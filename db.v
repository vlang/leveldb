module leveldb

import os

pub struct DB {
	dir  string
	opts Options
mut:
	mem     &MemDB
	journal &JournalWriter
	vs      &VersionSet
	tables  map[u64]&TableReader
	closed  bool
}

pub fn open(dir string, opts Options) !&DB {
	if !os.exists(dir) {
		if !opts.create_if_missing {
			return error('leveldb: database does not exist: ${dir}')
		}
		os.mkdir_all(dir)!
	}
	lock_path := os.join_path(dir, 'LOCK')
	if !os.exists(lock_path) {
		os.write_file(lock_path, '')!
	}
	current_exists := os.exists(os.join_path(dir, 'CURRENT'))
	if current_exists && opts.error_if_exists {
		return error('leveldb: database already exists: ${dir}')
	}
	if !current_exists && !opts.create_if_missing {
		return error('leveldb: database is missing CURRENT file: ${dir}')
	}
	mut vs := &VersionSet{
		dir:     dir
		opts:    opts
		current: &Version{}
	}
	mut mem := new_memdb()
	if current_exists {
		vs.recover()!
	}
	mut db := &DB{
		dir:     dir
		opts:    opts
		mem:     mem
		journal: unsafe { nil }
		vs:      vs
	}
	if current_exists {
		db.replay_journals()!
	}
	journal_num := vs.new_file_num()
	db.journal = new_journal_writer(os.join_path(dir, journal_name(journal_num)))!
	old_journal := vs.journal_num
	vs.journal_num = journal_num
	vs.create_manifest()!
	// Whatever replay_journals recovered lives only in the memtable and the
	// journal it came from is about to be removed. Write it out first: nothing
	// else does, so otherwise the recovered data goes when this handle closes
	// and the next open finds neither journal nor table.
	if db.mem.approx_size() > 0 {
		db.flush_memtable()!
	}
	if old_journal != 0 {
		db.remove_old_journals(journal_num)
	}
	return db
}

fn (mut db DB) replay_journals() ! {
	entries := os.ls(db.dir) or { return }
	mut nums := []u64{}
	for name in entries {
		if name.ends_with('.log') {
			n := name.all_before('.log').u64()
			if n >= db.vs.journal_num {
				nums << n
			}
		}
	}
	nums.sort()
	for n in nums {
		mut reader := new_journal_reader(os.join_path(db.dir, journal_name(n)))!
		for {
			record := reader.read_record() or { break }
			batch := batch_from_data(record) or { break }
			mut seq := batch.seq()
			batch.each(fn [mut db, mut seq] (kt KeyType, key []u8, value []u8) ! {
				db.mem.put(make_internal_key(key, seq, kt), value.clone())
				seq++
			}) or { break }
			end_seq := batch.seq() + u64(batch.count) - 1
			if end_seq > db.vs.last_seq {
				db.vs.last_seq = end_seq
			}
		}
	}
}

fn (mut db DB) remove_old_journals(keep u64) {
	entries := os.ls(db.dir) or { return }
	for name in entries {
		if name.ends_with('.log') {
			n := name.all_before('.log').u64()
			if n < keep {
				os.rm(os.join_path(db.dir, name)) or {}
			}
		}
	}
}

pub fn (mut db DB) put(key []u8, value []u8, wo WriteOptions) ! {
	mut b := new_batch()
	b.put(key, value)
	db.write(mut b, wo)!
}

pub fn (mut db DB) delete(key []u8, wo WriteOptions) ! {
	mut b := new_batch()
	b.delete(key)
	db.write(mut b, wo)!
}

pub fn (mut db DB) write(mut b Batch, wo WriteOptions) ! {
	if db.closed {
		return error('leveldb: database is closed')
	}
	if b.count == 0 {
		return
	}
	seq := db.vs.last_seq + 1
	b.set_seq(seq)
	db.journal.append(b.data)!
	if wo.sync {
		db.journal.sync()!
	} else {
		db.journal.flush()!
	}
	mut cur := seq
	b.each(fn [mut db, mut cur] (kt KeyType, key []u8, value []u8) ! {
		db.mem.put(make_internal_key(key, cur, kt), value.clone())
		cur++
	})!
	db.vs.last_seq = seq + u64(b.count) - 1
	if db.mem.approx_size() >= db.opts.write_buffer_size {
		db.flush_memtable()!
	}
}

