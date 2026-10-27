EXTERIA_TC ?= $(error set EXTERIA_TC to the ios toolchain bin directory)
EXTERIA_SDK_V7 ?= $(error set EXTERIA_SDK_V7 to a legacy iphoneos sdk)
EXTERIA_SDK_V64 ?= $(error set EXTERIA_SDK_V64 to an arm64 iphoneos sdk)
EXTERIA_OPENSSL_V7 ?= $(error set EXTERIA_OPENSSL_V7 to an armv7 openssl prefix)
EXTERIA_OPENSSL_V64 ?= $(error set EXTERIA_OPENSSL_V64 to an arm64 openssl prefix)
EXTERIA_CRT_V7 ?=
EXTERIA_IOS_BUILD ?= build/ios

CORE_SRC := $(sort $(wildcard core/*/*.c core/tl/generated/*.c))
OPUS_C := $(addprefix third_party/opus/,$(shell cat third_party/opus/SOURCES))
OGG_C := $(sort $(wildcard third_party/ogg/src/*.c))
CODEC_SRC := $(OPUS_C) $(OGG_C)
# core/media includes the vendored codec headers
INCLUDE := $(addprefix -I,$(wildcard core/*)) -Icore/tl/generated -Ithird_party/opus/include -Ithird_party/ogg/include
# same flags as the app, the test binaries link the codec objects the core calls into
CODEC_FLAGS := -std=c99 -O2 -g -w -DOPUS_BUILD -DFIXED_POINT -DDISABLE_FLOAT_API -DVAR_ARRAYS -DPACKAGE_VERSION=\"1.5.2\" \
               -Ithird_party/opus/include -Ithird_party/opus/celt -Ithird_party/opus/silk -Ithird_party/opus/silk/fixed \
               -Ithird_party/opus/src -Ithird_party/ogg/include -MMD -MP
WARN := -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes -Wmissing-prototypes -Wconversion -Wno-sign-conversion
FLAGS := -std=c99 -O2 -g $(WARN) $(INCLUDE) -MMD -MP
V7_FLAGS := -target armv7-apple-ios5.0 -isysroot $(EXTERIA_SDK_V7) -I$(EXTERIA_OPENSSL_V7)/include
V64_FLAGS := -target arm64-apple-ios7.0 -isysroot $(EXTERIA_SDK_V64) -I$(EXTERIA_OPENSSL_V64)/include
V7_OBJ := $(patsubst %.c,$(EXTERIA_IOS_BUILD)/armv7/%.o,$(CORE_SRC))
V64_OBJ := $(patsubst %.c,$(EXTERIA_IOS_BUILD)/arm64/%.o,$(CORE_SRC))
V7_CODEC := $(patsubst %.c,$(EXTERIA_IOS_BUILD)/armv7/%.o,$(CODEC_SRC))
V64_CODEC := $(patsubst %.c,$(EXTERIA_IOS_BUILD)/arm64/%.o,$(CODEC_SRC))
CODEC_STAMP := $(EXTERIA_IOS_BUILD)/codec.stamp
CODEC_STAMP_TEXT := $(EXTERIA_TC) $(V7_FLAGS) $(V64_FLAGS) $(CODEC_FLAGS)

.PHONY: all inputs inspect force
all: $(EXTERIA_IOS_BUILD)/libexteria-core.a $(EXTERIA_IOS_BUILD)/armv7/test_mt_client $(EXTERIA_IOS_BUILD)/arm64/test_mt_client

inputs:
	@test -x "$(EXTERIA_TC)/clang" -a -x "$(EXTERIA_TC)/llvm-ar" -a -x "$(EXTERIA_TC)/lipo" -a -x "$(EXTERIA_TC)/otool" || { echo "missing ios toolchain in EXTERIA_TC" >&2; exit 1; }
	@test -f "$(EXTERIA_SDK_V7)/usr/include/stdlib.h" -a -f "$(EXTERIA_SDK_V64)/usr/include/stdlib.h" || { echo "missing iphoneos sdk headers" >&2; exit 1; }
	@$(if $(EXTERIA_CRT_V7),test -f "$(EXTERIA_CRT_V7)" || { echo "missing EXTERIA_CRT_V7 startup object" >&2; exit 1; },:)
	@test -f "$(EXTERIA_OPENSSL_V7)/lib/libcrypto.a" -a -f "$(EXTERIA_OPENSSL_V64)/lib/libcrypto.a" || { echo "missing openssl static libraries" >&2; exit 1; }

# sdk and openssl overrides must not reuse objects from a previous invocation
force:

# the codec objects are vendored and slow to build, so a changed sdk or flag set rebuilds them through a stamp
# instead of the force rule the core objects use
$(CODEC_STAMP): force | inputs
	@mkdir -p $(dir $@)
	@echo '$(CODEC_STAMP_TEXT)' | cmp -s - $@ || echo '$(CODEC_STAMP_TEXT)' > $@

$(EXTERIA_IOS_BUILD)/armv7/third_party/%.o: third_party/%.c $(CODEC_STAMP)
	@mkdir -p $(dir $@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $(CODEC_FLAGS) $(V7_FLAGS) -c $< -o $@

$(EXTERIA_IOS_BUILD)/arm64/third_party/%.o: third_party/%.c $(CODEC_STAMP)
	@mkdir -p $(dir $@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $(CODEC_FLAGS) $(V64_FLAGS) -c $< -o $@

$(EXTERIA_IOS_BUILD)/armv7/%.o: %.c force | inputs
	@mkdir -p $(dir $@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $(FLAGS) $(V7_FLAGS) -c $< -o $@

$(EXTERIA_IOS_BUILD)/arm64/%.o: %.c force | inputs
	@mkdir -p $(dir $@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $(FLAGS) $(V64_FLAGS) -c $< -o $@

$(EXTERIA_IOS_BUILD)/armv7/libexteria-core.a: $(V7_OBJ)
	@rm -f $@
	"$(EXTERIA_TC)/llvm-ar" rcs $@ $^

$(EXTERIA_IOS_BUILD)/arm64/libexteria-core.a: $(V64_OBJ)
	@rm -f $@
	"$(EXTERIA_TC)/llvm-ar" rcs $@ $^

$(EXTERIA_IOS_BUILD)/libexteria-core.a: $(EXTERIA_IOS_BUILD)/armv7/libexteria-core.a $(EXTERIA_IOS_BUILD)/arm64/libexteria-core.a
	"$(EXTERIA_TC)/lipo" -create $^ -output $@

$(EXTERIA_IOS_BUILD)/armv7/test_mt_client: tests/core/test_mt_client.c tests/core/test_util.h $(EXTERIA_IOS_BUILD)/armv7/libexteria-core.a $(V7_CODEC)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $(FLAGS) $(V7_FLAGS) $< -Wl,-force_load,$(EXTERIA_IOS_BUILD)/armv7/libexteria-core.a $(V7_CODEC) \
	  $(EXTERIA_OPENSSL_V7)/lib/libcrypto.a $(if $(EXTERIA_CRT_V7),-nostartfiles $(EXTERIA_CRT_V7),) -lz -lsqlite3 -o $@

$(EXTERIA_IOS_BUILD)/arm64/test_mt_client: tests/core/test_mt_client.c tests/core/test_util.h $(EXTERIA_IOS_BUILD)/arm64/libexteria-core.a $(V64_CODEC)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $(FLAGS) $(V64_FLAGS) $< -Wl,-force_load,$(EXTERIA_IOS_BUILD)/arm64/libexteria-core.a $(V64_CODEC) \
	  $(EXTERIA_OPENSSL_V64)/lib/libcrypto.a -lz -lsqlite3 -o $@

inspect: all
	"$(EXTERIA_TC)/lipo" -info $(EXTERIA_IOS_BUILD)/libexteria-core.a
	"$(EXTERIA_TC)/otool" -L $(EXTERIA_IOS_BUILD)/armv7/test_mt_client
	"$(EXTERIA_TC)/otool" -L $(EXTERIA_IOS_BUILD)/arm64/test_mt_client
	"$(EXTERIA_TC)/otool" -l $(EXTERIA_IOS_BUILD)/armv7/test_mt_client
	"$(EXTERIA_TC)/otool" -l $(EXTERIA_IOS_BUILD)/arm64/test_mt_client

-include $(V7_OBJ:.o=.d) $(V64_OBJ:.o=.d) $(V7_CODEC:.o=.d) $(V64_CODEC:.o=.d)
