module memdb

// `memdb` is the mutable skiplist-backed table used before writes are flushed
// into sorted table files.

import rand
import leveldb.internal.internalkey { KeyType, compare_bytes, compare_internal, internal_ukey, parse_internal_key }

const max_height = 12
const branching = 4

struct MemNode {
mut:
	key   []u8
	value []u8
	next  []int
}

@[heap]
pub struct MemDB {
mut:
	nodes  []MemNode
	height int = 1
	size   int
}

pub fn new_memdb() &MemDB {
	mut db := &MemDB{}
	db.nodes << MemNode{
		next: []int{len: max_height, init: -1}
	}
	return db
}

pub fn (db &MemDB) len() int {
	return db.nodes.len - 1
}

pub fn (db &MemDB) approx_size() int {
	return db.size
}

fn random_height() int {
	mut h := 1
	for h < max_height && rand.intn(branching) or { 0 } == 0 {
		h++
	}
	return h
}

fn (db &MemDB) find_greater_or_equal(key []u8, mut prev []int) int {
	mut x := 0
	mut level := db.height - 1
	for {
		next := db.nodes[x].next[level]
		if next != -1 && compare_internal(db.nodes[next].key, key) < 0 {
			x = next
		} else {
			if prev.len > 0 {
				prev[level] = x
			}
			if level == 0 {
				return next
			}
			level--
		}
	}
	return -1
}

pub fn (mut db MemDB) put(key []u8, value []u8) {
	mut prev := []int{len: max_height, init: 0}
	db.find_greater_or_equal(key, mut prev)
	h := random_height()
	if h > db.height {
		for i in db.height .. h {
			prev[i] = 0
		}
		db.height = h
	}
	idx := db.nodes.len
	mut node := MemNode{
		key:   key
		value: value
		next:  []int{len: h, init: -1}
	}
	for i in 0 .. h {
		node.next[i] = db.nodes[prev[i]].next[i]
	}
	db.nodes << node
	for i in 0 .. h {
		db.nodes[prev[i]].next[i] = idx
	}
	db.size += key.len + value.len + 16
}

pub fn (db &MemDB) get(ikey []u8) ?([]u8, KeyType) {
	mut prev := []int{}
	idx := db.find_greater_or_equal(ikey, mut prev)
	if idx == -1 {
		return none
	}
	node := db.nodes[idx]
	pk := parse_internal_key(node.key) or { return none }
	if compare_bytes(pk.ukey, internal_ukey(ikey)) != 0 {
		return none
	}
	return node.value, pk.kt
}

pub struct MemIterator {
	db &MemDB
mut:
	node int = -1
}

pub fn (db &MemDB) iterator() &MemIterator {
	return &MemIterator{
		db: db
	}
}

pub fn (mut it MemIterator) seek_to_first() bool {
	it.node = it.db.nodes[0].next[0]
	return it.node != -1
}

fn (mut it MemIterator) seek(ikey []u8) bool {
	mut prev := []int{}
	it.node = it.db.find_greater_or_equal(ikey, mut prev)
	return it.node != -1
}

pub fn (mut it MemIterator) next() bool {
	if it.node == -1 {
		return false
	}
	it.node = it.db.nodes[it.node].next[0]
	return it.node != -1
}

fn (it &MemIterator) valid() bool {
	return it.node != -1
}

pub fn (it &MemIterator) key() []u8 {
	return it.db.nodes[it.node].key
}

pub fn (it &MemIterator) value() []u8 {
	return it.db.nodes[it.node].value
}
