//! Private read-only Linux SQLite C ABI seam, adapted from atomic-business-lab.
//! No create/write API is exposed. Every query has row/cell budgets.
//! Connections and statements own their C handles; text buffers outlive statement finalization.
use std::{
    ffi::{c_char, c_int, c_void, CStr, CString},
    ptr,
};
#[repr(C)]
struct Sqlite {
    _private: [u8; 0],
}
#[repr(C)]
struct Statement {
    _private: [u8; 0],
}
#[link(name = "libsqlite3.so.0", kind = "dylib", modifiers = "+verbatim")]
unsafe extern "C" {
    fn sqlite3_open_v2(
        path: *const c_char,
        db: *mut *mut Sqlite,
        flags: c_int,
        vfs: *const c_char,
    ) -> c_int;
    fn sqlite3_close(db: *mut Sqlite) -> c_int;
    fn sqlite3_busy_timeout(db: *mut Sqlite, ms: c_int) -> c_int;
    fn sqlite3_prepare_v2(
        db: *mut Sqlite,
        sql: *const c_char,
        n: c_int,
        stmt: *mut *mut Statement,
        tail: *mut *const c_char,
    ) -> c_int;
    fn sqlite3_bind_parameter_count(stmt: *mut Statement) -> c_int;
    fn sqlite3_bind_text(
        stmt: *mut Statement,
        i: c_int,
        text: *const c_char,
        n: c_int,
        destroy: Option<unsafe extern "C" fn(*mut c_void)>,
    ) -> c_int;
    fn sqlite3_step(stmt: *mut Statement) -> c_int;
    fn sqlite3_column_count(stmt: *mut Statement) -> c_int;
    fn sqlite3_column_type(stmt: *mut Statement, i: c_int) -> c_int;
    fn sqlite3_column_text(stmt: *mut Statement, i: c_int) -> *const u8;
    fn sqlite3_column_bytes(stmt: *mut Statement, i: c_int) -> c_int;
    fn sqlite3_finalize(stmt: *mut Statement) -> c_int;
}
pub type Result<T> = std::result::Result<T, String>;
pub(super) struct Db {
    handle: *mut Sqlite,
}
struct Stmt<'a> {
    handle: *mut Statement,
    db: &'a Db,
    _text: Vec<CString>,
}
impl Drop for Stmt<'_> {
    fn drop(&mut self) {
        unsafe {
            sqlite3_finalize(self.handle);
        }
    }
}
impl Drop for Db {
    fn drop(&mut self) {
        unsafe {
            sqlite3_close(self.handle);
        }
    }
}
impl Db {
    pub(super) fn open_readonly(path: &str) -> Result<Self> {
        let path = CString::new(path).map_err(|_| "NUL path")?;
        let mut handle = ptr::null_mut();
        // READONLY=1, READWRITE=2, CREATE=4; deliberately no URI interpretation.
        let flags = 1;
        let rc = unsafe { sqlite3_open_v2(path.as_ptr(), &mut handle, flags, ptr::null()) };
        if handle.is_null() {
            return Err("supplier_sqlite_open".into());
        }
        let db = Self { handle };
        db.check(rc)?;
        db.check(unsafe { sqlite3_busy_timeout(handle, 250) })?;
        Ok(db)
    }
    fn error(&self, _rc: c_int) -> String {
        "supplier_sqlite_error".into()
    }
    fn check(&self, rc: c_int) -> Result<()> {
        if rc == 0 {
            Ok(())
        } else {
            Err(self.error(rc))
        }
    }
    fn prepare<'a>(&'a self, sql: &str, args: &[&str]) -> Result<Stmt<'a>> {
        let sql = CString::new(sql).map_err(|_| "NUL SQL")?;
        let mut handle = ptr::null_mut();
        let mut tail = ptr::null();
        let rc =
            unsafe { sqlite3_prepare_v2(self.handle, sql.as_ptr(), -1, &mut handle, &mut tail) };
        if rc != 0 {
            if !handle.is_null() {
                unsafe {
                    sqlite3_finalize(handle);
                }
            }
            return Err(self.error(rc));
        }
        if handle.is_null() {
            return Err("empty SQL".into());
        }
        let mut stmt = Stmt {
            handle,
            db: self,
            _text: Vec::new(),
        };
        if !unsafe { CStr::from_ptr(tail) }.to_bytes().is_empty() {
            return Err("multiple SQL statements refused".into());
        }
        if unsafe { sqlite3_bind_parameter_count(handle) } as usize != args.len() {
            return Err("parameter count mismatch".into());
        }
        for (i, arg) in args.iter().enumerate() {
            let text = CString::new(*arg).map_err(|_| "NUL text")?;
            let length = c_int::try_from(text.as_bytes().len()).map_err(|_| "text too long")?;
            self.check(unsafe {
                sqlite3_bind_text(handle, (i + 1) as c_int, text.as_ptr(), length, None)
            })?;
            stmt._text.push(text);
        }
        Ok(stmt)
    }
    pub(super) fn query(&self, sql: &str, args: &[&str]) -> Result<Vec<Vec<Option<String>>>> {
        let stmt = self.prepare(sql, args)?;
        let mut rows = Vec::new();
        loop {
            match unsafe { sqlite3_step(stmt.handle) } {
                101 => break,
                100 => {
                    if rows.len() >= 64 {
                        return Err("SQLite row budget".into());
                    }
                    let mut row = Vec::new();
                    for i in 0..unsafe { sqlite3_column_count(stmt.handle) } {
                        if unsafe { sqlite3_column_type(stmt.handle, i) } == 5 {
                            row.push(None);
                            continue;
                        }
                        let text = unsafe { sqlite3_column_text(stmt.handle, i) };
                        if text.is_null() {
                            return Err("SQLite text conversion failed".into());
                        }
                        let n = unsafe { sqlite3_column_bytes(stmt.handle, i) };
                        if n < 0 || n > 65536 {
                            return Err("SQLite cell budget".into());
                        }
                        let bytes = unsafe { std::slice::from_raw_parts(text, n as usize) };
                        row.push(Some(
                            String::from_utf8(bytes.to_vec())
                                .map_err(|_| "database invalid UTF-8")?,
                        ));
                    }
                    rows.push(row);
                }
                rc => return Err(stmt.db.error(rc)),
            }
        }
        // Finalize is also checked on successful evaluation, not silently ignored.
        let mut stmt = stmt;
        let rc = unsafe { sqlite3_finalize(stmt.handle) };
        stmt.handle = ptr::null_mut();
        self.check(rc)?;
        Ok(rows)
    }
}
