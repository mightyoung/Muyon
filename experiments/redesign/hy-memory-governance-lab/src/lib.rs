//! Isolated synthetic SQLite contract lab; not a production authority or sender.
use rusqlite::{params, Connection, OptionalExtension, TransactionBehavior};
use sha2::{Digest, Sha256};
use std::{path::Path, time::Duration};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    Denied,
    Absent,
    Unknown,
    Conflict,
    InvalidSpan,
    Redacted,
    Storage,
}
pub type Result<T> = std::result::Result<T, Error>;
impl From<rusqlite::Error> for Error {
    fn from(_: rusqlite::Error) -> Self {
        Self::Storage
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Member {
    pub id: String,
    pub revision: i64,
    pub authority: i64,
    pub policy: i64,
    pub digest: String,
    pub source_id: String,
    pub source_revision: i64,
    pub source_digest: String,
    pub source_authority: i64,
    pub generation: i64,
    pub scope: String,
    pub allowed_uses: String,
    pub lineage: String,
}
#[derive(Clone, Debug)]
pub struct Delete {
    pub request: String,
    pub member: Member,
    pub purpose: String,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Job {
    pub sink: String,
    pub status: String,
    pub attempts: i64,
    pub next_retry: i64,
    pub operation: String,
}
/// These process-exit hooks are only for synthetic child-process fault tests.
#[derive(Clone, Copy)]
pub enum Crash {
    None,
    BeforeCommit,
    AfterCommit,
    AfterSink,
}
#[derive(Clone, Debug)]
pub struct Segment {
    pub start: usize,
    pub end: usize,
    /// An allowlisted reason category, never caller supplied replacement text.
    pub replacement: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Quote {
    pub source_id: String,
    pub source_revision: i64,
    pub source_digest: String,
    pub segments: Vec<QuotedSegment>,
    pub display: String,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QuotedSegment {
    pub start: usize,
    pub end: usize,
    pub text: String,
    pub redacted: bool,
    pub reason: Option<String>,
}
#[derive(Clone, Debug)]
pub struct Claim {
    request: String,
    sink: String,
    target: String,
    attempt: i64,
    lease: i64,
}
fn digest(s: &str) -> String {
    format!("{:x}", Sha256::digest(s.as_bytes()))
}
fn identity(fields: &[String]) -> String {
    digest(
        &fields
            .iter()
            .map(|f| format!("{}:{}", f.len(), f))
            .collect::<String>(),
    )
}
struct State {
    member: Member,
    source_body: String,
    body: String,
    read: bool,
    manage: bool,
    tombstone: bool,
}
pub struct Lab {
    db: Connection,
}

fn state(db: &Connection, id: &str) -> Result<State> {
    let exists: bool = db.query_row(
        "SELECT EXISTS(SELECT 1 FROM memory WHERE id=?)",
        [id],
        |r| r.get(0),
    )?;
    if !exists {
        return Err(Error::Absent);
    }
    let state=db.query_row("SELECT m.id,m.revision,m.authority,m.policy,m.digest,m.source_id,s.revision,s.digest,s.authority,m.generation,m.scope,m.allowed_uses,m.lineage,s.body,
 m.memory_read,m.manager_allowed,m.disabled,m.expired,m.tombstone,m.unknown_state,s.allowed,s.tombstone,s.unknown_state,m.body
 FROM memory m JOIN sources s ON s.id=m.source_id WHERE m.id=?",[id],|r| {
  let member=Member{id:r.get(0)?,revision:r.get(1)?,authority:r.get(2)?,policy:r.get(3)?,digest:r.get(4)?,source_id:r.get(5)?,source_revision:r.get(6)?,source_digest:r.get(7)?,source_authority:r.get(8)?,generation:r.get(9)?,scope:r.get(10)?,allowed_uses:r.get(11)?,lineage:r.get(12)?};
  let unknown=r.get::<_,bool>(19)? || r.get::<_,bool>(22)?;
  let manage=r.get::<_,bool>(15)?;
  let read=r.get::<_,bool>(14)? && manage && !r.get::<_,bool>(16)? && !r.get::<_,bool>(17)? && !r.get::<_,bool>(18)? && r.get::<_,bool>(20)? && !r.get::<_,bool>(21)?;
  Ok((State{member,source_body:r.get(13)?,body:r.get(23)?,read,manage,tombstone:r.get(18)?},unknown))
 }).optional()?.ok_or(Error::Unknown)?;
    if state.1 {
        return Err(Error::Unknown);
    }
    Ok(state.0)
}
fn allow_read(s: &State, ticket: &Member) -> bool {
    s.read
        && digest(&s.body) == s.member.digest
        && &s.member == ticket
        && s.member.scope == "local"
        && s.member.allowed_uses == "context"
        && s.member.lineage == s.member.source_id
        && digest(&s.source_body) == s.member.source_digest
}
impl Lab {
    pub fn open(path: &Path) -> Result<Self> {
        let db = Connection::open(path)?;
        db.busy_timeout(Duration::from_secs(5))?;
        db.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;
CREATE TABLE IF NOT EXISTS sources(id TEXT PRIMARY KEY,revision INTEGER,digest TEXT,body TEXT,authority INTEGER DEFAULT 1,allowed INTEGER DEFAULT 1,tombstone INTEGER DEFAULT 0,unknown_state INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS memory(id TEXT PRIMARY KEY,revision INTEGER,authority INTEGER,policy INTEGER,digest TEXT,body TEXT,source_id TEXT,scope TEXT DEFAULT 'local',allowed_uses TEXT DEFAULT 'context',lineage TEXT,memory_read INTEGER DEFAULT 1,manager_allowed INTEGER DEFAULT 1,disabled INTEGER DEFAULT 0,expired INTEGER DEFAULT 0,tombstone INTEGER DEFAULT 0,unknown_state INTEGER DEFAULT 0,automatic INTEGER DEFAULT 1,generation INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS receipts(request TEXT PRIMARY KEY,payload TEXT NOT NULL,receipt TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS jobs(request TEXT,sink TEXT,target TEXT,generation INTEGER,status TEXT,attempts INTEGER DEFAULT 0,lease INTEGER DEFAULT 0,next_retry INTEGER DEFAULT 0,operation TEXT UNIQUE,PRIMARY KEY(request,sink));
CREATE TABLE IF NOT EXISTS sinks(target TEXT,sink TEXT,PRIMARY KEY(target,sink));
CREATE TABLE IF NOT EXISTS consumed(id INTEGER PRIMARY KEY,member_count INTEGER);")?;
        Ok(Self { db })
    }
    pub fn seed(&mut self, id: &str, body: &str) -> Result<Member> {
        let source = format!("source:{id}");
        let tx = self.db.transaction()?;
        tx.execute(
            "INSERT INTO sources(id,revision,digest,body) VALUES(?,1,?,?)",
            params![source, digest(body), body],
        )?;
        tx.execute("INSERT INTO memory(id,revision,authority,policy,digest,body,source_id,lineage) VALUES(?,1,1,1,?,?,?,?)",params![id,digest(body),body,source,source])?;
        for sink in ["vector", "cache"] {
            tx.execute("INSERT INTO sinks VALUES(?,?)", params![id, sink])?;
        }
        tx.commit()?;
        self.current(id)
    }
    pub fn current(&self, id: &str) -> Result<Member> {
        let s = state(&self.db, id)?;
        if !allow_read(&s, &s.member) {
            return Err(Error::Denied);
        }
        Ok(s.member)
    }
    /// Synthetic fixture mutations update independent state facts, never a shared valid bit.
    pub fn change(&mut self, id: &str, field: &str) -> Result<()> {
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let source: String =
            tx.query_row("SELECT source_id FROM memory WHERE id=?", [id], |r| {
                r.get(0)
            })?;
        let sql = match field {
            "revision" => "UPDATE memory SET revision=revision+1 WHERE id=?",
            "authority" => "UPDATE memory SET authority=authority+1 WHERE id=?",
            "policy" => "UPDATE memory SET policy=policy+1 WHERE id=?",
            "digest" => "UPDATE memory SET digest='changed' WHERE id=?",
            "unknown" => "UPDATE memory SET unknown_state=1 WHERE id=?",
            "automatic_closed" => "UPDATE memory SET automatic=0,policy=policy+1 WHERE id=?",
            "memory_read_closed" => "UPDATE memory SET memory_read=0,policy=policy+1 WHERE id=?",
            "revoked" => "UPDATE memory SET manager_allowed=0,authority=authority+1 WHERE id=?",
            "tombstone" => "UPDATE memory SET tombstone=1 WHERE id=?",
            "disabled" => "UPDATE memory SET disabled=1 WHERE id=?",
            "expired" => "UPDATE memory SET expired=1 WHERE id=?",
            "lineage" => "UPDATE memory SET lineage='unrelated-source' WHERE id=?",
            "scope" => "UPDATE memory SET scope='other-scope' WHERE id=?",
            "uses" => "UPDATE memory SET allowed_uses='other-purpose' WHERE id=?",
            "source_identity" => "UPDATE memory SET source_id='missing-source' WHERE id=?",
            "source_revision" | "source_digest" | "source_revoked" | "source_tombstone"
            | "source_unknown" => "",
            _ => return Err(Error::Denied),
        };
        if !sql.is_empty() {
            tx.execute(sql, [id])?;
        } else {
            let sql = match field {
                "source_revision" => "UPDATE sources SET revision=revision+1 WHERE id=?",
                "source_digest" => "UPDATE sources SET digest='changed' WHERE id=?",
                "source_revoked" => "UPDATE sources SET allowed=0,authority=authority+1 WHERE id=?",
                "source_tombstone" => "UPDATE sources SET tombstone=1 WHERE id=?",
                _ => "UPDATE sources SET unknown_state=1 WHERE id=?",
            };
            tx.execute(sql, [source])?;
        }
        tx.execute("UPDATE memory SET generation=generation+1 WHERE id=?", [id])?;
        tx.commit()?;
        Ok(())
    }
    pub fn delete(&mut self, d: &Delete, crash: Crash) -> Result<String> {
        let m = &d.member;
        let payload = identity(&[
            d.request.clone(),
            m.id.clone(),
            m.revision.to_string(),
            m.authority.to_string(),
            m.policy.to_string(),
            m.digest.clone(),
            m.source_id.clone(),
            m.source_revision.to_string(),
            m.source_digest.clone(),
            m.source_authority.to_string(),
            m.generation.to_string(),
            m.scope.clone(),
            m.allowed_uses.clone(),
            m.lineage.clone(),
            d.purpose.clone(),
        ]);
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let previous = tx
            .query_row(
                "SELECT payload,receipt FROM receipts WHERE request=?",
                [&d.request],
                |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)),
            )
            .optional()?;
        if let Some((old, receipt)) = previous {
            return if old == payload {
                Ok(receipt)
            } else {
                Err(Error::Conflict)
            };
        }
        let s = state(&tx, &m.id)?;
        if !s.manage || s.tombstone || s.member != *m || d.purpose != "manage" {
            return Err(Error::Denied);
        }
        tx.execute(
            "UPDATE memory SET tombstone=1,generation=generation+1 WHERE id=?",
            [&m.id],
        )?;
        if matches!(crash, Crash::BeforeCommit) {
            std::process::exit(71);
        }
        let generation = m.generation + 1;
        for sink in ["vector", "cache", "memory-body"] {
            let op = identity(&[
                d.request.clone(),
                sink.into(),
                m.id.clone(),
                generation.to_string(),
            ]);
            tx.execute("INSERT INTO jobs(request,sink,target,generation,status,operation) VALUES(?,?,?,?,'pending',?)",params![d.request,sink,m.id,generation,op])?;
        }
        let receipt = format!("blocked:{payload}");
        tx.execute(
            "INSERT INTO receipts VALUES(?,?,?)",
            params![d.request, payload, receipt],
        )?;
        tx.commit()?;
        if matches!(crash, Crash::AfterCommit) {
            std::process::exit(72);
        }
        Ok(receipt)
    }
    pub fn jobs(&self, request: &str) -> Result<Vec<Job>> {
        let mut q=self.db.prepare("SELECT sink,status,attempts,next_retry,operation FROM jobs WHERE request=? ORDER BY sink")?;
        let rows = q.query_map([request], |r| {
            Ok(Job {
                sink: r.get(0)?,
                status: r.get(1)?,
                attempts: r.get(2)?,
                next_retry: r.get(3)?,
                operation: r.get(4)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }
    /// `now` is a synthetic fixture clock; attempts fence old worker acknowledgements.
    pub fn claim(&mut self, request: &str, sink: &str, now: i64) -> Result<Option<Claim>> {
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let (target, status, lease, next, attempt): (String, String, i64, i64, i64) = tx
            .query_row(
            "SELECT target,status,lease,next_retry,attempts FROM jobs WHERE request=? AND sink=?",
            params![request, sink],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
        )?;
        if status == "done" {
            return Ok(None);
        }
        if (status == "claimed" && lease > now) || next > now {
            return Err(Error::Denied);
        }
        let lease = now + 10;
        let attempt = attempt + 1;
        tx.execute(
            "UPDATE jobs SET status='claimed',attempts=?,lease=? WHERE request=? AND sink=?",
            params![attempt, lease, request, sink],
        )?;
        tx.commit()?;
        Ok(Some(Claim {
            request: request.into(),
            sink: sink.into(),
            target,
            attempt,
            lease,
        }))
    }
    pub fn complete(&mut self, claim: &Claim, outcome: &str, crash: Crash) -> Result<()> {
        if !["done", "failed", "unknown"].contains(&outcome) {
            return Err(Error::Denied);
        }
        // Sink deletion is idempotent and separate from its durable acknowledgement.
        // A stale worker may repeat deletion, but cannot acknowledge another claim.
        if outcome == "done" {
            if claim.sink == "memory-body" {
                self.db.execute(
                    "UPDATE memory SET body='' WHERE id=? AND tombstone=1",
                    [&claim.target],
                )?;
            } else {
                self.db.execute(
                    "DELETE FROM sinks WHERE target=? AND sink=?",
                    params![claim.target, claim.sink],
                )?;
            }
        }
        if matches!(crash, Crash::AfterSink) {
            std::process::exit(73);
        }
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let verified = if outcome != "done" {
            true
        } else if claim.sink == "memory-body" {
            tx.query_row(
                "SELECT body='' AND tombstone=1 FROM memory WHERE id=?",
                [&claim.target],
                |r| r.get(0),
            )?
        } else {
            !tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM sinks WHERE target=? AND sink=?)",
                params![claim.target, claim.sink],
                |r| r.get::<_, bool>(0),
            )?
        };
        if !verified {
            return Err(Error::Unknown);
        }
        let changed=tx.execute("UPDATE jobs SET status=?,lease=0,next_retry=? WHERE request=? AND sink=? AND target=? AND attempts=? AND lease=? AND status='claimed'",params![outcome,if outcome=="done"{0}else{claim.lease},claim.request,claim.sink,claim.target,claim.attempt,claim.lease])?;
        if changed != 1 {
            return Err(Error::Denied);
        }
        tx.commit()?;
        Ok(())
    }
    pub fn work(
        &mut self,
        request: &str,
        sink: &str,
        now: i64,
        outcome: &str,
        crash: Crash,
    ) -> Result<()> {
        if let Some(claim) = self.claim(request, sink, now)? {
            self.complete(&claim, outcome, crash)?;
        }
        Ok(())
    }
    pub fn sink_exists(&self, id: &str, sink: &str) -> Result<bool> {
        Ok(self.db.query_row(
            "SELECT EXISTS(SELECT 1 FROM sinks WHERE target=? AND sink=?)",
            params![id, sink],
            |r| r.get(0),
        )?)
    }
    /// Final checks and synthetic consumption commit share the revocation write fence.
    pub fn consume(&mut self, members: &[Member]) -> Result<()> {
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        if members.is_empty() {
            return Err(Error::Denied);
        }
        for m in members {
            if !allow_read(&state(&tx, &m.id)?, m) {
                return Err(Error::Denied);
            }
        }
        tx.execute(
            "INSERT INTO consumed(member_count) VALUES(?)",
            [members.len() as i64],
        )?;
        tx.commit()?;
        Ok(())
    }
    pub fn consumed(&self) -> Result<i64> {
        Ok(self
            .db
            .query_row("SELECT count(*) FROM consumed", [], |r| r.get(0))?)
    }
    pub fn quote(&mut self, m: &Member, segments: &[Segment], continuous: bool) -> Result<Quote> {
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let s = state(&tx, &m.id)?;
        if !allow_read(&s, m) {
            return Err(Error::Denied);
        }
        let body = &s.source_body;
        let mut display = String::new();
        let mut previous = None;
        let mut rendered = Vec::new();
        for segment in segments {
            if segment.start >= segment.end
                || segment.end > body.len()
                || !body.is_char_boundary(segment.start)
                || !body.is_char_boundary(segment.end)
                || previous.is_some_and(|end| segment.start < end)
            {
                return Err(Error::InvalidSpan);
            }
            if continuous
                && (segment.replacement.is_some()
                    || previous.is_some_and(|end| segment.start != end))
            {
                return Err(Error::Redacted);
            }
            let text = if let Some(reason) = &segment.replacement {
                if !["sensitive", "credential"].contains(&reason.as_str()) {
                    return Err(Error::Redacted);
                }
                format!("[redacted:{reason}]")
            } else {
                body[segment.start..segment.end].into()
            };
            if !continuous && previous.is_some_and(|end| segment.start != end) {
                display.push_str("[omitted]");
            }
            display.push_str(&text);
            rendered.push(QuotedSegment {
                start: segment.start,
                end: segment.end,
                text,
                redacted: segment.replacement.is_some(),
                reason: segment.replacement.clone(),
            });
            previous = Some(segment.end);
        }
        tx.commit()?;
        Ok(Quote {
            source_id: m.source_id.clone(),
            source_revision: m.source_revision,
            source_digest: m.source_digest.clone(),
            segments: rendered,
            display,
        })
    }
}
