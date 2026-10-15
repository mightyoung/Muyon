//! Private Linux-only offline native host experiment. No real model or database.
pub const STUB_REACHED: &str = "NATIVE_HOST_STUB_REACHED";
pub fn native_read_probe() -> Result<usize, &'static str> { Err(STUB_REACHED) }
