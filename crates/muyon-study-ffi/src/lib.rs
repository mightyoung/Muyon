//! Purpose-specific bridge; does not change existing Muyon provider gates.
use muyon_core::study::StudyStore;
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};
uniffi::setup_scaffolding!();
#[derive(uniffi::Object)]
pub struct StudyEngine {
    store: Mutex<Option<StudyStore>>,
}
#[uniffi::export]
impl StudyEngine {
    #[uniffi::constructor]
    pub fn open(path: String) -> Arc<Self> {
        Arc::new(Self {
            store: Mutex::new(StudyStore::open(&path).ok()),
        })
    }
    pub fn request(&self, input: String) -> String {
        let result = (|| {
            if input.len() > 32 * 1024 * 1024 {
                return Err("请求过大".to_string());
            }
            let c: Value = serde_json::from_str(&input).map_err(|_| "请求不是有效JSON")?;
            self.store
                .lock()
                .map_err(|_| "数据服务不可用")?
                .as_ref()
                .ok_or("数据库无法打开，请检查存储空间")?
                .command(c)
        })();
        match result {
            Ok(data) => json!({"ok":true,"data":data}),
            Err(error) => json!({"ok":false,"error":error}),
        }
        .to_string()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn malformed_and_unavailable_are_not_success() {
        let s = StudyEngine::open("/nonexistent/path/study.sqlite".into());
        assert_eq!(
            serde_json::from_str::<Value>(&s.request("{}".into())).unwrap()["ok"],
            false
        );
        assert_eq!(
            serde_json::from_str::<Value>(&s.request("not json".into())).unwrap()["ok"],
            false
        );
    }
}
