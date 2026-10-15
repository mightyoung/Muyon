//! Small experimental store: the entire native.db snapshot is at most 64KiB,
//! matching the existing bounded JSON reader. A rejected finish retains the
//! durable running/unknown receipt, never a fabricated successful result.
use muyon_core_agent_lab::{
    identifier,
    store::{self, DirectoryLock},
    Result,
};
use muyon_plugin_contract_lab::{object, parse, string, Json};
use std::{
    collections::BTreeSet,
    path::{Path, PathBuf},
};
const MAX_SNAPSHOT: usize = 65536;
pub struct NativeStore {
    pub dir: PathBuf,
    _lock: DirectoryLock,
    receipts: Vec<Json>,
    facts: Json,
    poisoned: bool,
}
fn keys<'a>(
    value: &'a Json,
    expected: &[&str],
) -> Result<&'a std::collections::BTreeMap<String, Json>> {
    let m = value.object()?;
    if m.len() != expected.len() || expected.iter().any(|key| !m.contains_key(*key)) {
        return Err("native_store_shape".into());
    }
    Ok(m)
}
fn bounded_text<'a>(value: &'a Json, max: usize) -> Result<&'a str> {
    let text = value.string()?;
    if text.is_empty() || text.len() > max {
        return Err("native_store_text".into());
    }
    Ok(text)
}
fn validate_snapshot(receipts: &[Json], facts: &Json) -> Result<()> {
    let facts = keys(facts, &["external_read", "unknown_source"])?;
    for value in facts.values() {
        if !matches!(value, Json::Bool(_)) {
            return Err("native_facts_type".into());
        }
    }
    if facts["external_read"] != facts["unknown_source"]
        || (!receipts.is_empty() && facts["unknown_source"] != Json::Bool(true))
    {
        return Err("native_facts_inconsistent".into());
    }
    if receipts.len() > 64 {
        return Err("receipt_limit".into());
    }
    let mut invocations = BTreeSet::new();
    let mut identities = BTreeSet::new();
    for receipt in receipts {
        let r = keys(receipt, &["identity", "binding", "status", "raw"])?;
        let identity = keys(
            &r["identity"],
            &["owner", "invocation_id", "binding_id", "identity"],
        )?;
        if identity["owner"] != string("ToolRegistry") {
            return Err("native_receipt_owner".into());
        }
        for key in ["invocation_id", "binding_id", "identity"] {
            let v = bounded_text(&identity[key], 128)?;
            if !v
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"_.-".contains(&c))
            {
                return Err("native_receipt_identity".into());
            }
        }
        if !invocations.insert(identity["invocation_id"].encode())
            || !identities.insert(identity["identity"].encode())
        {
            return Err("duplicate_receipt".into());
        }
        let binding = keys(
            &r["binding"],
            &[
                "task",
                "attempt",
                "turn",
                "scope",
                "operation",
                "args",
                "authority",
                "scope_refs",
            ],
        )?;
        for key in ["task", "attempt"] {
            if !identifier(bounded_text(&binding[key], 64)?) {
                return Err("native_binding_identity".into());
            }
        }
        if binding["turn"].integer()? == 0 {
            return Err("native_binding_turn".into());
        }
        bounded_text(&binding["operation"], 256)?;
        bounded_text(&binding["scope"], 1024)?;
        binding["args"].object()?;
        if muyon_plugin_contract_lab::canonical_value(&binding["args"])? != binding["args"] {
            return Err("native_binding_args".into());
        }
        let a = keys(
            &binding["authority"],
            &[
                "allowed",
                "available",
                "scope_allowed",
                "bindings",
                "revision",
                "binding_revision",
                "source_revision",
                "rule_revision",
                "scope",
                "refs",
            ],
        )?;
        for key in ["allowed", "available", "scope_allowed"] {
            if a[key] != Json::Bool(true) {
                return Err("native_binding_authority".into());
            }
        }
        for key in [
            "revision",
            "binding_revision",
            "source_revision",
            "rule_revision",
            "scope",
        ] {
            bounded_text(&a[key], 1024)?;
        }
        if a["scope"] != binding["scope"] {
            return Err("native_binding_scope".into());
        }
        let allowed_bindings = a["bindings"].array()?;
        if allowed_bindings.len() > 128 || !allowed_bindings.contains(&identity["binding_id"]) {
            return Err("native_binding_authority".into());
        }
        for value in allowed_bindings {
            bounded_text(value, 128)?;
        }
        let refs = a["refs"].array()?;
        if refs.len() > 128 {
            return Err("native_binding_refs".into());
        }
        for reference in refs {
            crate::validate_reference(reference)?;
        }
        let required = binding["scope_refs"].array()?;
        if required.is_empty() || required.len() > 128 {
            return Err("native_binding_refs".into());
        }
        for reference in required {
            crate::validate_reference(reference)?;
            if !refs.contains(reference) {
                return Err("native_binding_refs".into());
            }
        }
        match r["status"].string()? {
            "running" if r["raw"] == Json::Null => {}
            "succeeded" => {}
            "failed" if matches!(r["raw"], Json::String(_)) => {}
            _ => return Err("native_receipt_status".into()),
        }
    }
    Ok(())
}
impl NativeStore {
    pub fn create(dir: &Path) -> Result<Self> {
        store::create_dir(dir)?;
        let lock = store::lock(dir)?;
        let mut result = Self {
            dir: dir.into(),
            _lock: lock,
            receipts: Vec::new(),
            facts: object([
                ("external_read", Json::Bool(false)),
                ("unknown_source", Json::Bool(false)),
            ]),
            poisoned: false,
        };
        result.write_candidate(Vec::new(), result.facts.clone())?;
        Ok(result)
    }
    pub fn open(dir: &Path) -> Result<Self> {
        let lock = store::lock(dir)?;
        let value = parse(store::read(&dir.join("native.db"))?.as_bytes())?;
        let map = keys(&value, &["version", "receipts", "facts"])?;
        if map["version"] != string("native-read-1") {
            return Err("native_store_version".into());
        }
        let receipts = map["receipts"].array()?.to_vec();
        let facts = map["facts"].clone();
        validate_snapshot(&receipts, &facts)?;
        Ok(Self {
            dir: dir.into(),
            _lock: lock,
            receipts,
            facts,
            poisoned: false,
        })
    }
    pub fn ensure_healthy(&self) -> Result<()> {
        if self.poisoned {
            Err("native_store_poisoned".into())
        } else {
            Ok(())
        }
    }
    fn write_candidate(&mut self, receipts: Vec<Json>, facts: Json) -> Result<()> {
        self.ensure_healthy()?;
        let write = (|| {
            validate_snapshot(&receipts, &facts)?;
            let snapshot = object([
                ("version", string("native-read-1")),
                ("receipts", Json::Array(receipts.clone())),
                ("facts", facts.clone()),
            ]);
            if snapshot.encoded_len()? > MAX_SNAPSHOT {
                return Err("native_store_budget".into());
            }
            store::atomic(&self.dir, "native.db", &snapshot.encode())
        })();
        match write {
            Ok(()) => {
                self.receipts = receipts;
                self.facts = facts;
                Ok(())
            }
            Err(error) => {
                self.poisoned = true;
                Err(error)
            }
        }
    }
    pub fn facts(&self) -> &Json {
        &self.facts
    }
    pub fn receipt_count(&self) -> usize {
        self.receipts.len()
    }
    pub fn receipts(&self) -> &[Json] {
        &self.receipts
    }
    pub fn mark_read(&mut self) -> Result<()> {
        self.write_candidate(
            self.receipts.clone(),
            object([
                ("external_read", Json::Bool(true)),
                ("unknown_source", Json::Bool(true)),
            ]),
        )
    }
    pub fn begin(&mut self, identity: Json, binding: Json) -> Result<usize> {
        self.ensure_healthy()?;
        let index = self.receipts.len();
        let mut candidate = self.receipts.clone();
        candidate.push(object([
            ("identity", identity),
            ("binding", binding),
            ("status", string("running")),
            ("raw", Json::Null),
        ]));
        self.write_candidate(candidate, self.facts.clone())?;
        Ok(index)
    }
    pub fn finish(&mut self, index: usize, raw: Json, success: bool) -> Result<()> {
        self.ensure_healthy()?;
        let mut candidate = self.receipts.clone();
        let r = candidate.get_mut(index).ok_or("receipt_missing")?;
        let Json::Object(map) = r else {
            return Err("receipt_shape".into());
        };
        if map.get("status") != Some(&string("running")) {
            return Err("receipt_already_finished".into());
        }
        map.insert("raw".into(), raw);
        map.insert(
            "status".into(),
            string(if success { "succeeded" } else { "failed" }),
        );
        self.write_candidate(candidate, self.facts.clone())
    }
    pub fn ledger(&self, status: &str, body: &[u8]) -> Result<()> {
        self.ensure_healthy()?;
        if body.len() > 65536 {
            return Err("model_payload_limit".into());
        }
        store::atomic(
            &self.dir,
            "outbound.db",
            &object([
                ("status", string(status)),
                (
                    "bytes",
                    string(String::from_utf8(body.to_vec()).map_err(|_| "model_payload_utf8")?),
                ),
            ])
            .encode(),
        )
    }
}
