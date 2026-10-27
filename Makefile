# the ios toolchain's cc cannot build host test executables

PYTHON  ?= python3
SCHEMAS := schemas/api.tl schemas/mtproto.tl schemas/secret.tl
TLGEN   := $(PYTHON) tools/tlgen.py

.PHONY: test test-icons test-video sanitize generate check-generated core-ios inspect-core app app-unsigned inspect-app inspect-unsigned ipa deb clean

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

core-ios:
	$(MAKE) -f scripts/core-ios.mk all

inspect-core:
	$(MAKE) -f scripts/core-ios.mk inspect

app:
	$(MAKE) -f scripts/app-ios.mk app

app-unsigned:
	$(MAKE) -f scripts/app-ios.mk app-unsigned

inspect-unsigned:
	$(MAKE) -f scripts/app-ios.mk inspect-unsigned

inspect-app:
	$(MAKE) -f scripts/app-ios.mk inspect-app

ipa: app
	bash scripts/package_ipa.sh

deb: ipa
	bash scripts/package_deb.sh

clean:
	rm -rf build
