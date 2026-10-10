module table

import os
import leveldb.internal.internalkey
import leveldb.internal.options { Options }

fn test_table_roundtrip() {
	path := os.join_path(os.temp_dir(), 'vleveldb_table_test.ldb')
	os.rm(path) or {}
	opts := Options{}
	mut tw := new_table_writer(path, opts) or { panic(err) }
	mut keys := [][]u8{}
	for i in 0 .. 1000 {
		keys << internalkey.make_internal_key('key${i:06}'.bytes(), u64(i + 1), .val)
	}
	for k in keys {
		pk := internalkey.parse_internal_key(k) or { panic(err) }
		tw.add(k, 'value_of_${pk.ukey.bytestr()}'.bytes()) or { panic(err) }
	}
	tw.finish() or { panic(err) }
	tr := new_table_reader(path, opts) or { panic(err) }
	for i in 0 .. 1000 {
		seek := internalkey.make_internal_key('key${i:06}'.bytes(), internalkey.max_seq,
			internalkey.key_type_seek)
		hit := tr.get(seek) or { panic(err) }
		assert hit.found, 'missing key${i:06}'
		assert hit.kt == .val
		assert hit.value == 'value_of_key${i:06}'.bytes()
	}
	seek_missing := internalkey.make_internal_key('nope'.bytes(), internalkey.max_seq,
		internalkey.key_type_seek)
	miss := tr.get(seek_missing) or { panic(err) }
	assert !miss.found, 'unexpected hit'
	os.rm(path) or {}
}
