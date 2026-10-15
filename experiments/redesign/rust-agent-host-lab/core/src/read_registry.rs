//! Host-installed file read handler for the synthetic private store. Catalog
//! metadata never chooses filesystem paths or projection fields.
use crate::{field, Json, RawRead, ReadHandler};
use muyon_core_agent_lab::{identifier, store, Result};
use std::path::{Path, PathBuf};
pub struct PhysicalReadHandler {
    dir: PathBuf,
    file: String,
    key_argument: String,
    expected_key: String,
    fields: Vec<String>,
    optional_array: Option<(String, String)>,
    required_arguments: std::collections::BTreeMap<String, Json>,
}
impl PhysicalReadHandler {
    pub fn require_argument(mut self, key: &str, value: Json) -> Result<Self> {
        if !identifier(key) || value.encode().len() > 256 {
            return Err("physical_argument_config".into());
        }
        self.required_arguments.insert(key.into(), value);
        Ok(self)
    }
    pub fn new(
        dir: &Path,
        file: &str,
        key_argument: &str,
        expected_key: &str,
        fields: Vec<String>,
        optional_array: Option<(String, String)>,
    ) -> Result<Self> {
        store::validate_dir(dir)?;
        if !identifier(file)
            || !identifier(key_argument)
            || expected_key.is_empty()
            || expected_key.len() > 128
            || fields.is_empty()
            || fields.len() > 16
            || fields.iter().any(|f| !identifier(f))
        {
            return Err("physical_handler_config".into());
        }
        Ok(Self {
            dir: dir.into(),
            file: file.into(),
            key_argument: key_argument.into(),
            expected_key: expected_key.into(),
            fields,
            optional_array,
            required_arguments: std::collections::BTreeMap::new(),
        })
    }
}
impl ReadHandler for PhysicalReadHandler {
    fn read(&mut self, args: &Json) -> Result<RawRead> {
        for (key, value) in &self.required_arguments {
            if field(args, key)? != value {
                return Err("physical_argument_scope".into());
            }
        }
        if field(args, &self.key_argument)?.string()? != self.expected_key {
            return Err("physical_record_scope".into());
        }
        store::validate_dir(&self.dir)?;
        let raw =
            muyon_plugin_contract_lab::parse(store::read(&self.dir.join(&self.file))?.as_bytes())?;
        let mut selected = std::collections::BTreeMap::new();
        for name in &self.fields {
            selected.insert(name.clone(), field(&raw, name)?.clone());
        }
        if let Some((argument, field_name)) = &self.optional_array {
            if args.object()?.get(argument) != Some(&Json::Bool(true)) {
                selected.insert(field_name.clone(), Json::Array(Vec::new()));
            }
        }
        Ok(RawRead {
            raw,
            projection: Json::Object(selected),
        })
    }
}
