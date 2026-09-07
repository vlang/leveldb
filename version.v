module leveldb

import os

const num_levels = 7

const tag_comparer = u64(1)
const tag_journal_num = u64(2)
const tag_next_file_num = u64(3)
const tag_seq_num = u64(4)
const tag_compact_pointer = u64(5)
const tag_deleted_table = u64(6)
const tag_added_table = u64(7)
const tag_prev_journal_num = u64(9)

const comparer_name = 'leveldb.BytewiseComparator'

struct TableFile {
	num      u64
	size     u64
	smallest []u8
	largest  []u8
}

struct DeletedTable {
	level int
	num   u64
}

struct AddedTable {
	level int
	file  TableFile
}

struct VersionEdit {
mut:
	comparer      string
	journal_num   u64
	next_file_num u64
	seq_num       u64
	has_comparer  bool
	has_journal   bool
	has_next_file bool
	has_seq       bool
	deleted       []DeletedTable
	added         []AddedTable
}

fn (e &VersionEdit) encode() []u8 {
	mut out := []u8{}
	if e.has_comparer {
		append_uvarint(mut out, tag_comparer)
		append_uvarint(mut out, u64(e.comparer.len))
		out << e.comparer.bytes()
	}
	if e.has_journal {
		append_uvarint(mut out, tag_journal_num)
		append_uvarint(mut out, e.journal_num)
	}
	if e.has_next_file {
		append_uvarint(mut out, tag_next_file_num)
		append_uvarint(mut out, e.next_file_num)
	}
	if e.has_seq {
		append_uvarint(mut out, tag_seq_num)
		append_uvarint(mut out, e.seq_num)
	}
	for d in e.deleted {
		append_uvarint(mut out, tag_deleted_table)
		append_uvarint(mut out, u64(d.level))
		append_uvarint(mut out, d.num)
	}
	for a in e.added {
		append_uvarint(mut out, tag_added_table)
		append_uvarint(mut out, u64(a.level))
		append_uvarint(mut out, a.file.num)
		append_uvarint(mut out, a.file.size)
		append_uvarint(mut out, u64(a.file.smallest.len))
		out << a.file.smallest
		append_uvarint(mut out, u64(a.file.largest.len))
		out << a.file.largest
	}
	return out
}

fn read_len_bytes(data []u8, pos int) !([]u8, int) {
	l, n := read_uvarint(data, pos)!
	if pos + n + int(l) > data.len {
		return error('leveldb: corrupted manifest field')
	}
	return data[pos + n..pos + n + int(l)].clone(), n + int(l)
}

fn decode_version_edit(data []u8) !VersionEdit {
	mut e := VersionEdit{}
	mut pos := 0
	for pos < data.len {
		tag, tn := read_uvarint(data, pos)!
		pos += tn
		match tag {
			tag_comparer {
				b, n := read_len_bytes(data, pos)!
				pos += n
				e.comparer = b.bytestr()
				e.has_comparer = true
			}
			tag_journal_num {
				v, n := read_uvarint(data, pos)!
				pos += n
				e.journal_num = v
				e.has_journal = true
			}
			tag_prev_journal_num {
				_, n := read_uvarint(data, pos)!
				pos += n
			}
			tag_next_file_num {
				v, n := read_uvarint(data, pos)!
				pos += n
				e.next_file_num = v
				e.has_next_file = true
			}
			tag_seq_num {
				v, n := read_uvarint(data, pos)!
				pos += n
				e.seq_num = v
				e.has_seq = true
			}
			tag_compact_pointer {
				_, n1 := read_uvarint(data, pos)!
				pos += n1
				_, n2 := read_len_bytes(data, pos)!
				pos += n2
			}
			tag_deleted_table {
				level, n1 := read_uvarint(data, pos)!
				pos += n1
				num, n2 := read_uvarint(data, pos)!
				pos += n2
				e.deleted << DeletedTable{
					level: int(level)
					num:   num
				}
			}
			tag_added_table {
				level, n1 := read_uvarint(data, pos)!
				pos += n1
				num, n2 := read_uvarint(data, pos)!
				pos += n2
				size, n3 := read_uvarint(data, pos)!
				pos += n3
				smallest, n4 := read_len_bytes(data, pos)!
				pos += n4
				largest, n5 := read_len_bytes(data, pos)!
				pos += n5
				e.added << AddedTable{
					level: int(level)
					file:  TableFile{
						num:      num
						size:     size
						smallest: smallest
						largest:  largest
					}
				}
			}
			else {
				return error('leveldb: unknown manifest tag ${tag}')
			}
		}
	}
	return e
}

