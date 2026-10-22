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
    record_ref: Option<Json>,
    type_argument: Option<String>,
    raw_limit: Option<usize>,
}
impl PhysicalReadHandler {
    pub(crate) fn service_bounded(mut self) -> Self {
        self.raw_limit = Some(8192);
        self
    }
    pub fn bind_record(mut self, reference: Json, type_argument: Option<String>) -> Result<Self> {
        crate::validate_reference(&reference)?;
        if field(&reference, "key")?.string()? != self.expected_key {
            return Err("physical_record_binding".into());
        }
        if let Some(argument) = &type_argument {
            if self.required_arguments.get(argument) != Some(field(&reference, "type")?) {
                return Err("physical_type_binding".into());
            }
        }
        self.record_ref = Some(reference);
        self.type_argument = type_argument;
        Ok(self)
    }

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
            record_ref: None,
            type_argument: None,
            raw_limit: None,
        })
    }
}
impl ReadHandler for PhysicalReadHandler {
    fn admit_read(&self, args: &Json, scope_refs: &[Json]) -> Result<()> {
        let record = self.record_ref.as_ref().ok_or("unbound_physical_record")?;
        if !scope_refs.contains(record) {
            return Err("physical_reference_scope".into());
        }
        if field(args, &self.key_argument)? != field(record, "key")? {
            return Err("physical_record_scope".into());
        }
        if let Some(argument) = &self.type_argument {
            if field(args, argument)? != field(record, "type")? {
                return Err("physical_argument_scope".into());
            }
        }
        for (key, value) in &self.required_arguments {
            if field(args, key)? != value {
                return Err("physical_argument_scope".into());
            }
        }
        Ok(())
    }
    fn read(&mut self, args: &Json) -> Result<RawRead> {
        let record = self.record_ref.clone().ok_or("unbound_physical_record")?;
        self.admit_read(args, &[record])?;
        for (key, value) in &self.required_arguments {
            if field(args, key)? != value {
                return Err("physical_argument_scope".into());
            }
        }
        if field(args, &self.key_argument)?.string()? != self.expected_key {
            return Err("physical_record_scope".into());
        }
        store::validate_dir(&self.dir)?;
        let source = if let Some(limit) = self.raw_limit {
            use std::io::Read;
            let path = self.dir.join(&self.file);
            let meta =
                std::fs::symlink_metadata(&path).map_err(|_| "physical_source_unavailable")?;
            if !meta.is_file() || meta.file_type().is_symlink() || meta.len() > limit as u64 {
                return Err("service_raw_budget".into());
            }
            let mut bytes = Vec::new();
            std::fs::File::open(path)
                .map_err(|_| "physical_source_unavailable")?
                .take(limit as u64 + 1)
                .read_to_end(&mut bytes)
                .map_err(|_| "physical_source_unavailable")?;
            if bytes.len() > limit {
                return Err("service_raw_budget".into());
            }
            String::from_utf8(bytes).map_err(|_| "physical_source_utf8")?
        } else {
            store::read(&self.dir.join(&self.file))?
        };
        let raw = muyon_plugin_contract_lab::parse(source.as_bytes())?;
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
