module leveldb

import os
import compress.zlib
import compress.deflate

struct TableReader {
	opts Options
mut:
	data        []u8
	index       []BlockEntry
	filter      []u8
	filter_offs []u32
	bloom       &BloomFilter
	has_filter  bool
}

fn new_table_reader(path string, opts Options) !&TableReader {
	data := os.read_bytes(path)!
	if data.len < footer_len {
		return error('leveldb: table file too short')
	}
	magic := read_u64_le(data, data.len - 8)
	if magic != table_magic {
		return error('leveldb: bad table magic number')
	}
	footer := data[data.len - footer_len..]
	mh, n := decode_block_handle(footer)!
	ih, _ := decode_block_handle(footer[n..])!
	mut r := &TableReader{
		opts:  opts
		data:  data
		bloom: new_bloom_filter(opts.bloom_bits_per_key)
	}
	index_data := r.read_block(ih)!
	r.index = decode_block(index_data)!
	meta_data := r.read_block(mh)!
	meta := decode_block(meta_data)!
	filter_name := 'filter.${bloom_filter_name}'.bytes()
	for e in meta {
		if compare_bytes(e.key, filter_name) == 0 {
			fh, _ := decode_block_handle(e.value)!
			r.load_filter(fh)!
		}
	}
	return r
}

fn (mut r TableReader) load_filter(fh BlockHandle) ! {
	block := r.read_block(fh)!
	if block.len < 5 {
		return
	}
	base_lg := block[block.len - 1]
	if base_lg != filter_base_lg {
		return
	}
	offs_start := int(read_u32_le(block, block.len - 5))
	if offs_start > block.len - 5 {
		return
	}
	num := (block.len - 5 - offs_start) / 4
	for i in 0 .. num {
		r.filter_offs << read_u32_le(block, offs_start + i * 4)
	}
	r.filter_offs << u32(offs_start)
	r.filter = block[..offs_start].clone()
	r.has_filter = true
}

fn (r &TableReader) read_block(h BlockHandle) ![]u8 {
	off := int(h.offset)
	size := int(h.size)
	if off + size + 5 > r.data.len {
		return error('leveldb: block handle out of range')
	}
	raw := r.data[off..off + size]
	ctype := r.data[off + size]
	stored := read_u32_le(r.data, off + size + 1)
	crc := crc32c_update(crc32c(raw), [ctype])
	if unmask_crc(stored) != crc {
		return error('leveldb: block checksum mismatch')
	}
	match ctype {
		u8(Compression.none) {
			return raw.clone()
		}
		u8(Compression.zlib) {
			return zlib.decompress(raw)!
		}
		u8(Compression.raw_deflate) {
			return deflate.decompress(raw)!
		}
		else {
			return error('leveldb: unsupported block compression type ${ctype}')
		}
	}
}

// block_index is the block that may hold ikey or -1 when no block in this
// table covers it. Searching the index cannot fail: an answer of "no block
// covers this key" is an answer.
fn (r &TableReader) block_index(ikey []u8) int {
	mut lo := 0
	mut hi := r.index.len - 1
	mut result := -1
	for lo <= hi {
		mid := (lo + hi) / 2
		if compare_internal(r.index[mid].key, ikey) >= 0 {
			result = mid
			hi = mid - 1
		} else {
			lo = mid + 1
		}
	}
	return result
}

// block_handle reads where a block lives from the index. An index entry that
// will not decode is damage and says so.
fn (r &TableReader) block_handle(idx int) !BlockHandle {
	h, _ := decode_block_handle(r.index[idx].value)!
	return h
}

// TableHit is what a table has to say about a key: whether this table holds an
// entry for it and what that entry is. A table that cannot be read returns an
// error instead, so damage is never reported as an absent key.
struct TableHit {
	found bool
	value []u8
	kt    KeyType
}

fn (r &TableReader) get(ikey []u8) !TableHit {
	idx := r.block_index(ikey)
	if idx < 0 {
		return TableHit{}
	}
	h := r.block_handle(idx)!
	if r.has_filter {
		fidx := int(h.offset >> filter_base_lg)
		if fidx + 1 < r.filter_offs.len {
			start := int(r.filter_offs[fidx])
			end := int(r.filter_offs[fidx + 1])
			if start == end {
				return TableHit{}
			}
			if end <= r.filter.len {
				if !r.bloom.may_contain(r.filter[start..end], internal_ukey(ikey)) {
					return TableHit{}
				}
			}
		}
	}
	block_data := r.read_block(h)!
	entries := decode_block(block_data)!
	for e in entries {
		if compare_internal(e.key, ikey) >= 0 {
			pk := parse_internal_key(e.key)!
			if compare_bytes(pk.ukey, internal_ukey(ikey)) != 0 {
				return TableHit{}
			}
			return TableHit{
				found: true
				value: e.value
				kt:    pk.kt
			}
		}
	}
	return TableHit{}
}

fn (r &TableReader) all_entries() ![]BlockEntry {
	mut out := []BlockEntry{}
	for ie in r.index {
		h, _ := decode_block_handle(ie.value)!
		block_data := r.read_block(h)!
		out << decode_block(block_data)!
	}
	return out
}
