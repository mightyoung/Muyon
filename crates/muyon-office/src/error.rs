//! Closed error set. Every failure is explicit; nothing is "best effort".

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OfficeError {
    /// A configured size / count / depth limit was exceeded.
    LimitExceeded(&'static str),
    /// ZIP member name is absolute, uses backslashes or contains `.` / `..` segments.
    UnsafePath,
    DuplicatePart,
    MalformedArchive,
    MalformedXml(&'static str),
    /// DOCTYPE / entity declarations are never accepted.
    DtdNotAllowed,
    UnsupportedEntity,
    MissingPart(String),
    UnsupportedFormat,
    /// The operation is outside the narrow supported subset (reason is fixed text).
    Unsupported(&'static str),
    /// No unique target matched the pre-declared `expected` value.
    NotFound,
    /// More than one target matched; the engine never guesses.
    Ambiguous,
    InvalidReplacement(&'static str),
}

impl core::fmt::Display for OfficeError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for OfficeError {}
pub type Result<T> = core::result::Result<T, OfficeError>;
