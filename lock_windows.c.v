module leveldb

fn C.CreateFileW(&u16, u32, u32, voidptr, u32, u32, voidptr) voidptr
fn C.CloseHandle(voidptr) bool

// acquire_db_lock opens the LOCK file allowing no sharing, which is how Windows
// spells an exclusive claim on a file: every later opener, in this process or
// another, is refused by the OS until the handle closes.
fn acquire_db_lock(path string) !DBLock {
	handle := C.CreateFileW(path.to_wide(), C.GENERIC_READ | C.GENERIC_WRITE, 0, unsafe { nil },
		C.OPEN_ALWAYS, C.FILE_ATTRIBUTE_NORMAL, unsafe { nil })
	if handle == voidptr(-1) {
		return error('leveldb: cannot lock database, it may already be open elsewhere: ${path}')
	}
	return DBLock{
		handle: i64(handle)
	}
}

fn (mut l DBLock) release() {
	if l.handle < 0 {
		return
	}
	C.CloseHandle(voidptr(l.handle))
	l.handle = -1
}
