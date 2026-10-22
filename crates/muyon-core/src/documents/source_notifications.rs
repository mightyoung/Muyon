//! Same-transaction metadata-only outbox for the actual Artifacts source hook.
//! Requires fixed resolver0e85c6e9 plus real library/harness composition by B.
use super::{identity::valid_id, DocumentRef};
use crate::{
    business::BusinessStore,
    contract::{ContractError, Revision},
    sqlite::Transaction,
};
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};

type Result<T> = std::result::Result<T, ContractError>;
const SOURCE: &str = "artifact_local_evidence_sources_v1";
const NAME: &str = "document_source_notifications_v1";
const DDL: &str = "CREATE TABLE document_source_notifications_v1(project_id TEXT NOT NULL REFERENCES projects(id),actor_id TEXT NOT NULL,object_id TEXT NOT NULL,generation TEXT NOT NULL,pending INTEGER NOT NULL CHECK(pending IN(0,1)),PRIMARY KEY(project_id,actor_id,object_id))";
const MAX_PAGE: usize = 256;

/// Trusted Runtime-routing metadata only, never source permission or content.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct DocumentSourceNotification {
    pub project_id: String,
    pub actor_id: String,
    pub object_id: String,
    pub generation: Revision,
}
struct DocumentSourceRoute {
    document: DocumentRef,
    event: DocumentSourceNotification,
    expected: Option<(Revision, bool)>,
}
pub(super) struct DocumentSourceMutationPlan<'tx, 'db> {
    transaction: &'tx Transaction<'db>,
    documents: Vec<DocumentRef>,
    routes: Vec<DocumentSourceRoute>,
    notifications: bool,
    installed: bool,
}
pub(super) struct DocumentSourceMutationPostcondition {
    routes: Vec<DocumentSourceRoute>,
    batches: Vec<(DocumentRef, Vec<DocumentSourceNotification>)>,
    installed: bool,
}
fn sql<T>(value: crate::sqlite::Result<T>) -> Result<T> {
    value.map_err(|_| ContractError::Storage)
}
fn cell(row: &[Option<String>], index: usize) -> Result<&str> {
    row.get(index)
        .and_then(Option::as_deref)
        .ok_or(ContractError::StorageCorrupt)
}
fn ids(project: &str, actor: &str, object: &str) -> Result<()> {
    if [project, actor, object].iter().all(|id| valid_id(id)) {
        Ok(())
    } else {
        Err(ContractError::StorageCorrupt)
    }
}
impl BusinessStore {
    pub(super) fn document_notification_schema(&self) -> Result<bool> {
        let rows = sql(self.database().query("SELECT type,CASE WHEN length(CAST(sql AS BLOB))<=1024 THEN sql ELSE NULL END FROM sqlite_master WHERE name=?", &[NAME]))?;
        if rows.is_empty() {
            return Ok(false);
        }
        if rows.len() != 1 || cell(&rows[0], 0)? != "table" || cell(&rows[0], 1)? != DDL {
            return Err(ContractError::InvalidVersion);
        }
        Ok(true)
    }
    /// Routing projections only, not an authority decision. Freeze BEFORE the
    /// document/grant/blob writes and before the real owner's source UPDATEs.
    pub(super) fn prepare_document_source_mutation_in_transaction<'tx, 'db>(
        &self,
        tx: &'tx Transaction<'db>,
        changed: &[&DocumentRef],
    ) -> Result<DocumentSourceMutationPlan<'tx, 'db>> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::ScopeMismatch);
        }
        let notifications = self.document_notification_schema()?;
        let source = sql(self
            .database()
            .query("SELECT type FROM sqlite_master WHERE name=?", &[SOURCE]))?;
        let installed = !source.is_empty();
        if installed && (source.len() != 1 || cell(&source[0], 0)? != "table") {
            return Err(ContractError::InvalidVersion);
        }
        if !installed && notifications {
            return Err(ContractError::InvalidVersion);
        }
        let mut documents: Vec<DocumentRef> = Vec::new();
        let mut routes = Vec::new();
        for document in changed {
            if document.scope().workspace_id != self.workspace_id() {
                return Err(ContractError::ScopeMismatch);
            }
            let project = document
                .scope()
                .project_id
                .as_deref()
                .ok_or(ContractError::ScopeMismatch)?;
            if documents.iter().any(|old| {
                old.scope() == document.scope() && old.document_id() == document.document_id()
            }) {
                continue;
            }
            documents.push((**document).clone());
            if !installed {
                continue;
            }
            let mut actor = String::new();
            let mut object = String::new();
            loop {
                // Include inactive sources: their existing tombstones must not
                // be erased as a side effect of another source's invalidation.
                let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(actor_id AS BLOB))<=128 THEN actor_id ELSE NULL END,CASE WHEN length(CAST(object_id AS BLOB))<=128 THEN object_id ELSE NULL END FROM artifact_local_evidence_sources_v1 WHERE project_id=? AND document_id=? AND (actor_id>? OR (actor_id=? AND object_id>?)) ORDER BY actor_id,object_id LIMIT 256", &[project, document.document_id(), &actor, &actor, &object]))?;
                if rows.is_empty() {
                    break;
                }
                for row in rows {
                    actor = cell(&row, 0)?.into();
                    object = cell(&row, 1)?.into();
                    ids(project, &actor, &object)?;
                    let event = DocumentSourceNotification {
                        project_id: project.into(),
                        actor_id: actor.clone(),
                        object_id: object.clone(),
                        generation: Revision::new(1),
                    };
                    let expected = if notifications {
                        self.document_notification_state(&event)?
                    } else {
                        None
                    };
                    routes.push(DocumentSourceRoute {
                        document: (**document).clone(),
                        event,
                        expected,
                    });
                }
            }
        }
        Ok(DocumentSourceMutationPlan {
            transaction: tx,
            documents,
            routes,
            notifications,
            installed,
        })
    }
    fn verify_document_source_routes(
        &self,
        routes: &[DocumentSourceRoute],
        notifications: bool,
    ) -> Result<()> {
        for route in routes {
            let source = sql(self.database().query("SELECT 1 FROM artifact_local_evidence_sources_v1 s JOIN artifact_local_bindings_v1 b ON b.project_id=s.project_id AND b.actor_id=s.actor_id AND b.object_id=s.object_id WHERE s.project_id=? AND s.actor_id=? AND s.object_id=? AND s.document_id=?", &[&route.event.project_id, &route.event.actor_id, &route.event.object_id, route.document.document_id()]))?;
            if source.len() != 1 {
                return Err(ContractError::StorageCorrupt);
            }
            let actual = if notifications {
                self.document_notification_state(&route.event)?
            } else {
                None
            };
            if actual != route.expected {
                return Err(ContractError::StorageCorrupt);
            }
        }
        Ok(())
    }
    /// Called after the original mutation, still in its exact transaction. The
    /// REAL owner decides invalidity; core only preserves the frozen queue facts.
    pub(super) fn finish_document_source_mutation_in_transaction(
        &self,
        tx: &Transaction<'_>,
        plan: DocumentSourceMutationPlan<'_, '_>,
    ) -> Result<DocumentSourceMutationPostcondition> {
        if !tx.belongs_to(self.database()) || !std::ptr::eq(tx, plan.transaction) {
            return Err(ContractError::ScopeMismatch);
        }
        self.verify_document_source_notification_namespace(plan.notifications, plan.installed)?;
        self.verify_document_source_routes(&plan.routes, plan.notifications)?;
        let mut routes = plan.routes;
        let route_indices: BTreeMap<_, _> = routes
            .iter()
            .enumerate()
            .map(|(index, route)| {
                (
                    (
                        route.event.project_id.clone(),
                        route.event.actor_id.clone(),
                        route.event.object_id.clone(),
                    ),
                    index,
                )
            })
            .collect();
        let mut queued_indices = BTreeSet::new();
        let mut batches = Vec::new();
        let mut frozen = Vec::new();
        if plan.installed {
            for document in plan.documents {
                let affected =
                    self.invalidate_local_evidence_sources_in_transaction(tx, &document)?;
                let mut events = Vec::with_capacity(affected.len());
                for affected in affected {
                    ids(
                        &affected.project_id,
                        &affected.actor_id,
                        &affected.object_id,
                    )?;
                    let index = *route_indices
                        .get(&(
                            affected.project_id.clone(),
                            affected.actor_id.clone(),
                            affected.object_id.clone(),
                        ))
                        .ok_or(ContractError::StorageCorrupt)?;
                    if routes[index].document.scope() != document.scope()
                        || routes[index].document.document_id() != document.document_id()
                        || !queued_indices.insert(index)
                    {
                        return Err(ContractError::StorageCorrupt);
                    }
                    let old = routes[index].expected.clone();
                    let generation = match &old {
                        Some((generation, _)) => generation.next()?,
                        None => Revision::new(1),
                    };
                    let event = DocumentSourceNotification {
                        project_id: affected.project_id,
                        actor_id: affected.actor_id,
                        object_id: affected.object_id,
                        generation,
                    };
                    events.push(event.clone());
                    frozen.push((index, event, old));
                }
                batches.push((document, events));
            }
            // Owner source/binding triggers also precede all queue writes.
            self.verify_document_source_notification_namespace(plan.notifications, true)?;
            self.verify_document_source_routes(&routes, plan.notifications)?;
            if !plan.notifications {
                sql(self.database().exec(DDL, &[]))?;
            }
            for (index, event, old) in frozen {
                if self.document_notification_state(&event)? != old {
                    return Err(ContractError::StorageCorrupt);
                }
                sql(self.database().exec("INSERT INTO document_source_notifications_v1 VALUES(?,?,?,?,1) ON CONFLICT(project_id,actor_id,object_id) DO UPDATE SET generation=excluded.generation,pending=1", &[&event.project_id, &event.actor_id, &event.object_id, event.generation.as_str()]))?;
                routes[index].expected = Some((event.generation, true));
            }
        }
        let postcondition = DocumentSourceMutationPostcondition {
            routes,
            batches,
            installed: plan.installed,
        };
        self.verify_document_source_mutation_in_transaction(tx, &postcondition)?;
        Ok(postcondition)
    }
    pub(super) fn verify_document_source_mutation_in_transaction(
        &self,
        tx: &Transaction<'_>,
        postcondition: &DocumentSourceMutationPostcondition,
    ) -> Result<()> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::ScopeMismatch);
        }
        self.verify_document_source_notification_namespace(
            postcondition.installed,
            postcondition.installed,
        )?;
        self.verify_document_source_routes(&postcondition.routes, postcondition.installed)?;
        for (document, events) in &postcondition.batches {
            self.verify_document_source_notifications_in_transaction(tx, document, events)?;
        }
        Ok(())
    }
    pub(super) fn verify_document_source_notification_namespace(
        &self,
        notifications: bool,
        installed: bool,
    ) -> Result<()> {
        if self.document_notification_schema()? != notifications {
            return Err(ContractError::InvalidVersion);
        }
        let source = sql(self
            .database()
            .query("SELECT type FROM sqlite_master WHERE name=?", &[SOURCE]))?;
        if installed {
            if source.len() != 1 || cell(&source[0], 0)? != "table" {
                return Err(ContractError::InvalidVersion);
            }
        } else if !source.is_empty() {
            return Err(ContractError::InvalidVersion);
        }
        Ok(())
    }
    fn verify_document_notification_rows(
        &self,
        events: &[DocumentSourceNotification],
        pending: &str,
    ) -> Result<()> {
        if !events.is_empty() && !self.document_notification_schema()? {
            return Err(ContractError::StorageCorrupt);
        }
        for event in events {
            let rows = sql(self.database().query("SELECT 1 FROM document_source_notifications_v1 WHERE project_id=? AND actor_id=? AND object_id=? AND generation=? AND pending=?", &[&event.project_id, &event.actor_id, &event.object_id, event.generation.as_str(), pending]))?;
            if rows.len() != 1 {
                return Err(ContractError::StorageCorrupt);
            }
        }
        Ok(())
    }
    /// Read-only postcondition of the REAL owner's returned invalidations; this
    /// projects only exact inactive flags, never decodes grants/payloads or makes
    /// a source-authority decision. No owner schema/permission logic is copied.
    pub(super) fn verify_document_source_notifications_in_transaction(
        &self,
        tx: &Transaction<'_>,
        changed: &DocumentRef,
        events: &[DocumentSourceNotification],
    ) -> Result<()> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::ScopeMismatch);
        }
        self.verify_document_notification_rows(events, "1")?;
        for event in events {
            if changed.scope().workspace_id != self.workspace_id()
                || changed.scope().project_id.as_deref() != Some(event.project_id.as_str())
            {
                return Err(ContractError::ScopeMismatch);
            }
            let rows = sql(self.database().query("SELECT 1 FROM artifact_local_evidence_sources_v1 s JOIN artifact_local_bindings_v1 b ON b.project_id=s.project_id AND b.actor_id=s.actor_id AND b.object_id=s.object_id WHERE s.project_id=? AND s.actor_id=? AND s.object_id=? AND s.document_id=? AND s.active=0 AND b.active=0", &[&event.project_id, &event.actor_id, &event.object_id, changed.document_id()]))?;
            if rows.len() != 1 {
                return Err(ContractError::StorageCorrupt);
            }
        }
        Ok(())
    }
    /// Post-commit trusted Host call only. Nested calls during a source mutation
    /// fail to start a transaction; no Runtime event may be emitted before COMMIT.
    pub fn pending_document_source_notifications_trusted(
        &self,
        after: Option<&DocumentSourceNotification>,
        limit: usize,
    ) -> Result<Vec<DocumentSourceNotification>> {
        if limit == 0 || limit > MAX_PAGE {
            return Err(ContractError::TextLimit);
        }
        let tx = sql(self.database().transaction())?;
        self.document_schema()?;
        if !self.document_notification_schema()? {
            sql(tx.commit())?;
            return Ok(Vec::new());
        }
        let (project, actor, object) = match after {
            Some(cursor) => {
                ids(&cursor.project_id, &cursor.actor_id, &cursor.object_id)?;
                (
                    cursor.project_id.as_str(),
                    cursor.actor_id.as_str(),
                    cursor.object_id.as_str(),
                )
            }
            None => ("", "", ""),
        };
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(project_id AS BLOB))<=128 THEN project_id ELSE NULL END,CASE WHEN length(CAST(actor_id AS BLOB))<=128 THEN actor_id ELSE NULL END,CASE WHEN length(CAST(object_id AS BLOB))<=128 THEN object_id ELSE NULL END,CASE WHEN length(CAST(generation AS BLOB))<=20 THEN generation ELSE NULL END FROM document_source_notifications_v1 WHERE pending=1 AND (project_id>? OR (project_id=? AND (actor_id>? OR (actor_id=? AND object_id>?)))) ORDER BY project_id,actor_id,object_id LIMIT ?", &[project, project, actor, actor, object, &limit.to_string()]))?;
        let mut events = Vec::with_capacity(rows.len());
        for row in rows {
            ids(cell(&row, 0)?, cell(&row, 1)?, cell(&row, 2)?)?;
            let generation = Revision::parse(cell(&row, 3)?)?;
            if generation.value() == 0 {
                return Err(ContractError::StorageCorrupt);
            }
            events.push(DocumentSourceNotification {
                project_id: cell(&row, 0)?.into(),
                actor_id: cell(&row, 1)?.into(),
                object_id: cell(&row, 2)?.into(),
                generation,
            });
        }
        sql(tx.commit())?;
        Ok(events)
    }
    fn document_notification_state(
        &self,
        event: &DocumentSourceNotification,
    ) -> Result<Option<(Revision, bool)>> {
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(generation AS BLOB))<=20 THEN generation ELSE NULL END,pending FROM document_source_notifications_v1 WHERE project_id=? AND actor_id=? AND object_id=?", &[&event.project_id, &event.actor_id, &event.object_id]))?;
        if rows.is_empty() {
            return Ok(None);
        }
        if rows.len() != 1 {
            return Err(ContractError::StorageCorrupt);
        }
        let generation = Revision::parse(cell(&rows[0], 0)?)?;
        if generation.value() == 0 {
            return Err(ContractError::StorageCorrupt);
        }
        let pending = match cell(&rows[0], 1)? {
            "0" => false,
            "1" => true,
            _ => return Err(ContractError::StorageCorrupt),
        };
        Ok(Some((generation, pending)))
    }
    /// Call only after Runtime accepted the corresponding local notification.
    /// Keep tombstones: deleting an acked row could reuse generation1 (ABA).
    pub fn ack_document_source_notifications_trusted(
        &self,
        events: &[DocumentSourceNotification],
    ) -> Result<usize> {
        if events.len() > MAX_PAGE {
            return Err(ContractError::TextLimit);
        }
        if events.is_empty() {
            return Ok(0);
        }
        let tx = sql(self.database().transaction())?;
        self.document_schema()?;
        if !self.document_notification_schema()? {
            return Err(ContractError::NotFound);
        }
        // Freeze EVERY supplied target before ANY write, including stale and
        // missing rows. sqlite changes()==0 can hide a successful trigger that
        // deleted a tombstone and then RAISE(IGNORE)'d the original UPDATE.
        let mut frozen = Vec::with_capacity(events.len());
        for event in events {
            ids(&event.project_id, &event.actor_id, &event.object_id)?;
            if event.generation.value() == 0 {
                return Err(ContractError::InvalidRevision);
            }
            frozen.push((event, self.document_notification_state(event)?));
        }
        let mut acknowledged = 0;
        for event in events {
            let changed = sql(self.database().exec("UPDATE document_source_notifications_v1 SET pending=0 WHERE project_id=? AND actor_id=? AND object_id=? AND generation=? AND pending=1", &[&event.project_id, &event.actor_id, &event.object_id, event.generation.as_str()]))?;
            if changed > 1 {
                return Err(ContractError::StorageCorrupt);
            }
            acknowledged += changed;
        }
        if !self.document_notification_schema()? {
            return Err(ContractError::StorageCorrupt);
        }
        for (event, before) in frozen {
            let expected = before.map(|(generation, pending)| {
                let matched = events.iter().any(|input| {
                    input.project_id == event.project_id
                        && input.actor_id == event.actor_id
                        && input.object_id == event.object_id
                        && input.generation == generation
                });
                (generation, pending && !matched)
            });
            if self.document_notification_state(event)? != expected {
                return Err(ContractError::StorageCorrupt);
            }
        }
        tx.commit().map_err(|_| ContractError::Unknown)?;
        Ok(acknowledged)
    }
}
