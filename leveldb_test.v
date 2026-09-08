module leveldb

import os

fn test_varint() {
	mut buf := []u8{}
	values := [u64(0), 1, 127, 128, 300, 1 << 20, u64(1) << 40, u64(0xffffffffffffffff)]
	for v in values {
		buf.clear()
		append_uvarint(mut buf, v)
		got, n := read_uvarint(buf, 0) or { panic(err) }
		assert got == v
		assert n == buf.len
	}
}

fn test_crc32c() {
	assert crc32c('123456789'.bytes()) == u32(0xe3069283)
	crc := crc32c('hello'.bytes())
	assert unmask_crc(mask_crc(crc)) == crc
}

fn test_internal_key() {
	ik := make_internal_key('foo'.bytes(), 42, .val)
	pk := parse_internal_key(ik) or { panic(err) }
	assert pk.ukey == 'foo'.bytes()
	assert pk.seq == 42
	assert pk.kt == .val
	a := make_internal_key('a'.bytes(), 5, .val)
	b := make_internal_key('a'.bytes(), 9, .val)
	assert compare_internal(b, a) < 0
	c := make_internal_key('b'.bytes(), 1, .val)
	assert compare_internal(a, c) < 0
}

fn test_memdb() {
	mut m := new_memdb()
	m.put(make_internal_key('b'.bytes(), 1, .val), 'v1'.bytes())
	m.put(make_internal_key('a'.bytes(), 2, .val), 'v2'.bytes())
	m.put(make_internal_key('a'.bytes(), 3, .del), []u8{})
	value, kt := m.get(make_internal_key('a'.bytes(), max_seq, key_type_seek)) or {
		panic('missing')
	}
	assert kt == .del
	v2, kt2 := m.get(make_internal_key('b'.bytes(), max_seq, key_type_seek)) or { panic('missing') }
	assert kt2 == .val
	assert v2 == 'v1'.bytes()
	assert value.len == 0
}

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

fn test_bloom() {
	bf := new_bloom_filter(10)
	keys := [['abc'.bytes()], ['hello'.bytes()], ['world'.bytes()]].map(it[0])
	f := bf.create(keys)
	for k in keys {
		assert bf.may_contain(f, k)
	}
	mut false_positives := 0
	for i in 0 .. 1000 {
		if bf.may_contain(f, 'missing_key_${i}'.bytes()) {
			false_positives++
		}
	}
	assert false_positives < 50
}

fn test_table_roundtrip() {
	path := os.join_path(os.temp_dir(), 'vleveldb_table_test.ldb')
	os.rm(path) or {}
	opts := Options{}
	mut tw := new_table_writer(path, opts) or { panic(err) }
	mut keys := [][]u8{}
	for i in 0 .. 1000 {
		keys << make_internal_key('key${i:06}'.bytes(), u64(i + 1), .val)
	}
	for k in keys {
		pk := parse_internal_key(k) or { panic(err) }
		tw.add(k, 'value_of_${pk.ukey.bytestr()}'.bytes()) or { panic(err) }
	}
	tw.finish() or { panic(err) }
	tr := new_table_reader(path, opts) or { panic(err) }
	for i in 0 .. 1000 {
		seek := make_internal_key('key${i:06}'.bytes(), max_seq, key_type_seek)
		value, kt := tr.get(seek) or { panic('missing key${i:06}') }
		assert kt == .val
		assert value == 'value_of_key${i:06}'.bytes()
	}
	seek_missing := make_internal_key('nope'.bytes(), max_seq, key_type_seek)
	if _, _ := tr.get(seek_missing) {
		panic('unexpected hit')
	}
	os.rm(path) or {}
}

fn test_db_basic() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_db_basic')
	os.rmdir_all(dir) or {}
	mut db := open(dir, Options{}) or { panic(err) }
	db.put('name'.bytes(), 'eris'.bytes(), WriteOptions{}) or { panic(err) }
	db.put('lang'.bytes(), 'vlang'.bytes(), WriteOptions{}) or { panic(err) }
	v := db.get('name'.bytes(), ReadOptions{}) or { panic('missing name') }
	assert v == 'eris'.bytes()
	db.delete('name'.bytes(), WriteOptions{}) or { panic(err) }
	if _ := db.get('name'.bytes(), ReadOptions{}) {
		panic('deleted key still visible')
	}
	assert db.has('lang'.bytes(), ReadOptions{})
	db.close() or { panic(err) }
	os.rmdir_all(dir) or {}
}

