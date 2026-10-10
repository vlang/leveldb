module leveldb

import leveldb.internal.coding { append_uvarint, put_u32_le, read_u32_le, read_u64_le, read_uvarint }
import leveldb.internal.internalkey { KeyType }

const batch_header_len = 12

pub struct Batch {
mut:
	data  []u8
	count u32
}

pub fn new_batch() &Batch {
	return &Batch{
		data: []u8{len: batch_header_len}
	}
}

pub fn (mut b Batch) put(key []u8, value []u8) {
	b.data << u8(KeyType.val)
	append_uvarint(mut b.data, u64(key.len))
	b.data << key
	append_uvarint(mut b.data, u64(value.len))
	b.data << value
	b.count++
}

pub fn (mut b Batch) delete(key []u8) {
	b.data << u8(KeyType.del)
	append_uvarint(mut b.data, u64(key.len))
	b.data << key
	b.count++
}

pub fn (mut b Batch) reset() {
	b.data = []u8{len: batch_header_len}
	b.count = 0
}

pub fn (b &Batch) len() int {
	return int(b.count)
}

fn (mut b Batch) set_seq(seq u64) {
	for i in 0 .. 8 {
		b.data[i] = u8(seq >> (i * 8))
	}
	put_u32_le(mut b.data, 8, b.count)
}

fn (b &Batch) seq() u64 {
	return read_u64_le(b.data, 0)
}

fn batch_from_data(data []u8) !&Batch {
	if data.len < batch_header_len {
		return error('leveldb: batch record too short')
	}
	b := &Batch{
		data:  data.clone()
		count: read_u32_le(data, 8)
	}
	return b
}

fn (b &Batch) each(cb fn (kt KeyType, key []u8, value []u8) !) ! {
	mut pos := batch_header_len
	mut n := u32(0)
	for pos < b.data.len {
		t := b.data[pos]
		pos++
		if t > 1 {
			return error('leveldb: corrupted batch record type')
		}
		klen, kn := read_uvarint(b.data, pos)!
		pos += kn
		if pos + int(klen) > b.data.len {
			return error('leveldb: corrupted batch key')
		}
		key := b.data[pos..pos + int(klen)]
		pos += int(klen)
		mut value := []u8{}
		if t == u8(KeyType.val) {
			vlen, vn := read_uvarint(b.data, pos)!
			pos += vn
			if pos + int(vlen) > b.data.len {
				return error('leveldb: corrupted batch value')
			}
			value = b.data[pos..pos + int(vlen)]
			pos += int(vlen)
		}
		cb(unsafe { KeyType(t) }, key, value)!
		n++
	}
	if n != b.count {
		return error('leveldb: batch count mismatch')
	}
}
