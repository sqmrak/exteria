EXTERIA_TC ?= $(error set EXTERIA_TC to the ios toolchain bin directory)
EXTERIA_SDK_V7 ?= $(error set EXTERIA_SDK_V7 to a legacy iphoneos sdk)
EXTERIA_SDK_V64 ?= $(error set EXTERIA_SDK_V64 to an arm64 iphoneos sdk)
EXTERIA_OPENSSL_V7 ?= $(error set EXTERIA_OPENSSL_V7 to an armv7 openssl prefix)
EXTERIA_OPENSSL_V64 ?= $(error set EXTERIA_OPENSSL_V64 to an arm64 openssl prefix)
EXTERIA_VIDEO_V7 ?= $(error set EXTERIA_VIDEO_V7 to the armv7 ffmpeg and libvpx prefix)
EXTERIA_VIDEO_V64 ?= $(error set EXTERIA_VIDEO_V64 to the arm64 ffmpeg and libvpx prefix)
EXTERIA_CRT_V7 ?=
EXTERIA_LDID ?= $(EXTERIA_TC)/ldid
EXTERIA_IOS_BUILD ?= build/ios

APP_NAME := Exteria
APP := $(EXTERIA_IOS_BUILD)/$(APP_NAME).app

APP_M := $(sort $(wildcard app/*/*.m app/*/*/*.m))
APP_C := $(sort $(wildcard core/*/*.c core/tl/generated/*.c))
CREDENTIALS := $(EXTERIA_IOS_BUILD)/generated/exteria_credentials.h
WEBP_C := $(sort $(wildcard third_party/libwebp/src/*/*.c))
OPUS_C := $(addprefix third_party/opus/,$(shell cat third_party/opus/SOURCES))
OGG_C := $(sort $(wildcard third_party/ogg/src/*.c))
# the QR reader of the devices screen: the listed files of zbar are its QR-only build
ZBAR_C := $(addprefix third_party/zbar/zbar/,config.c error.c symbol.c image.c refcnt.c img_scanner.c scanner.c decoder.c misc.c decoder/qr_finder.c \
  qrcode/qrdec.c qrcode/qrdectxt.c qrcode/rs.c qrcode/isaac.c qrcode/bch15_5.c qrcode/binarize.c qrcode/util.c)
# the call engine: libtgvoip as vendored, without the webrtc dsp and the other platforms' audio, and the glue that gives it a C face
TGV_CPP := $(sort $(wildcard third_party/libtgvoip/*.cpp third_party/libtgvoip/audio/*.cpp third_party/libtgvoip/os/posix/*.cpp \
  third_party/libtgvoip/os/darwin/*.cpp))
RL_CPP := $(sort $(wildcard third_party/rlottie/src/*/*.cpp third_party/rlottie/src/*/*/*.cpp))
RES := $(sort $(wildcard resources/icons/*.png resources/launch/*.png resources/animations/*.tgs \
  resources/phone/*.png resources/phone/*.txt resources/popup/*.jpg resources/fonts/*.ttf resources/fonts/*.otf resources/fonts/*.txt \
  resources/chat/*.jpg resources/chat/*.png resources/emoji/*.pack resources/emoji/*.txt resources/licenses/*.txt resources/shiro/*.pem resources/maps/*.pem resources/web/*.pem resources/sounds/*.caf resources/sounds/*.mp3))
STRINGS := $(sort $(wildcard resources/localization/*.lproj/Localizable.strings))

APP_INC := $(addprefix -I,$(sort $(dir $(APP_M)))) $(addprefix -I,$(wildcard core/*)) -Icore/tl/generated \
           -I$(dir $(CREDENTIALS)) -Ithird_party/rlottie/inc -Ithird_party/libwebp \
           -Ithird_party/opus/include -Ithird_party/ogg/include -Ithird_party/libtgvoip -Ithird_party/zbar/include
RL_INC := -Ithird_party/rlottie/config -Ithird_party/rlottie/inc -Ithird_party/rlottie/src/vector \
          -Ithird_party/rlottie/src/vector/freetype -Ithird_party/rlottie/src/vector/pixman \
          -Ithird_party/rlottie/src/lottie -Ithird_party/rlottie/src/binding/c

OBJC_FLAGS := -std=gnu99 -fno-objc-arc -fblocks -O2 -g -Wall -Wextra -Wno-unused-parameter $(APP_INC) -MMD -MP
C_FLAGS := -std=c99 -O2 -g -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes -Wmissing-prototypes -Wconversion -Wno-sign-conversion $(APP_INC) -MMD -MP
# portable raster path on both slices: the neon asm needs a build of its own
# the upstream sources miss includes that the sdk headers used to pull in
CXX_FLAGS := -std=c++14 -stdlib=libc++ -fno-exceptions -fno-rtti -fvisibility=hidden -O2 -g -w \
             -U__ARM_NEON__ -include limits -include cstdint $(RL_INC) -MMD -MP
# libc++ marks std::future_error iOS 6 only
V7_CXX_FLAGS := -D_LIBCPP_DISABLE_AVAILABILITY

# libwebp is vendored as upstream ships it, so it builds without the project's strict warnings
WEBP_FLAGS := -std=c99 -O2 -g -w -Ithird_party/libwebp -MMD -MP
# zbar is vendored as upstream ships it, so it builds without the project's strict warnings; SENKO_ZBAR_IOS keeps its timer off the POSIX timers ios lacks
ZBAR_FLAGS := -std=gnu99 -O2 -g -w -DSENKO_ZBAR_IOS -Ithird_party/zbar/include -Ithird_party/zbar/zbar -Ithird_party/zbar/zbar/decoder -Ithird_party/zbar/zbar/qrcode -MMD -MP

# opus is the fixed point build without asm, so both slices run the same portable code; ogg needs no flags
OPUS_FLAGS := -std=c99 -O2 -g -w -DOPUS_BUILD -DFIXED_POINT -DDISABLE_FLOAT_API -DVAR_ARRAYS -DPACKAGE_VERSION=\"1.5.2\" \
              -Ithird_party/opus/include -Ithird_party/opus/celt -Ithird_party/opus/silk -Ithird_party/opus/silk/fixed \
              -Ithird_party/opus/src -Ithird_party/ogg/include -MMD -MP

# libtgvoip throws and casts across its address classes, so it keeps exceptions and rtti on
TGV_FLAGS := -std=c++14 -stdlib=libc++ -fvisibility=hidden -O2 -g -w -DTGVOIP_NO_DSP -DTGVOIP_LOG_VERBOSITY=2 \
             -Ithird_party/libtgvoip -Ithird_party/opus/include -Iapp/net -Icore/shiro -Icore/base -MMD -MP

V7_TARGET := -target armv7-apple-ios5.0 -isysroot $(EXTERIA_SDK_V7)
V64_TARGET := -target arm64-apple-ios7.0 -isysroot $(EXTERIA_SDK_V64)
# the core reaches openssl by its own headers on each slice
V7_CC := -isystem $(EXTERIA_VIDEO_V7)/include $(V7_TARGET) -I$(EXTERIA_OPENSSL_V7)/include
V64_CC := -isystem $(EXTERIA_VIDEO_V64)/include $(V64_TARGET) -I$(EXTERIA_OPENSSL_V64)/include
LINK_LIBS := -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework ImageIO -framework CoreText -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreAudio -framework AudioToolbox -framework CoreLocation -weak_framework CoreMotion -framework MobileCoreServices -framework CFNetwork -weak_framework AssetsLibrary -weak_framework AddressBook -weak_framework AddressBookUI -weak_framework MediaPlayer -lz -lc++ -lsqlite3 -liconv

VIDEO_LIB_NAMES := libavformat.a libavcodec.a libavutil.a libvpx.a
VIDEO_V7_LIBS := $(addprefix $(EXTERIA_VIDEO_V7)/lib/,$(VIDEO_LIB_NAMES))
VIDEO_V64_LIBS := $(addprefix $(EXTERIA_VIDEO_V64)/lib/,$(VIDEO_LIB_NAMES))
SLICES := armv7 arm64
OBJ_SRC := $(APP_M) $(APP_C) $(RL_CPP) $(WEBP_C) $(OPUS_C) $(OGG_C) $(ZBAR_C) $(TGV_CPP)
# every object lives under its slice: $(B)/armv7/app/ui/shared/x.m.o
objects = $(addprefix $(EXTERIA_IOS_BUILD)/$(1)/,$(addsuffix .o,$(OBJ_SRC)))

STAMP := $(EXTERIA_IOS_BUILD)/flags.stamp
FLAGS_TEXT := $(EXTERIA_TC) $(V7_CC) $(V64_CC) $(EXTERIA_CRT_V7) $(OBJC_FLAGS) $(C_FLAGS) $(CXX_FLAGS) $(V7_CXX_FLAGS) $(WEBP_FLAGS) $(OPUS_FLAGS) $(ZBAR_FLAGS) $(TGV_FLAGS)

.PHONY: app app-unsigned inspect-unsigned inputs force inspect-app check-legacy-symbols check-legacy-api
app: $(EXTERIA_IOS_BUILD)/app-signed.stamp

app-unsigned: $(APP)/$(APP_NAME)

inputs:
	@for lib in $(VIDEO_V7_LIBS) $(VIDEO_V64_LIBS); do test -f "$$lib" || { echo "missing sticker codec $$lib" >&2; exit 1; }; done
	@test -x "$(EXTERIA_TC)/clang" -a -x "$(EXTERIA_TC)/lipo" -a -x "$(EXTERIA_TC)/otool" || { echo "missing ios toolchain in EXTERIA_TC" >&2; exit 1; }
	@test -f "$(EXTERIA_SDK_V7)/usr/include/stdlib.h" -a -f "$(EXTERIA_SDK_V64)/usr/include/stdlib.h" || { echo "missing iphoneos sdk headers" >&2; exit 1; }
	@$(if $(EXTERIA_CRT_V7),test -f "$(EXTERIA_CRT_V7)" || { echo "missing EXTERIA_CRT_V7 startup object" >&2; exit 1; },:)
	@test -f "$(EXTERIA_OPENSSL_V7)/lib/libcrypto.a" -a -f "$(EXTERIA_OPENSSL_V64)/lib/libcrypto.a" -a -f "$(EXTERIA_OPENSSL_V7)/lib/libssl.a" -a -f "$(EXTERIA_OPENSSL_V64)/lib/libssl.a" || { echo "missing openssl static libraries" >&2; exit 1; }

# a changed sdk or flag set must not reuse objects from a previous invocation
force:

# the api id and hash come from the environment, see local/credentials.env, and never enter the repository
$(CREDENTIALS): force | inputs
	@echo "$(EXTERIA_API_ID)" | grep -Eq '^[0-9]+$$' || { echo "set EXTERIA_API_ID to the numeric telegram api id" >&2; exit 1; }
	@echo "$(EXTERIA_API_HASH)" | grep -Eq '^[0-9a-f]{32}$$' || { echo "set EXTERIA_API_HASH to the 32 character telegram api hash" >&2; exit 1; }
	@mkdir -p $(dir $@)
	@printf '#define EXTERIA_API_ID %s\n#define EXTERIA_API_HASH "%s"\n' "$(EXTERIA_API_ID)" "$(EXTERIA_API_HASH)" > $@.new
	@cmp -s $@.new $@ && rm $@.new || mv $@.new $@

$(STAMP): force | inputs $(CREDENTIALS)
	@mkdir -p $(dir $@)
	@echo '$(FLAGS_TEXT)' | cmp -s - $@ || echo '$(FLAGS_TEXT)' > $@

define slice_rules
$(EXTERIA_IOS_BUILD)/$(1)/%.m.o: %.m $(STAMP)
	@mkdir -p $$(dir $$@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $$(OBJC_FLAGS) $(2) -c $$< -o $$@
$(EXTERIA_IOS_BUILD)/$(1)/third_party/libwebp/%.c.o: third_party/libwebp/%.c $(STAMP)
	@mkdir -p $$(dir $$@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $$(WEBP_FLAGS) $(2) -c $$< -o $$@
$(EXTERIA_IOS_BUILD)/$(1)/third_party/zbar/%.c.o: third_party/zbar/%.c $(STAMP)
	@mkdir -p $$(dir $$@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $$(ZBAR_FLAGS) $(2) -c $$< -o $$@
$(EXTERIA_IOS_BUILD)/$(1)/third_party/opus/%.c.o: third_party/opus/%.c $(STAMP)
	@mkdir -p $$(dir $$@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $$(OPUS_FLAGS) $(2) -c $$< -o $$@
$(EXTERIA_IOS_BUILD)/$(1)/third_party/ogg/%.c.o: third_party/ogg/%.c $(STAMP)
	@mkdir -p $$(dir $$@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $$(OPUS_FLAGS) $(2) -c $$< -o $$@
$(EXTERIA_IOS_BUILD)/$(1)/third_party/libtgvoip/%.cpp.o: third_party/libtgvoip/%.cpp $(STAMP)
	@mkdir -p $$(dir $$@)
	"$(EXTERIA_TC)/clang++" -B"$(EXTERIA_TC)" $$(TGV_FLAGS) $(3) $(2) -c $$< -o $$@
$(EXTERIA_IOS_BUILD)/$(1)/%.c.o: %.c $(STAMP)
	@mkdir -p $$(dir $$@)
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $$(C_FLAGS) $(2) -c $$< -o $$@
$(EXTERIA_IOS_BUILD)/$(1)/%.cpp.o: %.cpp $(STAMP)
	@mkdir -p $$(dir $$@)
	"$(EXTERIA_TC)/clang++" -B"$(EXTERIA_TC)" $$(CXX_FLAGS) $(3) $(2) -c $$< -o $$@
endef
$(eval $(call slice_rules,armv7,$(V7_CC),$(V7_CXX_FLAGS)))
$(eval $(call slice_rules,arm64,$(V64_CC),))

$(EXTERIA_IOS_BUILD)/armv7/$(APP_NAME): $(call objects,armv7) $(VIDEO_V7_LIBS) $(EXTERIA_OPENSSL_V7)/lib/libssl.a $(EXTERIA_OPENSSL_V7)/lib/libcrypto.a
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $(V7_TARGET) $(call objects,armv7) $(EXTERIA_OPENSSL_V7)/lib/libssl.a $(EXTERIA_OPENSSL_V7)/lib/libcrypto.a $(VIDEO_V7_LIBS) $(LINK_LIBS) \
	  $(if $(EXTERIA_CRT_V7),-nostartfiles $(EXTERIA_CRT_V7),) -o $@

$(EXTERIA_IOS_BUILD)/arm64/$(APP_NAME): $(call objects,arm64) $(VIDEO_V64_LIBS) $(EXTERIA_OPENSSL_V64)/lib/libssl.a $(EXTERIA_OPENSSL_V64)/lib/libcrypto.a
	"$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" $(V64_TARGET) $(call objects,arm64) $(EXTERIA_OPENSSL_V64)/lib/libssl.a $(EXTERIA_OPENSSL_V64)/lib/libcrypto.a $(VIDEO_V64_LIBS) $(LINK_LIBS) -o $@

# staged from scratch so a removed resource cannot survive a rebuild
$(APP)/$(APP_NAME): $(EXTERIA_IOS_BUILD)/armv7/$(APP_NAME) $(EXTERIA_IOS_BUILD)/arm64/$(APP_NAME) packaging/Info.plist $(RES) $(STRINGS)
	rm -rf $(APP)
	mkdir -p $(APP)
	"$(EXTERIA_TC)/lipo" -create $(EXTERIA_IOS_BUILD)/armv7/$(APP_NAME) $(EXTERIA_IOS_BUILD)/arm64/$(APP_NAME) -output $@
	cp packaging/Info.plist $(APP)/Info.plist
	cp $(RES) $(APP)/
	for dir in $(sort $(dir $(STRINGS))); do mkdir -p $(APP)/$$(basename $$dir) && cp $$dir/Localizable.strings $(APP)/$$(basename $$dir)/; done

$(EXTERIA_IOS_BUILD)/app-signed.stamp: $(APP)/$(APP_NAME)
	@test -x "$(EXTERIA_LDID)" || { echo "missing signer in EXTERIA_LDID" >&2; exit 1; }
	"$(EXTERIA_LDID)" -S $(APP)/$(APP_NAME)
	@touch $@

inspect-app: app
inspect-unsigned: app-unsigned

inspect-app inspect-unsigned:
	"$(EXTERIA_TC)/lipo" -info $(APP)/$(APP_NAME)
	for slice in $(SLICES); do \
	  echo "== $$slice"; \
	  "$(EXTERIA_TC)/otool" -arch $$slice -L $(APP)/$(APP_NAME); \
	  "$(EXTERIA_TC)/otool" -arch $$slice -l $(APP)/$(APP_NAME) | grep -A3 -E 'LC_VERSION_MIN_IPHONEOS|LC_BUILD_VERSION'; \
	done
	$(MAKE) -f scripts/app-ios.mk check-legacy-symbols check-legacy-api

# the ios 6.1 headers carry availability marks, so anything newer than the 5.0 target is flagged
check-legacy-api:
	@test -n "$(EXTERIA_SDK_V6)" || { echo "set EXTERIA_SDK_V6 to the iphoneos 6.1 sdk" >&2; exit 1; }
	@set -e; for src in $(APP_M); do \
	  "$(EXTERIA_TC)/clang" -B"$(EXTERIA_TC)" -std=gnu99 -fno-objc-arc -fblocks -Wpartial-availability -Werror=partial-availability \
	    $(APP_INC) -isystem $(EXTERIA_VIDEO_V7)/include -I$(EXTERIA_OPENSSL_V7)/include -target armv7-apple-ios5.0 -isysroot $(EXTERIA_SDK_V6) -fsyntax-only $$src; \
	done; echo "app sources use no api newer than ios 5.0 in the ios 6.1 headers"

check-legacy-symbols:
	bash scripts/check_legacy_symbols.sh $(APP)/$(APP_NAME)

-include $(foreach s,$(SLICES),$(patsubst %.o,%.d,$(call objects,$(s))))
