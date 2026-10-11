## Description

`internal.fs` contains the filesystem operations needed to make database state
exclusive and durable.

The module owns the database directory lock, full file-descriptor writes, file
sync and directory sync. Platform files keep the OS specific details narrow:
POSIX uses `flock`, `fsync`, and directory `fsync`, while Windows uses exclusive
file handles and `FlushFileBuffers`.
