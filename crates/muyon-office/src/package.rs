//! Bounded, in-memory OOXML package access and byte-preserving member rewrite.

use crate::error::{OfficeError, Result};
use sha2::{Digest, Sha256};
use std::io::{Cursor, Read, Write};
use zip::{write::SimpleFileOptions, CompressionMethod, ZipArchive, ZipWriter};

#[derive(Debug, Clone)]
pub struct Limits {
    pub max_archive: usize,
    pub max_entries: usize,
    pub max_part: usize,
    pub max_expanded: usize,
    pub max_xml_depth: usize,
    pub max_xml_tokens: usize,
    pub max_text: usize,
    pub max_sections: usize,
}

impl Default for Limits {
    /// Mirrors the bounds of the existing Kotlin preview so behaviour stays comparable.
    fn default() -> Self {
        Self {
            max_archive: 16 * 1024 * 1024,
            max_entries: 1024,
            max_part: 4 * 1024 * 1024,
            max_expanded: 32 * 1024 * 1024,
            max_xml_depth: 128,
            max_xml_tokens: 1_000_000,
            max_text: 200_000,
            max_sections: 64,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Docx,
    Xlsx,
    Pptx,
}

/// Result of a successful edit. The host owns authorization / CAS / durable publication;
/// this is only the candidate plus evidence tying it to its exact source.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditReceipt {
    pub candidate: Vec<u8>,
    pub source_sha256: String,
    pub candidate_sha256: String,
    /// The single package member whose bytes changed.
    pub changed_part: String,
    /// Byte range replaced inside `changed_part` (in the source member).
    pub changed_range: (usize, usize),
}

pub struct Package {
    bytes: Vec<u8>,
    names: Vec<String>,
    pub(crate) limits: Limits,
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let d = Sha256::digest(bytes);
    d.iter().map(|b| format!("{b:02x}")).collect()
}

fn safe_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with('/')
        && !name.contains('\\')
        && !name.contains('\0')
        && name.split('/').all(|s| s != ".." && s != "." )
}

fn read_limited<R: Read>(r: &mut R, limit: usize) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    r.take(limit as u64 + 1)
        .read_to_end(&mut out)
        .map_err(|_| OfficeError::MalformedArchive)?;
    if out.len() > limit {
        return Err(OfficeError::LimitExceeded("part size"));
    }
    Ok(out)
}

impl Package {
    pub fn open(bytes: &[u8], limits: &Limits) -> Result<Package> {
        if bytes.len() > limits.max_archive {
            return Err(OfficeError::LimitExceeded("archive size"));
        }
        let mut archive =
            ZipArchive::new(Cursor::new(bytes)).map_err(|_| OfficeError::MalformedArchive)?;
        if archive.len() > limits.max_entries {
            return Err(OfficeError::LimitExceeded("entry count"));
        }
        let mut names = Vec::with_capacity(archive.len());
        let mut total = 0usize;
        for i in 0..archive.len() {
            let mut f = archive.by_index(i).map_err(|_| OfficeError::MalformedArchive)?;
            let name = f.name().map_err(|_| OfficeError::UnsafePath)?.into_owned();
            if !safe_name(&name) {
                return Err(OfficeError::UnsafePath);
            }
            if names.contains(&name) {
                return Err(OfficeError::DuplicatePart);
            }
            if f.is_dir() {
                names.push(name);
                continue;
            }
            // Declared sizes are not trusted: count real decompressed bytes with a hard cap.
            let remaining = limits.max_expanded.saturating_sub(total);
            let n = std::io::copy(&mut f.by_ref().take(remaining as u64 + 1), &mut std::io::sink())
                .map_err(|_| OfficeError::MalformedArchive)? as usize;
            total += n;
            if total > limits.max_expanded {
                return Err(OfficeError::LimitExceeded("expanded size"));
            }
            names.push(name);
        }
        Ok(Package { bytes: bytes.to_vec(), names, limits: limits.clone() })
    }

