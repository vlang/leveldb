# leveldb

LevelDB key/value database implementation in pure V. Uses zlib/deflate block compression instead of snappy, matching the format used by Minecraft Bedrock worlds.

> [!NOTE]
> This implementation is a V port derived from [`df-mc/goleveldb`](https://github.com/df-mc/goleveldb), which is itself a fork of [`syndtr/goleveldb`](https://github.com/syndtr/goleveldb).

## Features

- Log-structured merge tree with 7 levels
- Skiplist memtable with write-ahead log (journal) for crash recovery
- SSTable files with prefix-compressed blocks, restart points and CRC32C checksums
- Zlib (type 2) and raw deflate (type 4) block compression
- Bloom filters for fast negative lookups
- MANIFEST/CURRENT based version tracking
- Atomic write batches
- Memtable flush to L0 and size-based level compaction
- Snapshot iterator over the whole database

## Usage

```v
import leveldb

mut db := leveldb.open('mydb', leveldb.Options{})!

db.put('key'.bytes(), 'value'.bytes(), leveldb.WriteOptions{})!

// get returns an error when the read fails and a Lookup whose `found`
// says whether the key is there.
if r := db.get('key'.bytes(), leveldb.ReadOptions{}) {
	if r.found {
		println(r.value.bytestr())
	}
}

db.delete('key'.bytes(), leveldb.WriteOptions{})!

mut batch := leveldb.new_batch()
batch.put('a'.bytes(), '1'.bytes())
batch.put('b'.bytes(), '2'.bytes())
batch.delete('a'.bytes())
db.write(mut batch, leveldb.WriteOptions{})!

mut it := db.new_iterator(leveldb.ReadOptions{})!
for ok := it.first(); ok; ok = it.next() {
	println('${it.key().bytestr()} = ${it.value().bytestr()}')
}

db.close()!
```

## Options

| Option | Default | Description |
|---|---|---|
| `create_if_missing` | `true` | Create the database if it does not exist |
| `error_if_exists` | `false` | Fail when opening an existing database |
| `write_buffer_size` | 4 MiB | Memtable size before flushing to L0 |
| `block_size` | 4 KiB | Target uncompressed size of table blocks |
| `block_restart_interval` | 16 | Keys between prefix-compression restart points |
| `compression` | `.zlib` | Block compression: `.none`, `.zlib`, `.raw_deflate` |
| `bloom_bits_per_key` | 10 | Bloom filter density, 0 disables filters |
| `max_file_size` | 2 MiB | Target size of compaction output tables |
| `l0_compaction_trigger` | 4 | L0 file count that triggers compaction |

## File format

Follows the standard LevelDB on-disk layout:

- `NNNNNN.log` - write-ahead journal, 32 KiB blocks with checksummed records
- `NNNNNN.ldb` - sorted table files with data/filter/metaindex/index blocks and footer magic
- `MANIFEST-NNNNNN` - version edit records written in journal format
- `CURRENT` - name of the active manifest
- `LOCK` - lock file

## Tests

```sh
v test .
```
