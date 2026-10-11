module options

// `options` defines the tunable database, read and write settings shared by
// the public API and internal components.

pub enum Compression as u8 {
	none        = 0
	snappy      = 1
	zlib        = 2
	raw_deflate = 4
}

pub struct Options {
pub mut:
	create_if_missing      bool = true
	error_if_exists        bool
	write_buffer_size      int         = 4 * 1024 * 1024
	block_size             int         = 4 * 1024
	block_restart_interval int         = 16
	compression            Compression = .zlib
	bloom_bits_per_key     int         = 10
	max_file_size          int         = 2 * 1024 * 1024
	l0_compaction_trigger  int         = 4
}

pub struct ReadOptions {
pub mut:
	verify_checksums bool
}

pub struct WriteOptions {
pub mut:
	sync bool
}
