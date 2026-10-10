module filter

fn test_bloom() {
	bf := new_bloom_filter(10)
	keys := [['abc'.bytes()], ['hello'.bytes()], ['world'.bytes()]].map(it[0])
	f := bf.create(keys)
	for k in keys {
		assert bf.may_contain(f, k)
	}
	mut false_positives := 0
	for i in 0 .. 1000 {
		if bf.may_contain(f, 'missing_key_${i}'.bytes()) {
			false_positives++
		}
	}
	assert false_positives < 50
}
