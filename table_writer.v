module leveldb

import os
import compress.zlib
import compress.deflate

const table_magic = u64(0xdb4775248b80fb57)
const footer_len = 48
const filter_base_lg = 11
const filter_base = 1 << filter_base_lg

struct TableWriter {
	opts Options
mut:
	f           os.File
	offset      u64
	data_block  &BlockBuilder
	index_block &BlockBuilder
	filter_keys [][]u8
	filter_data []u8
	filter_offs []u32
	bloom       &BloomFilter
	pending     bool
	pending_h   BlockHandle
	last_key    []u8
	num_entries int
	closed      bool
}

fn new_table_writer(path string, opts Options) !&TableWriter {
	f := os.open_file(path, 'wb+', 0o644)!
	return &TableWriter{
		opts:        opts
		f:           f
		data_block:  new_block_builder(opts.block_restart_interval)
		index_block: new_block_builder(1)
		bloom:       new_bloom_filter(opts.bloom_bits_per_key)
	}
}

fn (mut w TableWriter) add(key []u8, value []u8) ! {
	if w.pending {
		w.index_block.add(w.last_key, w.pending_h.encode())
		w.pending = false
	}
	if w.opts.bloom_bits_per_key > 0 {
		w.filter_keys << internal_ukey(key).clone()
	}
	w.data_block.add(key, value)
	w.last_key = key.clone()
	w.num_entries++
	if w.data_block.size_estimate() >= w.opts.block_size {
		w.flush_data_block()!
	}
}

fn (mut w TableWriter) flush_data_block() ! {
	if w.data_block.empty() {
		return
	}
	block := w.data_block.finish()
	w.pending_h = w.write_block(block, w.opts.compression)!
	w.pending = true
	w.data_block.reset()
	w.generate_filters()
}

fn (mut w TableWriter) generate_filters() {
	if w.opts.bloom_bits_per_key <= 0 {
		return
	}
	filter_index := int(w.offset / u64(filter_base))
	for w.filter_offs.len < filter_index {
		w.finish_filter_slot()
	}
}

fn (mut w TableWriter) finish_filter_slot() {
	w.filter_offs << u32(w.filter_data.len)
	if w.filter_keys.len > 0 {
		f := w.bloom.create(w.filter_keys)
		w.filter_data << f
		w.filter_keys.clear()
	}
}

fn (mut w TableWriter) write_block(block []u8, compression Compression) !BlockHandle {
	mut data := unsafe { block }
	mut ctype := u8(0)
	match compression {
		.zlib {
			compressed := zlib.compress(block) or { block.clone() }
			if compressed.len < block.len {
				data = compressed.clone()
				ctype = u8(Compression.zlib)
			}
		}
		.raw_deflate {
			compressed := deflate.compress(block) or { block.clone() }
			if compressed.len < block.len {
				data = compressed.clone()
				ctype = u8(Compression.raw_deflate)
			}
		}
		else {}
	}
	handle := BlockHandle{
		offset: w.offset
		size:   u64(data.len)
	}
	write_fd_all(w.f.fd, data)!
	mut trailer := []u8{cap: 5}
	trailer << ctype
	crc := crc32c_update(crc32c(data), [ctype])
	append_u32_le(mut trailer, mask_crc(crc))
	write_fd_all(w.f.fd, trailer)!
	w.offset += u64(data.len) + 5
	return handle
}

fn (mut w TableWriter) finish() ! {
	w.flush_data_block()!
	if w.pending {
		w.index_block.add(w.last_key, w.pending_h.encode())
		w.pending = false
	}
	mut metaindex := new_block_builder(w.opts.block_restart_interval)
	if w.opts.bloom_bits_per_key > 0 {
		w.finish_filter_slot()
		mut filter_block := w.filter_data.clone()
		offs_start := u32(filter_block.len)
		for off in w.filter_offs {
			append_u32_le(mut filter_block, off)
		}
		append_u32_le(mut filter_block, offs_start)
		filter_block << u8(filter_base_lg)
		fh := w.write_block(filter_block, .none)!
		metaindex.add('filter.${bloom_filter_name}'.bytes(), fh.encode())
	}
	mh := w.write_block(metaindex.finish(), w.opts.compression)!
	ih := w.write_block(w.index_block.finish(), w.opts.compression)!
	mut footer := []u8{cap: footer_len}
	footer << mh.encode()
	footer << ih.encode()
	for footer.len < footer_len - 8 {
		footer << u8(0)
	}
	append_u64_le(mut footer, table_magic)
	write_fd_all(w.f.fd, footer)!
	w.offset += u64(footer_len)
	// The table is about to be named by a manifest edit that is itself made
	// durable. Get the contents to the device first or a crash between the two
	// leaves durable metadata pointing at a table that was never written.
	sync_file(w.f.fd)!
	w.f.close()
	w.closed = true
}

fn (w &TableWriter) file_size() u64 {
	return w.offset
}

fn (w &TableWriter) entries() int {
	return w.num_entries
}
