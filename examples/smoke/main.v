module main

import os
import leveldb

fn main() {
	dir := os.join_path(os.temp_dir(), 'leveldb-smoke')
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}

	mut db := leveldb.open(dir, leveldb.Options{})!
	db.put('key'.bytes(), 'value'.bytes(), leveldb.WriteOptions{ sync: true })!
	db.close()!

	mut reopened := leveldb.open(dir, leveldb.Options{})!
	value := reopened.get('key'.bytes(), leveldb.ReadOptions{}) or {
		panic('the key written before the reopen is gone')
	}
	if value.bytestr() != 'value' {
		panic('expected "value", got "${value.bytestr()}"')
	}
	reopened.close()!

	println('smoke ok')
}
