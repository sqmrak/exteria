CC ?= cc
PKG_CONFIG ?= pkg-config
BUILD ?= ../../build/video-tests
CFLAGS ?= -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer
FFMPEG_FLAGS = $(shell $(PKG_CONFIG) --cflags libavformat libavcodec libavutil)
FFMPEG_LIBS = $(shell $(PKG_CONFIG) --libs libavformat libavcodec libavutil)

VPX_FLAGS = $(shell $(PKG_CONFIG) --cflags vpx)
VPX_LIBS = $(shell $(PKG_CONFIG) --libs vpx)
CORE_INC = -I../../core/video -I../../core/base -I../../core/calls

.PHONY: test
test: test-vp8

	@command -v ffmpeg >/dev/null || { echo 'ffmpeg is required for local VP9 fixtures' >&2; exit 1; }
	@$(PKG_CONFIG) --exists libavformat libavcodec libavutil || { echo 'ffmpeg development libraries are required' >&2; exit 1; }
	@mkdir -p $(BUILD)
	ffmpeg -nostdin -v error -f lavfi -i 'color=c=red@0.5:s=64x32:r=30:d=1,format=yuva420p' -c:v libvpx-vp9 -auto-alt-ref 0 -y $(BUILD)/alpha.webm
	ffmpeg -nostdin -v error -f lavfi -i 'color=c=blue:s=64x32:r=30:d=1' -c:v libvpx -auto-alt-ref 0 -y $(BUILD)/vp8.webm
	ffmpeg -nostdin -v error -f lavfi -i 'color=c=blue:s=514x32:r=30:d=0.1' -c:v libvpx-vp9 -y $(BUILD)/oversize.webm
	$(CC) -std=c99 -Wall -Wextra -Werror -Wconversion -Wno-sign-conversion $(CFLAGS) $(FFMPEG_FLAGS) -I../../core/video test_video_sticker.c ../../core/video/exteria_video_sticker.c $(FFMPEG_LIBS) -lm -o $(BUILD)/test_video
	$(BUILD)/test_video $(BUILD)/alpha.webm $(BUILD)/vp8.webm $(BUILD)/oversize.webm

# the call codec: encoder, packets, depacketizer and decoder together, under the address sanitizer
.PHONY: test-vp8
test-vp8:
	@$(PKG_CONFIG) --exists vpx || { echo 'libvpx development files with VP8 are required' >&2; exit 1; }
	@mkdir -p $(BUILD)
	$(CC) -std=c99 -Wall -Wextra -Werror -Wconversion -Wno-sign-conversion $(CFLAGS) $(VPX_FLAGS) $(CORE_INC) test_vp8.c ../../core/video/exteria_vp8.c ../../core/calls/exteria_vp8_rtp.c ../../core/base/exteria_status.c $(VPX_LIBS) -lm -o $(BUILD)/test_vp8
	$(BUILD)/test_vp8
