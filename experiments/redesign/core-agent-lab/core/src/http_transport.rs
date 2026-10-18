//! Bounded loopback-only synthetic HTTP transport. No live endpoint support.
use crate::{model::ProviderControl, Result};
use std::{net::SocketAddr, time::Duration};

#[derive(Clone, Debug)]
pub struct LoopbackHttpConfig {
    pub address: SocketAddr,
    pub idle_timeout: Duration,
    pub total_timeout: Duration,
    /// Total HTTP response bytes, including its headers.
    pub max_response_bytes: usize,
}

pub struct LoopbackHttpTransport { config: LoopbackHttpConfig }
impl LoopbackHttpTransport {
    pub fn new(config: LoopbackHttpConfig) -> Result<Self> {
        if !config.address.ip().is_loopback() || config.address.port() == 0
            || config.idle_timeout.is_zero() || config.total_timeout.is_zero()
            || config.total_timeout > Duration::from_secs(30)
            || config.idle_timeout > config.total_timeout
            || config.max_response_bytes == 0 || config.max_response_bytes > 73728 {
            return Err("http_loopback_config".into());
        }
        Ok(Self { config })
    }

    /// `review` must recheck current authority for these exact body bytes.
    /// Caller owns durable admission/accounting; this transport never retries.
    pub fn exchange(&mut self, _payload: &[u8], _control: &mut dyn ProviderControl,
        _review: &mut dyn FnMut(&[u8]) -> Result<()>) -> Result<Vec<u8>> {
        let _ = &self.config;
        Err("http_transport_not_implemented".into())
    }
}
