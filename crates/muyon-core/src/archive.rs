//! Bounded ZIP32 metadata parsing. No decompression or content-integrity claim.
use crate::contract::{ArchiveEntry, ArchiveMethod, ContractError, FileSource, Revision};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use unicode_normalization::UnicodeNormalization;

pub const MAX_MEMBER_BYTES: u64 = 30 * 1024 * 1024;
pub const MAX_ARCHIVE_BYTES: u64 = 150 * 1024 * 1024;
pub const MAX_MEMBERS: usize = 10_000;
type Result<T> = std::result::Result<T, ContractError>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArchiveMember {
    pub name: String,
    pub method: ArchiveMethod,
    pub crc32: u32,
    pub data_offset: u64,
    pub compressed_length: u64,
    pub expanded_length: u64,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArchiveManifest {
    pub archive_length: u64,
    pub archive_digest: String,
    /// Directory records are validated, but only regular members are exposed.
    pub entries: Vec<ArchiveMember>,
}
impl ArchiveManifest {
    /// Binds parsed immutable bytes to the source blob. This does not authenticate
    /// a FileSource/lease; only the trusted owner can resolve its actual authority.
    pub fn to_contract_entries(&self, source: &FileSource) -> Result<Vec<ArchiveEntry>> {
        source.validate()?;
        if source.blob.byte_length.value() != self.archive_length
            || source.blob.digest != self.archive_digest
        {
            return Err(ContractError::BindingMismatch);
        }
        self.entries
            .iter()
            .map(|m| {
                let entry = ArchiveEntry {
                    snapshot_id: source.snapshot_id.clone(),
                    name: m.name.clone(),
                    method: m.method.clone(),
                    crc32: m.crc32,
                    data_offset: Revision::new(m.data_offset),
                    compressed_length: Revision::new(m.compressed_length),
                    expanded_length: Revision::new(m.expanded_length),
                };
                entry.validate_for(source)?;
                Ok(entry)
            })
            .collect()
    }
}
fn invalid<T>() -> Result<T> {
    Err(ContractError::InvalidPayload)
}
fn slice(b: &[u8], p: usize, n: usize) -> Result<&[u8]> {
    b.get(p..p.checked_add(n).ok_or(ContractError::InvalidPayload)?)
        .ok_or(ContractError::InvalidPayload)
}
fn u16_at(b: &[u8], p: usize) -> Result<u16> {
    Ok(u16::from_le_bytes(slice(b, p, 2)?.try_into().unwrap()))
}
fn u32_at(b: &[u8], p: usize) -> Result<u32> {
    Ok(u32::from_le_bytes(slice(b, p, 4)?.try_into().unwrap()))
}
fn extras(b: &[u8]) -> Result<()> {
    let mut p = 0;
    let mut seen = BTreeSet::new();
    while p < b.len() {
        let id = u16_at(b, p)?;
        let size = u16_at(b, p + 2)? as usize;
        let data = slice(b, p + 4, size)?;
        if !seen.insert(id) {
            return invalid();
        }
        match id {
            // Extended timestamps: known flags only; CEN may contain mtime only.
            0x5455
                if !data.is_empty()
                    && data[0] & !7 == 0
                    && (size == 1 + 4 * (data[0].count_ones() as usize)
                        || (size == 5 && data[0] & 1 != 0)) => {}
            // Info-ZIP Unix UID/GID v1. Ownership is never restored.
            0x7875 if size >= 3 && data[0] == 1 => {
                let uid = data[1] as usize;
                let gid_pos = 2 + uid;
                if uid == 0 || uid > 8 || gid_pos >= size {
                    return invalid();
                }
                let gid = data[gid_pos] as usize;
                if gid == 0 || gid > 8 || gid_pos + 1 + gid != size {
                    return invalid();
                }
            }
            _ => return Err(ContractError::Unsupported),
        }
        p += 4 + size;
    }
    Ok(())
}
fn member_name(raw: &[u8], flags: u16) -> Result<(String, bool)> {
    if raw.is_empty() || raw.len() > 1024 {
        return invalid();
    }
    // Without EFS only ASCII is supported; do not guess a legacy code page.
    if flags & 0x800 == 0 && !raw.is_ascii() {
        return Err(ContractError::Unsupported);
    }
    let name = std::str::from_utf8(raw).map_err(|_| ContractError::InvalidPayload)?;
    let directory = name.ends_with('/');
    let key = if directory {
        &name[..name.len() - 1]
    } else {
        name
    };
    if key.is_empty()
        || key.contains(['\\', ':'])
        || key.chars().any(char::is_control)
        || key
            .split('/')
            .any(|p| p.is_empty() || p == "." || p == "..")
    {
        return invalid();
    }
    // Preserve actual member bytes; reject aliases after canonical normalization.
    Ok((name.to_owned(), directory))
}

pub fn parse_archive(b: &[u8]) -> Result<ArchiveManifest> {
    if b.len() as u64 > MAX_ARCHIVE_BYTES {
        return Err(ContractError::TextLimit);
    }
    if b.len() < 22 {
        return invalid();
    }
    let eocd = (b.len().saturating_sub(22 + 65535)..=b.len() - 22)
        .rev()
        .find(|&p| {
            u32_at(b, p).ok() == Some(0x06054b50)
                && u16_at(b, p + 20)
                    .ok()
                    .is_some_and(|n| p + 22 + n as usize == b.len())
        })
        .ok_or(ContractError::InvalidPayload)?;
    let count = u16_at(b, eocd + 10)? as usize;
    let cd_len = u32_at(b, eocd + 12)? as usize;
    let cd_start = u32_at(b, eocd + 16)? as usize;
    if u16_at(b, eocd + 4)? != 0
        || u16_at(b, eocd + 6)? != 0
        || u16_at(b, eocd + 8)? as usize != count
        || count == 65535
        || cd_len == u32::MAX as usize
        || cd_start == u32::MAX as usize
    {
        return Err(ContractError::Unsupported);
    }
    if count > MAX_MEMBERS {
        return Err(ContractError::TextLimit);
    }
    if cd_start.checked_add(cd_len) != Some(eocd) {
        return invalid();
    }
    let central = slice(b, cd_start, cd_len)?;
    let mut p = 0;
    let mut names = BTreeSet::new();
    let mut files = BTreeSet::new();
    let mut ranges = Vec::new();
    let mut entries = Vec::new();
    let mut expanded_total = 0u64;
    for _ in 0..count {
        let record_start = p;
        slice(central, p, 46)?;
        if u32_at(central, p)? != 0x02014b50 {
            return invalid();
        }
        let creator = u16_at(central, p + 4)? >> 8;
        let version = u16_at(central, p + 6)?;
        let flags = u16_at(central, p + 8)?;
        let method = u16_at(central, p + 10)?;
        let crc = u32_at(central, p + 16)?;
        let compressed = u32_at(central, p + 20)? as usize;
        let expanded = u32_at(central, p + 24)? as u64;
        let name_len = u16_at(central, p + 28)? as usize;
        let extra_len = u16_at(central, p + 30)? as usize;
        let comment_len = u16_at(central, p + 32)? as usize;
        let attrs = u32_at(central, p + 38)?;
        let local = u32_at(central, p + 42)? as usize;
        if ![0, 3].contains(&creator)
            || ![10, 20].contains(&version)
            || flags & !0x080e != 0
            || ![0, 8].contains(&method)
            || (method == 0 && flags & 6 != 0)
            || (method == 8 && version != 20)
            || u16_at(central, p + 34)? != 0
            || compressed == u32::MAX as usize
            || expanded == u32::MAX as u64
            || local == u32::MAX as usize
        {
            return Err(ContractError::Unsupported);
        }
        if expanded > MAX_MEMBER_BYTES {
            return Err(ContractError::TextLimit);
        }
        expanded_total += expanded;
        if expanded_total > MAX_ARCHIVE_BYTES {
            return Err(ContractError::TextLimit);
        }
        let raw_name = slice(central, p + 46, name_len)?;
        let (name, directory) = member_name(raw_name, flags)?;
        extras(slice(central, p + 46 + name_len, extra_len)?)?;
        slice(central, p + 46 + name_len + extra_len, comment_len)?;
        p += 46 + name_len + extra_len + comment_len;
        let key: String = name.trim_end_matches('/').nfc().collect();
        if !names.insert(key.clone()) {
            return invalid();
        }
        if !directory {
            files.insert(key);
        }
        let unix_type = (attrs >> 16) & 0xf000;
        // archive 4.0.9 declares DOS creator but preserves UNIX mode bits.
        // Inspect those bits for both accepted hosts instead of ignoring them.
        if attrs & 0x8 != 0
            || ![0, 0x4000, 0x8000].contains(&unix_type)
            || (unix_type == 0x4000 && !directory)
            || (unix_type == 0x8000 && directory)
            || (attrs & 0x10 != 0 && !directory)
        {
            return invalid();
        }
        if (method == 0 && compressed as u64 != expanded)
            || (directory && (expanded != 0 || crc != 0))
        {
            return invalid();
        }
        let locals = slice(b, 0, cd_start)?;
        slice(locals, local, 30)?;
        if u32_at(locals, local)? != 0x04034b50
            || u16_at(locals, local + 4)? != version
            || u16_at(locals, local + 6)? != flags
            || u16_at(locals, local + 8)? != method
            || slice(locals, local + 10, 4)? != slice(central, record_start + 12, 4)?
            || u16_at(locals, local + 26)? as usize != name_len
        {
            return invalid();
        }
        let lextra = u16_at(locals, local + 28)? as usize;
        if slice(locals, local + 30, name_len)? != raw_name {
            return invalid();
        }
        extras(slice(locals, local + 30 + name_len, lextra)?)?;
        let data_start = local + 30 + name_len + lextra;
        slice(locals, data_start, compressed)?;
        let data_end = data_start + compressed;
        let expected = [crc, compressed as u32, expanded as u32];
        let mut end = data_end;
        if flags & 8 == 0 {
            for (i, value) in expected.iter().enumerate() {
                if u32_at(locals, local + 14 + 4 * i)? != *value {
                    return invalid();
                }
            }
        } else {
            for (i, value) in expected.iter().enumerate() {
                let actual = u32_at(locals, local + 14 + 4 * i)?;
                if actual != 0 && actual != *value {
                    return invalid();
                }
            }
            // Signed and unsigned descriptors are both legal. Match the entire
            // tuple, including the rare case CRC equals the descriptor signature.
            let matches = |start| {
                expected
                    .iter()
                    .enumerate()
                    .all(|(i, v)| u32_at(locals, start + 4 * i).ok() == Some(*v))
            };
            if u32_at(locals, data_end).ok() == Some(0x08074b50) && matches(data_end + 4) {
                end += 16;
            } else if matches(data_end) {
                end += 12;
            } else {
                return invalid();
            }
        }
        ranges.push((local, end));
        if !directory {
            entries.push(ArchiveMember {
                name,
                method: if method == 0 {
                    ArchiveMethod::Stored
                } else {
                    ArchiveMethod::Deflated
                },
                crc32: crc,
                data_offset: data_start as u64,
                compressed_length: compressed as u64,
                expanded_length: expanded,
            });
        }
    }
    if p != central.len() {
        return invalid();
    }
    for name in &names {
        for (i, _) in name.match_indices('/') {
            if files.contains(&name[..i]) {
                return invalid();
            }
        }
    }
    ranges.sort_unstable();
    // A strict contiguous ZIP32 envelope excludes hidden/unindexed local records,
    // prepended executables and unexplained padding as unsupported combinations.
    let mut end = 0;
    for (start, next) in ranges {
        if start != end || next <= start {
            return invalid();
        }
        end = next;
    }
    if end != cd_start {
        return invalid();
    }
    Ok(ArchiveManifest {
        archive_length: b.len() as u64,
        archive_digest: Sha256::digest(b)
            .iter()
            .map(|v| format!("{v:02x}"))
            .collect(),
        entries,
    })
}

/// Feed the actual decoded stream, then call finish before publishing anything.
pub struct DecodedEntryValidator {
    expected_length: u64,
    expected_crc: u32,
    length: u64,
    crc: u32,
    failed: bool,
}
impl DecodedEntryValidator {
    pub fn new(member: &ArchiveMember) -> Self {
        Self {
            expected_length: member.expanded_length,
            expected_crc: member.crc32,
            length: 0,
            crc: !0,
            failed: false,
        }
    }
    pub fn update(&mut self, bytes: &[u8]) -> Result<()> {
        self.length = self.length.saturating_add(bytes.len() as u64);
        if self.failed || self.length > self.expected_length || self.length > MAX_MEMBER_BYTES {
            self.failed = true;
            return Err(ContractError::TextLimit);
        }
        for byte in bytes {
            self.crc ^= *byte as u32;
            for _ in 0..8 {
                self.crc = (self.crc >> 1) ^ (0xedb88320 & (0u32.wrapping_sub(self.crc & 1)));
            }
        }
        Ok(())
    }
    pub fn finish(self) -> Result<()> {
        if self.failed || self.length != self.expected_length || !self.crc != self.expected_crc {
            return Err(ContractError::BindingMismatch);
        }
        Ok(())
    }
}