fn test_db_reopen() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_db_reopen')
	os.rmdir_all(dir) or {}
	mut db := open(dir, Options{}) or { panic(err) }
	for i in 0 .. 500 {
		db.put('key${i:04}'.bytes(), 'value${i}'.bytes(), WriteOptions{}) or { panic(err) }
	}
	db.close() or { panic(err) }
	mut db2 := open(dir, Options{}) or { panic(err) }
	for i in 0 .. 500 {
		v := db2.get('key${i:04}'.bytes(), ReadOptions{}) or {
			panic('missing key${i} after reopen')
		}
		assert v == 'value${i}'.bytes()
	}
	db2.close() or { panic(err) }
	os.rmdir_all(dir) or {}
}

// A reopen recovers the previous session's journal into the memtable and then
// discards that journal. Unless the recovered data is written out, it exists
// only in memory and the open after this one finds nothing.
fn test_db_reopen_twice_keeps_data() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_db_reopen_twice')
	os.rmdir_all(dir) or {}
	mut db := open(dir, Options{}) or { panic(err) }
	db.put('first'.bytes(), 'one'.bytes(), WriteOptions{}) or { panic(err) }
	db.close() or { panic(err) }

	mut db2 := open(dir, Options{}) or { panic(err) }
	db2.put('second'.bytes(), 'two'.bytes(), WriteOptions{}) or { panic(err) }
	db2.close() or { panic(err) }

	mut db3 := open(dir, Options{}) or { panic(err) }
	v := db3.get('first'.bytes(), ReadOptions{}) or { panic('missing first after two reopens') }
	assert v == 'one'.bytes()
	v2 := db3.get('second'.bytes(), ReadOptions{}) or { panic('missing second after reopen') }
	assert v2 == 'two'.bytes()
	db3.close() or { panic(err) }
	os.rmdir_all(dir) or {}
}

// A session that only reads must leave the database as it found it.
fn test_db_read_only_reopen_keeps_data() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_db_readonly_reopen')
	os.rmdir_all(dir) or {}
	mut db := open(dir, Options{}) or { panic(err) }
	db.put('kept'.bytes(), 'value'.bytes(), WriteOptions{}) or { panic(err) }
	db.close() or { panic(err) }

	mut reader := open(dir, Options{}) or { panic(err) }
	reader.close() or { panic(err) }

	mut db2 := open(dir, Options{}) or { panic(err) }
	v := db2.get('kept'.bytes(), ReadOptions{}) or { panic('a read only session lost the data') }
	assert v == 'value'.bytes()
	db2.close() or { panic(err) }
	os.rmdir_all(dir) or {}
}

fn test_db_flush_and_compact() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_db_compact')
	os.rmdir_all(dir) or {}
	mut opts := Options{
		write_buffer_size: 32 * 1024
	}
	mut db := open(dir, opts) or { panic(err) }
	for i in 0 .. 3000 {
		db.put('key${i:06}'.bytes(), 'value_${i}_'.repeat(5).bytes(), WriteOptions{}) or {
			panic(err)
		}
	}
	for i in 0 .. 3000 {
		if i % 3 == 0 {
			db.delete('key${i:06}'.bytes(), WriteOptions{}) or { panic(err) }
		}
	}
	db.compact() or { panic(err) }
	for i in 0 .. 3000 {
		if i % 3 == 0 {
			if _ := db.get('key${i:06}'.bytes(), ReadOptions{}) {
				panic('deleted key${i} still visible')
			}
		} else {
			v := db.get('key${i:06}'.bytes(), ReadOptions{}) or { panic('missing key${i}') }
			assert v == 'value_${i}_'.repeat(5).bytes()
		}
	}
	db.close() or { panic(err) }
	mut db2 := open(dir, opts) or { panic(err) }
	v := db2.get('key000001'.bytes(), ReadOptions{}) or { panic('missing after reopen') }
	assert v == 'value_1_'.repeat(5).bytes()
	db2.close() or { panic(err) }
	os.rmdir_all(dir) or {}
}

fn test_db_batch() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_db_batch')
	os.rmdir_all(dir) or {}
	mut db := open(dir, Options{}) or { panic(err) }
	mut b := new_batch()
	b.put('a'.bytes(), '1'.bytes())
	b.put('b'.bytes(), '2'.bytes())
	b.delete('a'.bytes())
	db.write(mut b, WriteOptions{}) or { panic(err) }
	if _ := db.get('a'.bytes(), ReadOptions{}) {
		panic('a should be deleted')
	}
	v := db.get('b'.bytes(), ReadOptions{}) or { panic('missing b') }
	assert v == '2'.bytes()
	db.close() or { panic(err) }
	os.rmdir_all(dir) or {}
}

