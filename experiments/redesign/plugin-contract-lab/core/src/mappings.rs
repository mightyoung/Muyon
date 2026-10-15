//! Private native declaration subset; metadata alone is never authority.
use crate::{Json, Result};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MappingKind { Research, Inquiry, Equipment }

#[derive(Clone, Debug)]
pub struct ReadDeclaration {
    pub bundle: Json,
    pub tool_id: String,
    pub operation: String,
    pub binding_id: String,
}

/// Refusing shell retained until the positive registration test is observed RED.
pub fn declaration(_kind: MappingKind) -> Result<ReadDeclaration> {
    Err("native_mapping_unsupported".into())
}
pub fn renamed_equipment(_seed: u32) -> Result<ReadDeclaration> {
    Err("native_mapping_unsupported".into())
}
