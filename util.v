module leveldb

const crc32c_poly = u32(0x82f63b78)
const crc_mask_delta = u32(0xa282ead8)

fn make_crc32c_table() [256]u32 {
	mut table := [256]u32{}
	for i in 0 .. 256 {
		mut crc := u32(i)
		for _ in 0 .. 8 {
			if crc & 1 == 1 {
				crc = (crc >> 1) ^ crc32c_poly
			} else {
				crc >>= 1
			}
		}
		table[i] = crc
	}
	return table
}

const crc32c_table = make_crc32c_table()

fn crc32c(data []u8) u32 {
	return crc32c_update(0, data)
}

fn crc32c_update(seed u32, data []u8) u32 {
	mut crc := ~seed
	for b in data {
		crc = crc32c_table[u8(crc) ^ b] ^ (crc >> 8)
	}
	return ~crc
}

fn mask_crc(crc u32) u32 {
	return ((crc >> 15) | (crc << 17)) + crc_mask_delta
}

fn unmask_crc(masked u32) u32 {
	rot := masked - crc_mask_delta
	return (rot >> 17) | (rot << 15)
}

fn put_u32_le(mut dst []u8, pos int, v u32) {
	dst[pos] = u8(v)
	dst[pos + 1] = u8(v >> 8)
	dst[pos + 2] = u8(v >> 16)
	dst[pos + 3] = u8(v >> 24)
}

fn append_u32_le(mut dst []u8, v u32) {
	dst << u8(v)
	dst << u8(v >> 8)
	dst << u8(v >> 16)
	dst << u8(v >> 24)
}

fn append_u64_le(mut dst []u8, v u64) {
	for i in 0 .. 8 {
		dst << u8(v >> (i * 8))
	}
}

fn read_u32_le(data []u8, pos int) u32 {
	return u32(data[pos]) | (u32(data[pos + 1]) << 8) | (u32(data[pos + 2]) << 16) | (u32(data[pos + 3]) << 24)
}

fn read_u64_le(data []u8, pos int) u64 {
	mut v := u64(0)
	for i in 0 .. 8 {
		v |= u64(data[pos + i]) << (i * 8)
	}
	return v
}

fn append_uvarint(mut dst []u8, v_ u64) {
	mut v := v_
	for v >= 0x80 {
		dst << u8(v) | 0x80
		v >>= 7
	}
	dst << u8(v)
}

fn read_uvarint(data []u8, pos int) !(u64, int) {
	mut v := u64(0)
	mut shift := u32(0)
	mut i := pos
	for i < data.len {
		b := data[i]
		i++
		v |= u64(b & 0x7f) << shift
		if b < 0x80 {
			return v, i - pos
		}
		shift += 7
		if shift > 63 {
			return error('leveldb: varint overflow')
		}
	}
	return error('leveldb: truncated varint')
}
