module fs

import os

fn test_write_fd_all_rejects_invalid_fd() {
	if _ := write_fd_all(-1, 'lost'.bytes()) {
		panic('write_fd_all accepted an invalid file descriptor')
	}
}

fn test_write_file_synced_reports_missing_parent() {
	parent := os.join_path(os.temp_dir(), 'vleveldb_missing_sync_parent')
	os.rmdir_all(parent) or {}
	path := os.join_path(parent, 'CURRENT.tmp')
	if _ := write_file_synced(path, 'MANIFEST-000001\n'.bytes()) {
		panic('write_file_synced accepted a missing parent directory')
	}
}
