//! Host-owned review acceptance journal. It shares BusinessStore's exclusive
//! owner lock; it does not change the strict business schema or grant authority.
use crate::{contract::*, sqlite::Db};
use std::path::Path;

const META: &str = "CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)";
const REVIEWS: &str = "CREATE TABLE reviews(intent_id TEXT PRIMARY KEY,plan_id TEXT NOT NULL UNIQUE,binding_digest TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('prepared','claimed','sealed')))";
pub(crate) struct ReviewLifecycle(Db);
fn io<T>(value: crate::sqlite::Result<T>) -> Result<T, ContractError> {
    value.map_err(|_| ContractError::Storage)
}
impl ReviewLifecycle {
    pub(crate) fn open(path: &Path, workspace: &str) -> Result<Self, ContractError> {
        let mut journal = path.as_os_str().to_os_string();
        journal.push(".reviews-v1.sqlite");
        let journal = std::path::PathBuf::from(journal);
        let exists = match std::fs::symlink_metadata(&journal) {
            Ok(metadata) if metadata.file_type().is_file() => true,
            Ok(_) => return Err(ContractError::Storage),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => false,
            Err(_) => return Err(ContractError::Storage),
        };
        let db = io(Db::open(
            journal.to_str().ok_or(ContractError::InvalidIdentity)?,
            false,
            !exists,
        ))?;
        io(db.query("PRAGMA journal_mode=WAL", &[]))?;
        io(db.exec("PRAGMA synchronous=FULL", &[]))?;
        {
            // File existence is not an initialization receipt: SQLite may have
            // created it before its first schema transaction was committed.
            // The enclosing BusinessStore owner lock and this BEGIN IMMEDIATE
            // exclude another initializer. Recover only a genuinely empty,
            // unversioned schema, without deleting/replacing the database.
            let tx = io(db.transaction())?;
            let schema = io(db.query("SELECT name FROM sqlite_master", &[]))?;
            let version = io(db.query("PRAGMA user_version", &[]))?;
            let version = version.first().and_then(|row| row[0].as_deref());
            if schema.is_empty() && version == Some("0") {
                io(db.exec(META, &[]))?;
                io(db.exec(REVIEWS, &[]))?;
                io(db.exec("INSERT INTO meta VALUES('version','1')", &[]))?;
                io(db.exec("INSERT INTO meta VALUES('workspace',?)", &[workspace]))?;
                io(db.exec("PRAGMA user_version=1", &[]))?;
            } else if !matches!(version, Some("0" | "1")) {
                return Err(ContractError::InvalidVersion);
            }
            io(tx.commit())?;
        }
        for (name, ddl) in [("meta", META), ("reviews", REVIEWS)] {
            let rows = io(db.query(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?;
            if rows.len() != 1 || rows[0][0].as_deref() != Some(ddl) {
                return Err(ContractError::InvalidVersion);
            }
        }
        let meta = io(db.query("SELECT key,value FROM meta ORDER BY key", &[]))?;
        if meta
            != vec![
                vec![Some("version".into()), Some("1".into())],
                vec![Some("workspace".into()), Some(workspace.into())],
            ]
        {
            return Err(ContractError::InvalidVersion);
        }
        Ok(Self(db))
    }
    pub(crate) fn prepare(
        &self,
        command: &CommandEnvelope,
        binding: &str,
    ) -> Result<(), ContractError> {
        let tx = io(self.0.transaction())?;
        io(self.0.exec(
            "INSERT INTO reviews VALUES(?,?,?,'prepared')",
            &[&command.intent_id, &command.plan_id, binding],
        ))?;
        io(tx.commit())
    }
    pub(crate) fn claim(
        &self,
        command: &CommandEnvelope,
        binding: &str,
    ) -> Result<(), ContractError> {
        let tx = io(self.0.transaction())?;
        let changed = io(self.0.exec("UPDATE reviews SET state='claimed' WHERE intent_id=? AND plan_id=? AND binding_digest=? AND state='prepared'", &[&command.intent_id, &command.plan_id, binding]))?;
        if changed != 1 {
            return Err(ContractError::InvalidAuthority);
        }
        io(tx.commit())
    }
    /// Linearizes against claim. A sealed preview can never be confirmed later.
    /// Missing legacy records and claimed records are deliberately inconclusive.
    pub(crate) fn seal_unclaimed(&self, intent: &str) -> Result<bool, ContractError> {
        let tx = io(self.0.transaction())?;
        io(self.0.exec(
            "UPDATE reviews SET state='sealed' WHERE intent_id=? AND state='prepared'",
            &[intent],
        ))?;
        let rows = io(self
            .0
            .query("SELECT state FROM reviews WHERE intent_id=?", &[intent]))?;
        let sealed = rows.first().and_then(|row| row[0].as_deref()) == Some("sealed");
        io(tx.commit())?;
        Ok(sealed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);

    struct Files(std::path::PathBuf);
    impl Files {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "muyon-review-init-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            std::fs::create_dir(&path).unwrap();
            Self(path)
        }
        fn business(&self) -> std::path::PathBuf {
            self.0.join("business.sqlite")
        }
        fn journal(&self) -> std::path::PathBuf {
            self.0.join("business.sqlite.reviews-v1.sqlite")
        }
        fn raw(&self) -> Db {
            Db::open(self.journal().to_str().unwrap(), false, true).unwrap()
        }
        fn open(&self) -> ReviewLifecycle {
            ReviewLifecycle::open(&self.business(), "workspace").unwrap()
        }
    }
    impl Drop for Files {
        fn drop(&mut self) {
            std::fs::remove_dir_all(&self.0).unwrap();
        }
    }

    #[test]
    fn empty_file_from_interrupted_creation_initializes_without_replacement() {
        let files = Files::new();
        std::fs::File::create(files.journal()).unwrap();
        let review = files.open();
        assert!(!review.seal_unclaimed("missing").unwrap());
        drop(review);
        drop(files.open());
    }

    #[test]
    fn uncommitted_ddl_reopens_and_initializes_the_original_database() {
        let files = Files::new();
        {
            let db = files.raw();
            db.query("PRAGMA journal_mode=WAL", &[]).unwrap();
            let transaction = db.transaction().unwrap();
            db.exec(META, &[]).unwrap();
            db.exec(REVIEWS, &[]).unwrap();
            db.exec("INSERT INTO meta VALUES('version','1')", &[])
                .unwrap();
            // Owner disappears before the initialization COMMIT. SQLite rolls
            // back this same transaction when its connection is closed/reopened.
            drop(transaction);
        }
        let review = files.open();
        assert!(review
            .0
            .query("SELECT * FROM reviews", &[])
            .unwrap()
            .is_empty());
    }

    #[test]
    fn committed_claims_are_preserved_and_partial_committed_schema_is_refused() {
        let files = Files::new();
        {
            let review = files.open();
            review
                .0
                .exec(
                    "INSERT INTO reviews VALUES('accepted','plan','binding','claimed')",
                    &[],
                )
                .unwrap();
        }
        {
            let review = files.open();
            assert!(!review.seal_unclaimed("accepted").unwrap());
            assert_eq!(
                review
                    .0
                    .query("SELECT state FROM reviews WHERE intent_id='accepted'", &[])
                    .unwrap()[0][0]
                    .as_deref(),
                Some("claimed")
            );
        }
        // Never repair or reset an existing committed partial/foreign schema.
        let partial = Files::new();
        {
            let db = partial.raw();
            db.exec(META, &[]).unwrap();
        }
        assert!(matches!(
            ReviewLifecycle::open(&partial.business(), "workspace"),
            Err(ContractError::InvalidVersion)
        ));
        assert_eq!(
            partial
                .raw()
                .query("SELECT count(*) FROM sqlite_master WHERE type='table'", &[])
                .unwrap()[0][0]
                .as_deref(),
            Some("1")
        );
        let marked = Files::new();
        {
            let db = marked.raw();
            db.exec("PRAGMA user_version=1", &[]).unwrap();
        }
        assert!(matches!(
            ReviewLifecycle::open(&marked.business(), "workspace"),
            Err(ContractError::InvalidVersion)
        ));
        assert!(marked
            .raw()
            .query("SELECT name FROM sqlite_master", &[])
            .unwrap()
            .is_empty());
    }
}
