use muyon_core_agent_lab::{
    store::{self, DirectoryLock},
    Result,
};
use muyon_plugin_contract_lab::{object, parse, string, Json};
use std::path::{Path, PathBuf};
pub struct NativeStore {
    pub dir: PathBuf,
    _lock: DirectoryLock,
    receipts: Vec<Json>,
    facts: Json,
}
impl NativeStore {
    pub fn create(dir: &Path) -> Result<Self> {
        store::create_dir(dir)?;
        let lock = store::lock(dir)?;
        let result = Self {
            dir: dir.into(),
            _lock: lock,
            receipts: Vec::new(),
            facts: object([
                ("external_read", Json::Bool(false)),
                ("unknown_source", Json::Bool(false)),
            ]),
        };
        result.persist()?;
        Ok(result)
    }
    pub fn open(dir: &Path) -> Result<Self> {
        let lock = store::lock(dir)?;
        let value = parse(store::read(&dir.join("native.db"))?.as_bytes())?;
        let map = value.object()?;
        if map.get("version") != Some(&string("native-read-1")) {
            return Err("native_store_version".into());
        }
        let receipts = map
            .get("receipts")
            .ok_or("native_receipts")?
            .array()?
            .to_vec();
        let facts = map.get("facts").ok_or("native_facts")?.clone();
        Ok(Self {
            dir: dir.into(),
            _lock: lock,
            receipts,
            facts,
        })
    }
    fn persist(&self) -> Result<()> {
        store::atomic(
            &self.dir,
            "native.db",
            &object([
                ("version", string("native-read-1")),
                ("receipts", Json::Array(self.receipts.clone())),
                ("facts", self.facts.clone()),
            ])
            .encode(),
        )
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
        self.facts = object([
            ("external_read", Json::Bool(true)),
            ("unknown_source", Json::Bool(true)),
        ]);
        self.persist()
    }
    pub fn begin(&mut self, identity: Json, binding: Json) -> Result<usize> {
        if self.receipts.len() >= 64 {
            return Err("receipt_limit".into());
        }
        if self
            .receipts
            .iter()
            .any(|r| r.object().ok().and_then(|m| m.get("identity")) == Some(&identity))
        {
            return Err("duplicate_receipt".into());
        }
        let index = self.receipts.len();
        self.receipts.push(object([
            ("identity", identity),
            ("binding", binding),
            ("status", string("running")),
            ("raw", Json::Null),
        ]));
        self.persist()?;
        Ok(index)
    }
    pub fn finish(&mut self, index: usize, raw: Json, success: bool) -> Result<()> {
        let r = self.receipts.get_mut(index).ok_or("receipt_missing")?;
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
        self.persist()
    }
    pub fn ledger(&self, status: &str, body: &[u8]) -> Result<()> {
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
