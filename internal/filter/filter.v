module filter

import leveldb.internal.coding { read_u32_le }

pub const bloom_filter_name = 'leveldb.BuiltinBloomFilter2'

fn bloom_hash(data []u8) u32 {
	seed := u32(0xbc9f1d34)
	m := u32(0xc6a4a793)
	mut h := seed ^ (u32(data.len) * m)
	mut i := 0
	for i + 4 <= data.len {
		h += read_u32_le(data, i)
		h *= m
		h ^= h >> 16
		i += 4
	}
	rest := data.len - i
	if rest >= 3 {
		h += u32(data[i + 2]) << 16
	}
	if rest >= 2 {
		h += u32(data[i + 1]) << 8
	}
	if rest >= 1 {
		h += u32(data[i])
		h *= m
		h ^= h >> 24
	}
	return h
}

pub struct BloomFilter {
	bits_per_key int
	k            int
}

pub fn new_bloom_filter(bits_per_key int) &BloomFilter {
	mut k := int(f64(bits_per_key) * 0.69)
	if k < 1 {
		k = 1
	}
	if k > 30 {
		k = 30
	}
	return &BloomFilter{
		bits_per_key: bits_per_key
		k:            k
	}
}

pub fn (bf &BloomFilter) create(keys [][]u8) []u8 {
	mut bits := keys.len * bf.bits_per_key
	if bits < 64 {
		bits = 64
	}
	bytes := (bits + 7) / 8
	bits = bytes * 8
	mut filter := []u8{len: bytes + 1}
	filter[bytes] = u8(bf.k)
	for key in keys {
		mut h := bloom_hash(key)
		delta := (h >> 17) | (h << 15)
		for _ in 0 .. bf.k {
			bit_pos := h % u32(bits)
			filter[bit_pos / 8] |= u8(1) << (bit_pos % 8)
			h += delta
		}
	}
	return filter
}

pub fn (bf &BloomFilter) may_contain(filter []u8, key []u8) bool {
	if filter.len < 2 {
		return false
	}
	bits := u32((filter.len - 1) * 8)
	k := filter[filter.len - 1]
	if k > 30 {
		return true
	}
	mut h := bloom_hash(key)
	delta := (h >> 17) | (h << 15)
	for _ in 0 .. k {
		bit_pos := h % bits
		if filter[bit_pos / 8] & (u8(1) << (bit_pos % 8)) == 0 {
			return false
		}
		h += delta
	}
	return true
}
