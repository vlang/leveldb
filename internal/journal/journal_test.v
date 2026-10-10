module journal

import os

fn test_journal_roundtrip() {
	path := os.join_path(os.temp_dir(), 'vleveldb_journal_test.log')
	os.rm(path) or {}
	mut w := new_journal_writer(path) or { panic(err) }
	small := 'hello world'.bytes()
	big := []u8{len: 100000, init: u8(index)}
	w.append(small) or { panic(err) }
	w.append(big) or { panic(err) }
	w.close()
	mut r := new_journal_reader(path) or { panic(err) }
	r1 := r.read_record() or { panic('missing record 1') }
	assert r1 == small
	r2 := r.read_record() or { panic('missing record 2') }
	assert r2 == big
	if _ := r.read_record() {
		panic('unexpected extra record')
	}
	os.rm(path) or {}
}
