module leveldb

import os

#include <fcntl.h>
#include <unistd.h>

fn C.fsync(int) int

// sync_file makes the bytes already written to fd durable on the device. A
// stdio flush only hands them to the kernel which is not far enough for
// anything that is about to be referred to by durable metadata.
fn sync_file(fd int) ! {
	if C.fsync(fd) != 0 {
		return error('leveldb: fsync failed: ${os.posix_get_error_msg(C.errno)}')
	}
}

// sync_dir makes a directory's entries durable. A newly created file needs this
// as well as its own sync: contents that survive a crash are no use while the
// name they live under doesn't.
fn sync_dir(path string) ! {
	fd := C.open(&char(path.str), C.O_RDONLY, 0)
	if fd < 0 {
		return error('leveldb: cannot open directory to sync it: ${path}: ${os.posix_get_error_msg(C.errno)}')
	}
	res := C.fsync(fd)
	// close() is free to overwrite errno and the fsync result is the one worth
	// reporting.
	code := C.errno
	C.close(fd)
	if res != 0 {
		return error('leveldb: directory fsync failed: ${path}: ${os.posix_get_error_msg(code)}')
	}
}
