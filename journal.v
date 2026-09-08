module leveldb

import os

const journal_block_size = 32768
const journal_header_size = 7

enum RecordType as u8 {
	zero   = 0
	full   = 1
	first  = 2
	middle = 3
	last   = 4
}

struct JournalWriter {
mut:
	f            os.File
	block_offset int
}

fn new_journal_writer(path string) !&JournalWriter {
	f := os.open_file(path, 'wb+', 0o644)!
	return &JournalWriter{
		f: f
	}
}

fn (mut w JournalWriter) append(record []u8) ! {
	mut left := record.len
	mut pos := 0
	mut begin := true
	for {
		leftover := journal_block_size - w.block_offset
		if leftover < journal_header_size {
			if leftover > 0 {
				pad := []u8{len: leftover}
				w.f.write(pad)!
			}
			w.block_offset = 0
		}
		avail := journal_block_size - w.block_offset - journal_header_size
		fragment := if left < avail { left } else { avail }
		end := left == fragment
		mut rt := RecordType.middle
		if begin && end {
			rt = .full
		} else if begin {
			rt = .first
		} else if end {
			rt = .last
		}
		w.emit(rt, record[pos..pos + fragment])!
		pos += fragment
		left -= fragment
		begin = false
		if left <= 0 {
			break
		}
	}
}

fn (mut w JournalWriter) emit(rt RecordType, data []u8) ! {
	mut header := []u8{len: journal_header_size}
	mut crc_buf := []u8{cap: data.len + 1}
	crc_buf << u8(rt)
	crc_buf << data
	crc := mask_crc(crc32c(crc_buf))
	put_u32_le(mut header, 0, crc)
	header[4] = u8(data.len)
	header[5] = u8(data.len >> 8)
	header[6] = u8(rt)
	w.f.write(header)!
	w.f.write(data)!
	w.block_offset += journal_header_size + data.len
}

fn (mut w JournalWriter) flush() ! {
	w.f.flush()
}

fn (mut w JournalWriter) sync() ! {
	w.f.flush()
	sync_file(w.f.fd)!
}

fn (mut w JournalWriter) close() {
	w.f.flush()
	w.f.close()
}

struct JournalReader {
mut:
	data []u8
	pos  int
}

fn new_journal_reader(path string) !&JournalReader {
	data := os.read_bytes(path)!
	return &JournalReader{
		data: data
	}
}

// JournalEnd is returned when a journal ended cleanly.
struct JournalEnd {
	Error
}

// JournalTornTail is returned when the final record was cut short by whatever
// killed the process that was writing it.
struct JournalTornTail {
	Error
}

fn (mut r JournalReader) read_record() ![]u8 {
	mut record := []u8{}
	mut in_fragment := false
	for {
		block_left := journal_block_size - (r.pos % journal_block_size)
		if block_left < journal_header_size {
			r.pos += block_left
		}
		start := r.pos
		if start == r.data.len {
			if in_fragment {
				return JournalTornTail{}
			}
			return JournalEnd{}
		}
		if start + journal_header_size > r.data.len {
			return JournalTornTail{}
		}
		length := int(u32(r.data[start + 4]) | (u32(r.data[start + 5]) << 8))
		rt := r.data[start + 6]
		block_room := journal_block_size - (start % journal_block_size) - journal_header_size
		if length > block_room {
			return error('leveldb: journal record at offset ${start} claims ${length} bytes, past the end of its block')
		}
		if start + journal_header_size + length > r.data.len {
			return JournalTornTail{}
		}
		stored_crc := read_u32_le(r.data, start)
		payload := r.data[start + journal_header_size..start + journal_header_size + length]
		mut crc_buf := []u8{cap: length + 1}
		crc_buf << rt
		crc_buf << payload
		if unmask_crc(stored_crc) != crc32c(crc_buf) {
			return error('leveldb: journal record checksum mismatch at offset ${start}')
		}
		r.pos = start + journal_header_size + length
		match rt {
			u8(RecordType.full) {
				if in_fragment {
					return error('leveldb: journal has a whole record inside a fragmented one at offset ${start}')
				}
				return payload.clone()
			}
			u8(RecordType.first) {
				if in_fragment {
					return error('leveldb: journal starts a second fragmented record at offset ${start}')
				}
				record << payload
				in_fragment = true
			}
			u8(RecordType.middle) {
				if !in_fragment {
					return error('leveldb: journal continues a record that never started at offset ${start}')
				}
				record << payload
			}
			u8(RecordType.last) {
				if !in_fragment {
					return error('leveldb: journal ends a record that never started at offset ${start}')
				}
				record << payload
				return record
			}
			else {
				return error('leveldb: unknown journal record type ${rt} at offset ${start}')
			}
		}
	}
	return JournalEnd{}
}
