module internalkey

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
