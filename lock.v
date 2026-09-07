module leveldb

// DBLock is the exclusive claim on a database directory, held for as long as
// the DB handle is.
//
// The LOCK file itself is never removed. A lock tied to a path that comes and
// goes can be held twice, once on the file the first holder still has open and
// once on the one a second opener creates after that file is unlinked.
struct DBLock {
mut:
	handle i64 = -1
}
