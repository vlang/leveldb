# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the major version is 0, the public API may change in any minor release;
breaking changes are listed under **Changed** with a migration note.

## [Unreleased]

Nothing yet.

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

[Unreleased]: https://github.com/bedrock-v/leveldb/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bedrock-v/leveldb/releases/tag/v0.1.0
