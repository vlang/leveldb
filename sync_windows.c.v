module leveldb

import os

#include <io.h>

fn C._get_osfhandle(int) voidptr
fn C.FlushFileBuffers(voidptr) bool
fn C.GetLastError() u32

fn sync_file(fd int) ! {
	handle := C._get_osfhandle(fd)
	if handle == voidptr(-1) {
		return error('leveldb: _get_osfhandle failed: ${os.posix_get_error_msg(C.errno)}')
	}
	if !C.FlushFileBuffers(handle) {
		return error('leveldb: FlushFileBuffers failed: ${os.get_error_msg(int(C.GetLastError()))}')
	}
}

// Windows has no documented equivalent of POSIX directory fsync through the CRT
// descriptor API used here. Keep file data sync mandatory and don't turn
// undocumented directory handle flushing into a hard failure condition.
fn sync_dir(path string) ! {
	_ = path
}