struct Version {
mut:
	levels [][]TableFile = [][]TableFile{len: num_levels}
}

struct VersionSet {
	dir  string
	opts Options
mut:
	current      &Version
	manifest     &JournalWriter = unsafe { nil }
	manifest_num u64
	next_file    u64 = 2
	journal_num  u64
	last_seq     u64
}

fn (mut vs VersionSet) new_file_num() u64 {
	n := vs.next_file
	vs.next_file++
	return n
}

fn (mut vs VersionSet) apply(edit VersionEdit) {
	mut v := &Version{}
	for i in 0 .. num_levels {
		v.levels[i] = vs.current.levels[i].clone()
	}
	for d in edit.deleted {
		v.levels[d.level] = v.levels[d.level].filter(it.num != d.num)
	}
	for a in edit.added {
		v.levels[a.level] << a.file
		if a.level > 0 {
			v.levels[a.level].sort_with_compare(fn (a &TableFile, b &TableFile) int {
				return compare_internal(a.smallest, b.smallest)
			})
		} else {
			v.levels[0].sort_with_compare(fn (a &TableFile, b &TableFile) int {
				if a.num > b.num {
					return -1
				} else if a.num < b.num {
					return 1
				}
				return 0
			})
		}
	}
	if edit.has_journal {
		vs.journal_num = edit.journal_num
	}
	if edit.has_next_file && edit.next_file_num > vs.next_file {
		vs.next_file = edit.next_file_num
	}
	if edit.has_seq && edit.seq_num > vs.last_seq {
		vs.last_seq = edit.seq_num
	}
	vs.current = v
}

fn (mut vs VersionSet) log_and_apply(mut edit VersionEdit) ! {
	edit.next_file_num = vs.next_file
	edit.has_next_file = true
	edit.seq_num = vs.last_seq
	edit.has_seq = true
	vs.manifest.append(edit.encode())!
	vs.manifest.sync()!
	vs.apply(edit)
}

fn manifest_name(num u64) string {
	return 'MANIFEST-${num:06}'
}

fn table_name(num u64) string {
	return '${num:06}.ldb'
}

fn journal_name(num u64) string {
	return '${num:06}.log'
}

fn (mut vs VersionSet) create_manifest() ! {
	vs.manifest_num = vs.new_file_num()
	path := os.join_path(vs.dir, manifest_name(vs.manifest_num))
	vs.manifest = new_journal_writer(path)!
	mut edit := VersionEdit{
		comparer:      comparer_name
		has_comparer:  true
		journal_num:   vs.journal_num
		has_journal:   true
		next_file_num: vs.next_file
		has_next_file: true
		seq_num:       vs.last_seq
		has_seq:       true
	}
	for level in 0 .. num_levels {
		for f in vs.current.levels[level] {
			edit.added << AddedTable{
				level: level
				file:  f
			}
		}
	}
	vs.manifest.append(edit.encode())!
	vs.manifest.sync()!
	current_path := os.join_path(vs.dir, 'CURRENT')
	tmp_path := current_path + '.tmp'
	os.write_file(tmp_path, manifest_name(vs.manifest_num) + '\n')!
	os.mv(tmp_path, current_path)!
	// CURRENT is what the next open reads to find the manifest at all. The
	// rename has to outlive a crash as surely as the manifest it names.
	sync_dir(vs.dir)!
}

fn (mut vs VersionSet) recover() ! {
	current := os.read_file(os.join_path(vs.dir, 'CURRENT'))!.trim_space()
	if current == '' {
		return error('leveldb: CURRENT file is empty')
	}
	mut reader := new_journal_reader(os.join_path(vs.dir, current))!
	for {
		record := reader.read_record() or {
			if err is JournalEnd {
				break
			}
			return error('leveldb: ${current}: ${err}')
		}
		edit := decode_version_edit(record)!
		if edit.has_comparer && edit.comparer != comparer_name {
			return error('leveldb: comparer mismatch: ${edit.comparer}')
		}
		vs.apply(edit)
	}
}
