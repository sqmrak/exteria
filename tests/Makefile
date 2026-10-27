CC      ?= cc
BUILD   ?= ../build/host
ROOT    := ..
INCLUDE := -I$(ROOT)/core/base -I$(ROOT)/core/crypto -I$(ROOT)/core/tl -I$(ROOT)/core/tl/generated \
           -I$(ROOT)/core/client -I$(ROOT)/core/mtproto -I$(ROOT)/core/auth -I$(ROOT)/core/updates \
           -I$(ROOT)/core/storage -I$(ROOT)/core/secret_chats -I$(ROOT)/core/layout -I$(ROOT)/core/phone -I$(ROOT)/core/session -I$(ROOT)/core/chats -I$(ROOT)/core/emoji -I$(ROOT)/core/media -I$(ROOT)/core/notify -I$(ROOT)/core/calls -I$(ROOT)/core/tgcalls -I$(ROOT)/core/video -I$(ROOT)/core/shiro \
           -I$(ROOT)/third_party/opus/include -I$(ROOT)/third_party/ogg/include -Icore
WARN    := -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes -Wmissing-prototypes -Wconversion -Wno-sign-conversion
OPT     ?= -O2 -g
CFLAGS   = $(OPT) -std=c99 -D_POSIX_C_SOURCE=200809L -D_DEFAULT_SOURCE $(WARN) $(INCLUDE)
LDLIBS  := -lpthread -lssl -lcrypto -lz -lsqlite3 -lm

BASE_SRC   := $(wildcard $(ROOT)/core/base/*.c)
CRYPTO_SRC := $(wildcard $(ROOT)/core/crypto/*.c)
# opus and ogg are vendored as upstream ships them: fixed point, encoder and decoder, no asm
OPUS_SRC   := $(addprefix $(ROOT)/third_party/opus/,$(shell cat $(ROOT)/third_party/opus/SOURCES))
OGG_SRC    := $(wildcard $(ROOT)/third_party/ogg/src/*.c)
OPUS_FLAGS := -std=c99 -O2 -w -DOPUS_BUILD -DFIXED_POINT -DDISABLE_FLOAT_API -DVAR_ARRAYS -DPACKAGE_VERSION=\"1.5.2\" \
              -I$(ROOT)/third_party/opus/include -I$(ROOT)/third_party/opus/celt -I$(ROOT)/third_party/opus/silk \
              -I$(ROOT)/third_party/opus/silk/fixed -I$(ROOT)/third_party/opus/src -I$(ROOT)/third_party/ogg/include
TESTS      := $(patsubst core/%.c,%,$(wildcard core/test_*.c))
HELPER_OBJ := $(patsubst core/%.c,$(BUILD)/helpers/%.o,$(wildcard core/fake_*.c))

# linking the whole core catches missing subsystem dependencies
CORE_SRC := $(BASE_SRC) $(CRYPTO_SRC) $(wildcard $(ROOT)/core/tl/*.c) $(wildcard $(ROOT)/core/tl/generated/*.c) \
            $(wildcard $(ROOT)/core/mtproto/*.c) $(wildcard $(ROOT)/core/auth/*.c) \
            $(wildcard $(ROOT)/core/updates/*.c) $(wildcard $(ROOT)/core/storage/*.c) \
            $(wildcard $(ROOT)/core/secret_chats/*.c) $(wildcard $(ROOT)/core/client/*.c) \
            $(wildcard $(ROOT)/core/layout/*.c) $(wildcard $(ROOT)/core/phone/*.c) \
            $(wildcard $(ROOT)/core/session/*.c) $(wildcard $(ROOT)/core/chats/*.c) $(wildcard $(ROOT)/core/emoji/*.c) \
            $(wildcard $(ROOT)/core/media/*.c) $(wildcard $(ROOT)/core/notify/*.c) $(wildcard $(ROOT)/core/calls/*.c) $(wildcard $(ROOT)/core/tgcalls/*.c) $(wildcard $(ROOT)/core/shiro/*.c) $(ROOT)/core/video/exteria_yuv.c $(OPUS_SRC) $(OGG_SRC)
CORE_OBJ := $(patsubst $(ROOT)/%.c,$(BUILD)/%.o,$(CORE_SRC))

.PHONY: test sanitize

test: $(addprefix $(BUILD)/,$(TESTS))
	@set -e; for t in $(TESTS); do $(BUILD)/$$t; done

sanitize:
	$(MAKE) BUILD=$(BUILD)-asan OPT="-O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer" \
	    LDFLAGS="-fsanitize=address,undefined" test

$(BUILD)/third_party/%.o: $(ROOT)/third_party/%.c
	@mkdir -p $(dir $@)
	$(CC) $(OPUS_FLAGS) -MMD -MP -c $< -o $@

$(BUILD)/%.o: $(ROOT)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD)/helpers/%.o: core/%.c core/test_util.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD)/test_%: core/test_%.c $(CORE_OBJ) $(HELPER_OBJ) core/test_util.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -MMD -MP $< $(CORE_OBJ) $(HELPER_OBJ) $(LDFLAGS) $(LDLIBS) -o $@

# host tests must not depend on a public telegram server
.PHONY: probes
probes: $(BUILD)/probe_handshake $(BUILD)/probe_login

$(BUILD)/probe_%: probe/probe_%.c $(CORE_OBJ)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -MMD -MP $< $(CORE_OBJ) $(LDFLAGS) $(LDLIBS) -o $@

-include $(CORE_OBJ:.o=.d) $(HELPER_OBJ:.o=.d) $(addprefix $(BUILD)/,$(addsuffix .d,$(TESTS)))
