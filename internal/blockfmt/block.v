module blockfmt

// `blockfmt` builds and decodes LevelDB blocks, including prefix-compressed
// entries, restart points and encoded block handles.

import leveldb.internal.coding { append_u32_le, append_uvarint, read_u32_le, read_uvarint }

pub struct BlockBuilder {
	restart_interval int
mut:
	buf      []u8
	restarts []u32
	counter  int
	last_key []u8
	entries  int
}

pub fn new_block_builder(restart_interval int) &BlockBuilder {
	return &BlockBuilder{
		restart_interval: restart_interval
		restarts:         [u32(0)]
	}
}

pub fn (mut b BlockBuilder) add(key []u8, value []u8) {
	mut shared_len := 0
	if b.counter < b.restart_interval {
		n := if b.last_key.len < key.len { b.last_key.len } else { key.len }
		for shared_len < n && b.last_key[shared_len] == key[shared_len] {
			shared_len++
		}
	} else {
		b.restarts << u32(b.buf.len)
		b.counter = 0
	}
	append_uvarint(mut b.buf, u64(shared_len))
	append_uvarint(mut b.buf, u64(key.len - shared_len))
	append_uvarint(mut b.buf, u64(value.len))
	b.buf << key[shared_len..]
	b.buf << value
	b.last_key = key.clone()
	b.counter++
	b.entries++
}

pub fn (b &BlockBuilder) size_estimate() int {
	return b.buf.len + b.restarts.len * 4 + 4
}

pub fn (b &BlockBuilder) empty() bool {
	return b.entries == 0
}

pub fn (mut b BlockBuilder) finish() []u8 {
	mut out := b.buf.clone()
	for r in b.restarts {
		append_u32_le(mut out, r)
	}
	append_u32_le(mut out, u32(b.restarts.len))
	return out
}

pub fn (mut b BlockBuilder) reset() {
	b.buf.clear()
	b.restarts = [u32(0)]
	b.counter = 0
	b.last_key = []u8{}
	b.entries = 0
}

pub struct BlockEntry {
pub:
	key   []u8
	value []u8
}

pub fn decode_block(data []u8) ![]BlockEntry {
	if data.len < 4 {
		return error('leveldb: block too short')
	}
	num_restarts := int(read_u32_le(data, data.len - 4))
	data_end := data.len - 4 - num_restarts * 4
	if data_end < 0 {
		return error('leveldb: corrupted block restarts')
	}
	mut entries := []BlockEntry{}
	mut pos := 0
	mut last_key := []u8{}
	for pos < data_end {
		shared_len, n1 := read_uvarint(data, pos)!
		pos += n1
		non_shared, n2 := read_uvarint(data, pos)!
		pos += n2
		vlen, n3 := read_uvarint(data, pos)!
		pos += n3
		if pos + int(non_shared) + int(vlen) > data_end || int(shared_len) > last_key.len {
			return error('leveldb: corrupted block entry')
		}
		mut key := []u8{cap: int(shared_len) + int(non_shared)}
		key << last_key[..int(shared_len)]
		key << data[pos..pos + int(non_shared)]
		pos += int(non_shared)
		value := data[pos..pos + int(vlen)].clone()
		pos += int(vlen)
		entries << BlockEntry{
			key:   key
			value: value
		}
		last_key = unsafe { key }
	}
	return entries
}

pub struct BlockHandle {
pub:
	offset u64
	size   u64
}

pub fn (h BlockHandle) encode() []u8 {
	mut out := []u8{cap: 20}
	append_uvarint(mut out, h.offset)
	append_uvarint(mut out, h.size)
	return out
}

pub fn decode_block_handle(data []u8) !(BlockHandle, int) {
	offset, n1 := read_uvarint(data, 0)!
	size, n2 := read_uvarint(data[n1..], 0)!
	return BlockHandle{
		offset: offset
		size:   size
	}, n1 + n2
}
