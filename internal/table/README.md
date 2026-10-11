## Description

`internal.table` reads and writes LevelDB sorted table files.

A table contains data blocks, an index block, a metaindex block, an optional
Bloom filter block and a footer with handles to the metaindex and index. Blocks
are written with a compression type byte and masked CRC32C trailer. This project
supports uncompressed, zlib and raw deflate table blocks.

`TableWriter` receives already ordered internal keys and emits the table layout.
`TableReader` verifies the footer and block checksums, uses the index to locate
candidate blocks and consults Bloom filters before reading data blocks when a
filter is present.
