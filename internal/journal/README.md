# journal

Record log in 32 KiB blocks with checksummed fragments. Used for the write-ahead log (`NNNNNN.log`) and the MANIFEST.

Internal to leveldb. Import `leveldb` for the public API, this package has no stability promise.
