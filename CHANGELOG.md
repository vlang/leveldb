# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the major version is 0, the public API may change in any minor release;
breaking changes are listed under **Changed** with a migration note.

## [Unreleased]

Nothing yet.

## [0.1.1] - 2026-09-29

A read that fails now says so. This release breaks the API: `db.get()` and
`db.has()` have new signatures. The migration is below.

### Changed

- **`db`**: `get()` and `has()` return a result instead of swallowing read
  failures. `get()` returns `!Lookup`, where `Lookup.found` says whether the
  key exists and `Lookup.value` holds its value; `has()` returns `!bool`. A
  table that will not open, a block whose checksum fails, a block that will
  not decompress or decode and a malformed internal key or block handle are
  all errors now. They used to come back as an ordinary missing key, so a
  caller could not tell a deleted key from a damaged database.

  Migration:

  ```v
  // before
  if value := db.get(key, leveldb.ReadOptions{}) {
  	println(value.bytestr())
  }

  // after
  r := db.get(key, leveldb.ReadOptions{})!
  if r.found {
  	println(r.value.bytestr())
  }
  ```

### Fixed

- **`journal`**: a crash during open could lose data that was recovered from
  the journal. Open wrote the recovered memtable out only after the manifest
  it belonged in was already written, leaving a window in which the journal
  was gone and no table named its records. The recovered memtable is now
  written to a table before the manifest and both are published together.
  A journal replayed at open also marks its file number used. The number
  cannot be handed out again and write over a file the directory already has.
- **`db`**: compaction dropped tombstones that still had to hide a value. The
  decision was made over the range of the level being compacted, not the range
  the compaction actually covered once the overlapping files from the next
  level joined it, so a delete could be discarded while an older value for the
  same key remained in a deeper level and came back.

## [0.1.0] - 2026-09-18

The first tagged release. A database that survives the crashes and the
corruption it is supposed to survive and a version number to depend on.

Everything below already existed in the repository; this release is where it
becomes something a dependent can pin.

### Added

- A LevelDB implementation in pure V: skiplist memtable, write-ahead journal,
  SSTables with prefix compressed blocks and CRC32C checksums, bloom filters,
  MANIFEST/CURRENT version tracking, atomic write batches, memtable flush to L0
  and size based level compaction and a snapshot iterator. Blocks are
  compressed with zlib or raw deflate.
- **`db`**: `sync()` makes pending writes durable without forcing a compaction.
- CI builds the V it tests against from a pinned source checkout and a release
  workflow publishes a tag whose changelog section becomes the release notes.

### Fixed

- **`journal`**: data recovered from the journal was lost on the next open.
  Recovery left the records in the memtable and then removed the journal they
  came from, writing them out only when they happened to exceed
  `write_buffer_size`. A smaller recovery survived the crash and was then
  dropped by an ordinary restart. The recovered memtable is now flushed before
  its journal is removed.
- **`journal`**: a corrupt record was indistinguishable from the end of the
  journal. Recovery stopped at the first bad checksum and reported success, so
  corruption in the middle of a journal silently truncated the database to the
  records before it.
- **`manifest`**: a truncated MANIFEST was accepted during recovery, opening a
  database against a version edit that was never fully written.
- **`lock`**: the LOCK file was created but never locked, so two processes
  could open the same database and write over each other.
- **`table`**: tables were published into a version before their contents were
  durable. A crash between publication and the data reaching disk left the
  MANIFEST pointing at a file whose blocks were not all there.
- **`journal`**, **`table`**: writes were unchecked. Records and blocks went
  through a buffered file handle whose short writes were never detected. A
  write that stored only part of a record still reported success. Journal
  records, table blocks and the CURRENT file are now written through a loop
  that writes every byte, retries on `EINTR` and turns a failure into an
  error.

[Unreleased]: https://github.com/bedrock-v/leveldb/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/bedrock-v/leveldb/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/bedrock-v/leveldb/releases/tag/v0.1.0
