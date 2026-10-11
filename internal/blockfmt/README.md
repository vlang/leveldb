## Description

`internal.blockfmt` contains the LevelDB block primitives used by table files.

A data block stores sorted entries with prefix-compressed keys. Each entry
records the shared key prefix length, the remaining key bytes and the value.
Restart points periodically reset the prefix compression so readers can recover
full keys without scanning from the start of the file.

The module also defines encoded block handles, which are the offset and size
pairs stored in table indexes, metaindexes and footers.