fn test_db_iterator() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_db_iter')
	os.rmdir_all(dir) or {}
	mut db := open(dir, Options{ write_buffer_size: 8 * 1024 }) or { panic(err) }
	for i in 0 .. 200 {
		db.put('k${i:04}'.bytes(), 'v${i}'.bytes(), WriteOptions{}) or { panic(err) }
	}
	db.delete('k0100'.bytes(), WriteOptions{}) or { panic(err) }
	mut it := db.new_iterator(ReadOptions{}) or { panic(err) }
	assert it.len() == 199
	mut count := 0
	for ok := it.first(); ok; ok = it.next() {
		count++
	}
	assert count == 199
	assert it.seek('k0100'.bytes())
	assert it.key() == 'k0101'.bytes()
	db.close() or { panic(err) }
	os.rmdir_all(dir) or {}
}

fn test_db_second_open_is_refused_while_first_is_live() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_db_lock')
	os.rmdir_all(dir) or {}
	mut db := open(dir, Options{}) or { panic(err) }
	db.put('held'.bytes(), 'value'.bytes(), WriteOptions{}) or { panic(err) }
	if _ := open(dir, Options{}) {
		panic('a second handle opened a database that was already open')
	}
	db.close() or { panic(err) }

	mut db2 := open(dir, Options{}) or { panic('the lock outlived the handle that took it') }
	v := db2.get('held'.bytes(), ReadOptions{}) or { panic('missing held') }
	assert v == 'value'.bytes()
	db2.close() or { panic(err) }
	os.rmdir_all(dir) or {}
}

fn newest_file_with_suffix(dir string, suffix string) string {
	mut names := os.ls(dir) or { panic(err) }
	names = names.filter(it.ends_with(suffix))
	names.sort()
	assert names.len > 0, 'no ${suffix} file in ${dir}'
	return os.join_path(dir, names.last())
}

// os.truncate opens with O_TRUNC before resizing which zero fills the whole
// file rather than shortening it. Write the prefix back instead.
fn cut_tail(path string, bytes int) {
	data := os.read_bytes(path) or { panic(err) }
	assert data.len > bytes
	os.write_file_array(path, data[..data.len - bytes]) or { panic(err) }
}

// CURRENT names the manifest in use. Reading it beats guessing at a file
// number. A harmless change to database creation could shift.
fn current_manifest(dir string) string {
	name := os.read_file(os.join_path(dir, 'CURRENT')) or { panic(err) }
	return os.join_path(dir, name.trim_space())
}

fn flip_byte(path string, offset int) {
	mut data := os.read_bytes(path) or { panic(err) }
	assert offset < data.len, 'file is shorter than the offset to corrupt'
	data[offset] = data[offset] ^ 0xff
	os.write_file_array(path, data) or { panic(err) }
}

fn test_corrupt_journal_record_is_not_end_of_journal() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_journal_corrupt')
	os.rmdir_all(dir) or {}
	mut db := open(dir, Options{}) or { panic(err) }
	for i in 0 .. 5 {
		db.put('key${i}'.bytes(), 'value${i}'.bytes(), WriteOptions{}) or { panic(err) }
	}
	db.close() or { panic(err) }

	// Byte 8 is inside the payload of the first record leaving four
	// undamaged records behind it.
	flip_byte(newest_file_with_suffix(dir, '.log'), 8)
	if _ := open(dir, Options{}) {
		panic('a database with a corrupt journal opened as if nothing were wrong')
	}
	os.rmdir_all(dir) or {}
}

fn test_truncated_manifest_record_is_not_end_of_manifest() {
	dir := os.join_path(os.temp_dir(), 'vleveldb_manifest_truncated')
	os.rmdir_all(dir) or {}
	mut db := open(dir, Options{ write_buffer_size: 256 }) or { panic(err) }
	for i in 0 .. 20 {
		db.put('manifest-key-${i}'.bytes(), 'manifest-value-${i}'.bytes(), WriteOptions{}) or {
			panic(err)
		}
	}

	db.compact() or { panic(err) }
	db.close() or { panic(err) }

	cut_tail(current_manifest(dir), 1)
	if _ := open(dir, Options{}) {
		panic('a database with a truncated manifest opened as if nothing were wrong')
	}
	os.rmdir_all(dir) or {}
}
