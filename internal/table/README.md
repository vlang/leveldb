# table

Sorted table files (`NNNNNN.ldb`). The writer builds them during flushes and compactions, the reader serves lookups and full scans.

Internal to leveldb. Import `leveldb` for the public API, this package has no stability promise.
