## Description

`internal.journal` implements the LevelDB write-ahead log format.

Journal files are divided into 32 KiB physical blocks. Logical records may fit
in one physical record or be split into first, middle, and last fragments. Each
physical record carries a masked CRC32C checksum over its type and payload.

The reader distinguishes a clean end of file from a torn tail. Recovery can
ignore a final record cut short by a crash, while checksum failures and malformed
fragment sequences are reported as corruption.
