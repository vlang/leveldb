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
	r := reopened.get('key'.bytes(), leveldb.ReadOptions{})!
	if !r.found {
		panic('the key written before the reopen is gone')
	}
	if r.value.bytestr() != 'value' {
		panic('expected "value", got "${r.value.bytestr()}"')
	}
	reopened.close()!

	println('smoke ok')
}
