module leveldb

import os

fn write_fd_all(fd int, data []u8) ! {
	if fd < 0 {
		return error('leveldb: invalid file descriptor')
	}
	mut ptr := data.data
	mut remaining := data.len
	for remaining > 0 {
		C.errno = 0
		n := int(C.write(fd, ptr, remaining))
		if n < 0 {
			code := C.errno
			if code == C.EINTR {
				continue
			}
			return error('leveldb: write failed: ${os.posix_get_error_msg(code)}')
		}
		if n == 0 {
			return error('leveldb: write returned 0 bytes')
		}
		remaining -= n
		ptr = unsafe { &u8(voidptr(usize(ptr) + usize(n))) }
	}
}

fn write_file_synced(path string, data []u8) ! {
	mut f := os.open_file(path, 'wb', 0o644)!
	defer {
		f.close()
	}
	write_fd_all(f.fd, data)!
	sync_file(f.fd)!
}
