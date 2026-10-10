module internalkey

import leveldb.internal.coding { append_u64_le, read_u64_le }

pub enum KeyType as u8 {
	del = 0
	val = 1
}

pub const key_type_seek = KeyType.val
pub const max_seq = u64(1 << 56) - 1

pub fn make_internal_key(ukey []u8, seq u64, kt KeyType) []u8 {
	mut ik := []u8{cap: ukey.len + 8}
	ik << ukey
	append_u64_le(mut ik, (seq << 8) | u64(u8(kt)))
	return ik
}

pub struct ParsedKey {
pub:
	ukey []u8
	seq  u64
	kt   KeyType
}

pub fn parse_internal_key(ik []u8) !ParsedKey {
	if ik.len < 8 {
		return error('leveldb: internal key too short')
	}
	num := read_u64_le(ik, ik.len - 8)
	t := u8(num)
	if t > 1 {
		return error('leveldb: invalid internal key type')
	}
	return ParsedKey{
		ukey: ik[..ik.len - 8]
		seq:  num >> 8
		kt:   unsafe { KeyType(t) }
	}
}

pub fn internal_ukey(ik []u8) []u8 {
	return ik[..ik.len - 8]
}

pub fn compare_bytes(a []u8, b []u8) int {
	n := if a.len < b.len { a.len } else { b.len }
	for i in 0 .. n {
		if a[i] != b[i] {
			return if a[i] < b[i] { -1 } else { 1 }
		}
	}
	if a.len == b.len {
		return 0
	}
	return if a.len < b.len { -1 } else { 1 }
}

pub fn compare_internal(a []u8, b []u8) int {
	c := compare_bytes(internal_ukey(a), internal_ukey(b))
	if c != 0 {
		return c
	}
	na := read_u64_le(a, a.len - 8)
	nb := read_u64_le(b, b.len - 8)
	if na > nb {
		return -1
	} else if na < nb {
		return 1
	}
	return 0
}
