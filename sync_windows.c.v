module leveldb

import os

#include <io.h>

fn C._commit(int) int

// sync_file commits the file data buffered behind the CRT descriptor. It covers
// the same ground as fsync() for a file's contents and nothing beyond that.
fn sync_file(fd int) ! {
	if C._commit(fd) != 0 {
		return error('leveldb: _commit failed: ${os.posix_get_error_msg(C.errno)}')
	}
}

// sync_dir does nothing on Windows. There is no equivalent of fsync() on a
// directory through the CRT descriptor API used here and what NTFS guarantees
// about a created name reaching the device alongside the file's contents has
// not been established for this code. The metadata half of the create then
// publish ordering is therefore not covered on this platform.
fn sync_dir(path string) ! {
}
