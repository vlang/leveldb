module leveldb

#include <fcntl.h>
#include <unistd.h>
#include <sys/file.h>

fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.flock(int, int) int

// acquire_db_lock takes the exclusive flock on the LOCK file. The lock is
// associated with the open file description and remains held until the
// descriptor is closed.
fn acquire_db_lock(path string) !DBLock {
	fd := C.open(&char(path.str), C.O_RDWR | C.O_CREAT, 0o644)
	if fd < 0 {
		return error('leveldb: cannot open lock file: ${path}')
	}
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		C.close(fd)
		return error('leveldb: database is already open elsewhere: ${path}')
	}
	return DBLock{
		handle: fd
	}
}

fn (mut l DBLock) release() {
	if l.handle < 0 {
		return
	}
	// Closing the descriptor drops the lock with it.
	C.close(int(l.handle))
	l.handle = -1
}
