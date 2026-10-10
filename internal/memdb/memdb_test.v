module memdb

import leveldb.internal.internalkey

fn test_memdb() {
	mut m := new_memdb()
	m.put(internalkey.make_internal_key('b'.bytes(), 1, .val), 'v1'.bytes())
	m.put(internalkey.make_internal_key('a'.bytes(), 2, .val), 'v2'.bytes())
	m.put(internalkey.make_internal_key('a'.bytes(), 3, .del), []u8{})
	value, kt := m.get(internalkey.make_internal_key('a'.bytes(), internalkey.max_seq,
		internalkey.key_type_seek)) or { panic('missing') }
	assert kt == .del
	v2, kt2 := m.get(internalkey.make_internal_key('b'.bytes(), internalkey.max_seq,
		internalkey.key_type_seek)) or { panic('missing') }
	assert kt2 == .val
	assert v2 == 'v1'.bytes()
	assert value.len == 0
}
