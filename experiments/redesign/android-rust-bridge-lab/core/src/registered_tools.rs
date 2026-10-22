//! Nonsecret route settings callback; no change to credential/model owner callbacks.
use muyon_web_search_lab::chat_route::{ConfiguredToolRoute, ToolSettingsSource};
use std::sync::Arc;
#[uniffi::export(with_foreign)]
pub trait RegisteredToolSettings: Send + Sync {
    fn snapshot(&self) -> String;
}
struct Settings(Arc<dyn RegisteredToolSettings>);
impl ToolSettingsSource for Settings {
    fn snapshot(&self) -> muyon_web_search_lab::Result<muyon_web_search_lab::Json> {
        let s = self.0.snapshot();
        if s.len() > 1024 {
            return Err("search_config_corrupt".into());
        }
        muyon_web_search_lab::parse(s.as_bytes())
    }
}
pub(crate) fn route(
    settings: Arc<dyn RegisteredToolSettings>,
    synthetic: bool,
) -> Arc<dyn muyon_rust_agent_host_lab::service_tools::RegisteredChatRoute> {
    Arc::new(ConfiguredToolRoute {
        settings: Arc::new(Settings(settings)),
        synthetic,
    })
}
