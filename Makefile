# host tests and generated tables only, the ios build is meow.toml (`meow build`)
# the ios toolchain's cc cannot build host test executables

PYTHON  ?= python3
SCHEMAS := schemas/api.tl schemas/mtproto.tl schemas/secret.tl
TLGEN   := $(PYTHON) tools/tlgen.py

.PHONY: test test-icons test-video sanitize generate check-generated clean

test:
	$(MAKE) -C tests test

test-icons:
	$(PYTHON) -m unittest discover -s tests -p test_app_icons.py

test-video:
	$(MAKE) -C tests/video test

sanitize:
	$(MAKE) -C tests sanitize

generate:
	$(TLGEN) --out core/tl/generated $(SCHEMAS)

check-generated:
	@rm -rf build/generated-check
	@$(TLGEN) --out build/generated-check $(SCHEMAS)
	@diff -r build/generated-check core/tl/generated && echo "generated tl tables are current"

clean:
	rm -rf build