pub fn (mut db DB) get(key []u8, ro ReadOptions) ?[]u8 {
	if db.closed {
		return none
	}
	ikey := make_internal_key(key, max_seq, key_type_seek)
	if value, kt := db.mem.get(ikey) {
		if kt == .del {
			return none
		}
		return value.clone()
	}
	for f in db.vs.current.levels[0] {
		if compare_bytes(key, internal_ukey(f.smallest)) < 0 {
			continue
		}
		if compare_bytes(key, internal_ukey(f.largest)) > 0 {
			continue
		}
		tr := db.table(f.num) or { continue }
		if value, kt := tr.get(ikey) {
			if kt == .del {
				return none
			}
			return value
		}
	}
	for level in 1 .. num_levels {
		files := db.vs.current.levels[level]
		idx := find_file(files, key)
		if idx < files.len {
			f := files[idx]
			if compare_bytes(key, internal_ukey(f.smallest)) >= 0 {
				tr := db.table(f.num) or { continue }
				if value, kt := tr.get(ikey) {
					if kt == .del {
						return none
					}
					return value
				}
			}
		}
	}
	return none
}

pub fn (mut db DB) has(key []u8, ro ReadOptions) bool {
	if _ := db.get(key, ro) {
		return true
	}
	return false
}

fn find_file(files []TableFile, ukey []u8) int {
	mut lo := 0
	mut hi := files.len
	for lo < hi {
		mid := (lo + hi) / 2
		if compare_bytes(internal_ukey(files[mid].largest), ukey) < 0 {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

fn (mut db DB) table(num u64) !&TableReader {
	if num in db.tables {
		return db.tables[num] or { return error('leveldb: table cache miss') }
	}
	tr := new_table_reader(os.join_path(db.dir, table_name(num)), db.opts)!
	db.tables[num] = tr
	return tr
}

fn (mut db DB) flush_memtable() ! {
	if db.mem.len() == 0 {
		return
	}
	file_num := db.vs.new_file_num()
	path := os.join_path(db.dir, table_name(file_num))
	mut tw := new_table_writer(path, db.opts)!
	mut it := db.mem.iterator()
	mut smallest := []u8{}
	mut largest := []u8{}
	for ok := it.seek_to_first(); ok; ok = it.next() {
		if smallest.len == 0 {
			smallest = it.key().clone()
		}
		largest = it.key().clone()
		tw.add(it.key(), it.value())!
	}
	tw.finish()!
	old_journal_num := db.vs.journal_num
	new_journal_num := db.vs.new_file_num()
	db.journal.close()
	db.journal = new_journal_writer(os.join_path(db.dir, journal_name(new_journal_num)))!
	mut edit := VersionEdit{
		journal_num: new_journal_num
		has_journal: true
	}
	edit.added << AddedTable{
		level: 0
		file:  TableFile{
			num:      file_num
			size:     tw.file_size()
			smallest: smallest
			largest:  largest
		}
	}
	db.vs.log_and_apply(mut edit)!
	db.mem = new_memdb()
	os.rm(os.join_path(db.dir, journal_name(old_journal_num))) or {}
	db.maybe_compact()!
}

fn (mut db DB) maybe_compact() ! {
	for {
		if db.vs.current.levels[0].len >= db.opts.l0_compaction_trigger {
			db.compact_level(0)!
			continue
		}
		mut compacted := false
		for level in 1 .. num_levels - 1 {
			mut size := u64(0)
			for f in db.vs.current.levels[level] {
				size += f.size
			}
			mut limit := u64(10) * 1024 * 1024
			for _ in 1 .. level {
				limit *= 10
			}
			if size > limit {
				db.compact_level(level)!
				compacted = true
				break
			}
		}
		if !compacted {
			break
		}
	}
}

fn overlaps(f TableFile, smallest []u8, largest []u8) bool {
	if compare_bytes(internal_ukey(f.largest), internal_ukey(smallest)) < 0 {
		return false
	}
	if compare_bytes(internal_ukey(f.smallest), internal_ukey(largest)) > 0 {
		return false
	}
	return true
}

fn (mut db DB) compact_level(level int) ! {
	mut inputs := []TableFile{}
	mut input_level_nums := []u64{}
	if level == 0 {
		inputs << db.vs.current.levels[0]
	} else {
		inputs << db.vs.current.levels[level][0]
	}
	if inputs.len == 0 {
		return
	}
	for f in inputs {
		input_level_nums << f.num
	}
	mut smallest := inputs[0].smallest.clone()
	mut largest := inputs[0].largest.clone()
	for f in inputs[1..] {
		if compare_internal(f.smallest, smallest) < 0 {
			smallest = f.smallest.clone()
		}
		if compare_internal(f.largest, largest) > 0 {
			largest = f.largest.clone()
		}
	}
	next := level + 1
	mut next_inputs := []TableFile{}
	for f in db.vs.current.levels[next] {
		if overlaps(f, smallest, largest) {
			next_inputs << f
		}
	}
	mut all_entries := []BlockEntry{}
	mut ordered := inputs.clone()
	ordered << next_inputs
	for f in ordered {
		tr := db.table(f.num)!
		all_entries << tr.all_entries()!
	}
	all_entries.sort_with_compare(fn (a &BlockEntry, b &BlockEntry) int {
		return compare_internal(a.key, b.key)
	})
	is_base_level := db.no_overlap_deeper(next, smallest, largest)
	mut edit := VersionEdit{}
	for f in inputs {
		edit.deleted << DeletedTable{
			level: level
			num:   f.num
		}
	}
	for f in next_inputs {
		edit.deleted << DeletedTable{
			level: next
			num:   f.num
		}
	}
	mut tw := &TableWriter(unsafe { nil })
	mut out_num := u64(0)
	mut out_smallest := []u8{}
	mut out_largest := []u8{}
	mut last_ukey := []u8{}
	mut has_last := false
	for e in all_entries {
		pk := parse_internal_key(e.key)!
		if has_last && compare_bytes(pk.ukey, last_ukey) == 0 {
			continue
		}
		last_ukey = pk.ukey.clone()
		has_last = true
		if pk.kt == .del && is_base_level {
			continue
		}
		if isnil(tw) {
			out_num = db.vs.new_file_num()
			tw = new_table_writer(os.join_path(db.dir, table_name(out_num)), db.opts)!
			out_smallest = e.key.clone()
		}
		tw.add(e.key, e.value)!
		out_largest = e.key.clone()
		if tw.file_size() >= u64(db.opts.max_file_size) {
			db.finish_output(mut edit, mut tw, next, out_num, out_smallest, out_largest)!
			tw = unsafe { nil }
		}
	}
	if !isnil(tw) {
		db.finish_output(mut edit, mut tw, next, out_num, out_smallest, out_largest)!
	}
	db.vs.log_and_apply(mut edit)!
	for d in edit.deleted {
		db.tables.delete(d.num)
		os.rm(os.join_path(db.dir, table_name(d.num))) or {}
	}
}

fn (mut db DB) finish_output(mut edit VersionEdit, mut tw TableWriter, level int, num u64, smallest []u8, largest []u8) ! {
	tw.finish()!
	edit.added << AddedTable{
		level: level
		file:  TableFile{
			num:      num
			size:     tw.file_size()
			smallest: smallest
			largest:  largest
		}
	}
}

fn (mut db DB) no_overlap_deeper(level int, smallest []u8, largest []u8) bool {
	for l in level + 1 .. num_levels {
		for f in db.vs.current.levels[l] {
			if overlaps(f, smallest, largest) {
				return false
			}
		}
	}
	return true
}

pub fn (mut db DB) compact() ! {
	db.flush_memtable()!
	for level in 0 .. num_levels - 1 {
		if db.vs.current.levels[level].len > 0 {
			db.compact_level(level)!
		}
	}
}

pub fn (mut db DB) sync() ! {
	if db.closed {
		return
	}
	db.journal.sync()!
}

pub fn (mut db DB) close() ! {
	if db.closed {
		return
	}
	db.journal.sync()!
	db.journal.close()
	db.vs.manifest.close()
	db.closed = true
}
