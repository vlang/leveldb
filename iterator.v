module leveldb

import leveldb.internal.blockfmt { BlockEntry }
import leveldb.internal.internalkey

pub struct Iterator {
mut:
	entries []BlockEntry
	pos     int = -1
}

pub fn (mut db DB) new_iterator(ro ReadOptions) !&Iterator {
	mut all := []BlockEntry{}
	mut mit := db.mem.iterator()
	for ok := mit.seek_to_first(); ok; ok = mit.next() {
		all << BlockEntry{
			key:   mit.key().clone()
			value: mit.value().clone()
		}
	}
	for level in 0 .. num_levels {
		for f in db.vs.current.levels[level] {
			tr := db.table(f.num)!
			all << tr.all_entries()!
		}
	}
	all.sort_with_compare(fn (a &BlockEntry, b &BlockEntry) int {
		return internalkey.compare_internal(a.key, b.key)
	})
	mut resolved := []BlockEntry{}
	mut last_ukey := []u8{}
	mut has_last := false
	for e in all {
		pk := internalkey.parse_internal_key(e.key)!
		if has_last && internalkey.compare_bytes(pk.ukey, last_ukey) == 0 {
			continue
		}
		last_ukey = pk.ukey.clone()
		has_last = true
		if pk.kt == .del {
			continue
		}
		resolved << BlockEntry{
			key:   pk.ukey.clone()
			value: e.value
		}
	}
	return &Iterator{
		entries: resolved
	}
}

pub fn (mut it Iterator) first() bool {
	it.pos = 0
	return it.valid()
}

pub fn (mut it Iterator) last() bool {
	it.pos = it.entries.len - 1
	return it.valid()
}

pub fn (mut it Iterator) next() bool {
	if it.pos < it.entries.len {
		it.pos++
	}
	return it.valid()
}

pub fn (mut it Iterator) prev() bool {
	if it.pos >= 0 {
		it.pos--
	}
	return it.valid()
}

pub fn (mut it Iterator) seek(key []u8) bool {
	mut lo := 0
	mut hi := it.entries.len
	for lo < hi {
		mid := (lo + hi) / 2
		if internalkey.compare_bytes(it.entries[mid].key, key) < 0 {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	it.pos = lo
	return it.valid()
}

pub fn (it &Iterator) valid() bool {
	return it.pos >= 0 && it.pos < it.entries.len
}

pub fn (it &Iterator) key() []u8 {
	return it.entries[it.pos].key
}

pub fn (it &Iterator) value() []u8 {
	return it.entries[it.pos].value
}

pub fn (it &Iterator) len() int {
	return it.entries.len
}
