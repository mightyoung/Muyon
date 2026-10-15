//! Request mapping only; transport implementation follows the preserved RED.
use crate::{Result,model::{ModelRequest,NativeMessage}};
pub fn encode_request(_request:&ModelRequest,_history:&[NativeMessage])->Result<Vec<u8>>{Ok(b"{}".to_vec())}
