V ?= v
SOURCES := $(wildcard *.v) $(wildcard *.c.v)
EXAMPLE := examples/smoke

.DEFAULT_GOAL := check

.PHONY: help
help:
	@printf '  %-12s %s\n' \
		link       'Link this checkout into V so `import leveldb` resolves' \
		check      'fmt-check, vet and test - what CI runs on a pull request' \
		test       'Run the test suite' \
		fmt        'Format in place' \
		fmt-check  'Fail if anything is unformatted' \
		vet        "Run V's vet" \
		example    'Build and run the example that imports the module' \
		example-prod 'The same, with optimisation on' \
		docs       'Generate the API documentation into _docs/' \
		clean      'Remove build output'

.PHONY: link
link:
	@mkdir -p "$(HOME)/.vmodules"
	@ln -sfn "$(CURDIR)" "$(HOME)/.vmodules/leveldb"
	@echo "linked $(HOME)/.vmodules/leveldb -> $(CURDIR)"

.PHONY: check
check: fmt-check vet test

.PHONY: test
test:
	$(V) test .

.PHONY: fmt
fmt:
	$(V) fmt -w $(SOURCES) $(EXAMPLE)

.PHONY: fmt-check
fmt-check:
	$(V) fmt -verify $(SOURCES) $(EXAMPLE)

.PHONY: vet
vet:
	$(V) vet . $(EXAMPLE)

.PHONY: example
example:
	$(V) run $(EXAMPLE)

.PHONY: example-prod
example-prod:
	$(V) -prod run $(EXAMPLE)

.PHONY: docs
docs:
	$(V) doc -f html -m -o _docs .

.PHONY: clean
clean:
	@rm -rf _docs
	@rm -f *.so *.dll *.dylib