    pub fn part_names(&self) -> &[String] {
        &self.names
    }
    pub fn has_part(&self, name: &str) -> bool {
        self.names.iter().any(|n| n == name)
    }
    pub fn source_sha256(&self) -> String {
        sha256_hex(&self.bytes)
    }

    pub fn format(&self) -> Option<Format> {
        if self.has_part("word/document.xml") {
            Some(Format::Docx)
        } else if self.has_part("xl/workbook.xml") {
            Some(Format::Xlsx)
        } else if self.has_part("ppt/presentation.xml") {
            Some(Format::Pptx)
        } else {
            None
        }
    }

    pub fn read_part(&self, name: &str) -> Result<Vec<u8>> {
        let mut archive = ZipArchive::new(Cursor::new(self.bytes.as_slice()))
            .map_err(|_| OfficeError::MalformedArchive)?;
        let mut f = archive
            .by_name(name)
            .map_err(|_| OfficeError::MissingPart(name.to_owned()))?;
        read_limited(&mut f, self.limits.max_part)
    }

    /// Rewrite exactly one member. Every other member is copied raw (compressed bytes, CRC,
    /// method and order preserved), so untouched members are byte-identical by construction.
    pub fn rewrite_part(
        &self,
        target: &str,
        new_content: &[u8],
        changed_range: (usize, usize),
    ) -> Result<EditReceipt> {
        let mut archive = ZipArchive::new(Cursor::new(self.bytes.as_slice()))
            .map_err(|_| OfficeError::MalformedArchive)?;
        let mut writer = ZipWriter::new(Cursor::new(Vec::new()));
        let mut replaced = false;
        for i in 0..archive.len() {
            let file = archive.by_index_raw(i).map_err(|_| OfficeError::MalformedArchive)?;
            if file.name().map(|n| n == target).unwrap_or(false) {
                let mut options = SimpleFileOptions::default()
                    .compression_method(CompressionMethod::Deflated);
                if let Some(t) = file.last_modified() {
                    options = options.last_modified_time(t);
                }
                if let Some(mode) = file.unix_mode() {
                    options = options.unix_permissions(mode);
                }
                let name = file.name().map_err(|_| OfficeError::UnsafePath)?.into_owned();
                drop(file);
                writer
                    .start_file(name, options)
                    .map_err(|_| OfficeError::MalformedArchive)?;
                writer.write_all(new_content).map_err(|_| OfficeError::MalformedArchive)?;
                replaced = true;
            } else {
                writer.raw_copy_file(file).map_err(|_| OfficeError::MalformedArchive)?;
            }
        }
        if !replaced {
            return Err(OfficeError::MissingPart(target.to_owned()));
        }
        let candidate = writer
            .finish()
            .map_err(|_| OfficeError::MalformedArchive)?
            .into_inner();
        if candidate.len() > self.limits.max_archive {
            return Err(OfficeError::LimitExceeded("archive size"));
        }
        Ok(EditReceipt {
            source_sha256: self.source_sha256(),
            candidate_sha256: sha256_hex(&candidate),
            candidate,
            changed_part: target.to_owned(),
            changed_range,
        })
    }

    pub(crate) fn tokens(&self, part: &str) -> Result<(Vec<u8>, Vec<crate::xml::Tok>)> {
        let bytes = self.read_part(part)?;
        let toks = crate::xml::tokenize(
            &bytes,
            &crate::xml::XmlLimits {
                max_depth: self.limits.max_xml_depth,
                max_tokens: self.limits.max_xml_tokens,
            },
        )?;
        Ok((bytes, toks))
    }
}

/// Splice `replacement` over `range`, leaving every other byte untouched.
pub(crate) fn splice(src: &[u8], range: (usize, usize), replacement: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(src.len() - (range.1 - range.0) + replacement.len());
    out.extend_from_slice(&src[..range.0]);
    out.extend_from_slice(replacement);
    out.extend_from_slice(&src[range.1..]);
    out
}
