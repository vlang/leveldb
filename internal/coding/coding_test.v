module coding

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
