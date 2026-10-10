# fs

Durable file operations (fsync for files and directories, write-then-sync helpers) and the exclusive `LOCK` file. The platform bits live in the `*_nix.c.v` and `*_windows.c.v` files.

Internal to leveldb. Import `leveldb` for the public API, this package has no stability promise.
