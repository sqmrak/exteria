CC ?= cc
PKG_CONFIG ?= pkg-config
BUILD ?= ../../build/video-tests
CFLAGS ?= -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer
FFMPEG_FLAGS = $(shell $(PKG_CONFIG) --cflags libavformat libavcodec libavutil)
FFMPEG_LIBS = $(shell $(PKG_CONFIG) --libs libavformat libavcodec libavutil)
FLAC_LIBS = $(shell $(PKG_CONFIG) --libs libavformat libavcodec libavutil libswresample)

VPX_FLAGS = $(shell $(PKG_CONFIG) --cflags vpx)
VPX_LIBS = $(shell $(PKG_CONFIG) --libs vpx)
CORE_INC = -I../../core/video -I../../core/base -I../../core/calls

.PHONY: test test-flac
test: test-vp8 test-flac

	@command -v ffmpeg >/dev/null || { echo 'ffmpeg is required for local VP9 fixtures' >&2; exit 1; }
	@$(PKG_CONFIG) --exists libavformat libavcodec libavutil || { echo 'ffmpeg development libraries are required' >&2; exit 1; }
	@mkdir -p $(BUILD)
	ffmpeg -nostdin -v error -f lavfi -i 'color=c=red@0.5:s=64x32:r=30:d=1,format=yuva420p' -c:v libvpx-vp9 -auto-alt-ref 0 -y $(BUILD)/alpha.webm
	ffmpeg -nostdin -v error -f lavfi -i 'color=c=blue:s=64x32:r=30:d=1' -c:v libvpx -auto-alt-ref 0 -y $(BUILD)/vp8.webm
	ffmpeg -nostdin -v error -f lavfi -i 'color=c=blue:s=514x32:r=30:d=0.1' -c:v libvpx-vp9 -y $(BUILD)/oversize.webm
	$(CC) -std=c99 -Wall -Wextra -Werror -Wconversion -Wno-sign-conversion $(CFLAGS) $(FFMPEG_FLAGS) -I../../core/video test_video_sticker.c ../../core/video/exteria_video_sticker.c $(FFMPEG_LIBS) -lm -o $(BUILD)/test_video
	$(BUILD)/test_video $(BUILD)/alpha.webm $(BUILD)/vp8.webm $(BUILD)/oversize.webm

test-flac:
	@command -v ffmpeg >/dev/null || { echo 'ffmpeg is required for local FLAC fixtures' >&2; exit 1; }
	@$(PKG_CONFIG) --exists libavformat libavcodec libavutil libswresample || { echo 'ffmpeg development libraries are required' >&2; exit 1; }
	@mkdir -p $(BUILD)
	ffmpeg -nostdin -v error -f lavfi -i 'sine=frequency=440:sample_rate=96000:duration=1' -ac 2 -sample_fmt s32 -c:a flac -y $(BUILD)/audio.flac
	ffmpeg -nostdin -v error -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=1' -ac 1 -sample_fmt s16 -c:a flac -y $(BUILD)/mono.flac
	ffmpeg -nostdin -v error -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1' -ac 6 -sample_fmt s16 -c:a flac -y $(BUILD)/surround.flac
	printf 'fLaCbroken' > $(BUILD)/bad.flac
	head -c $$(($$(wc -c < $(BUILD)/audio.flac) / 2)) $(BUILD)/audio.flac > $(BUILD)/truncated.flac
	python3 -c 'from pathlib import Path; p=Path("$(BUILD)/audio.flac"); b=bytearray(p.read_bytes()); b[21]=(b[21]&240)|15; b[22:26]=bytes([255]*4); Path("$(BUILD)/oversize.flac").write_bytes(b)'
	$(CC) -std=c99 -Wall -Wextra -Werror -Wconversion -Wno-sign-conversion $(CFLAGS) $(FFMPEG_FLAGS) $(CORE_INC) test_flac.c ../../core/video/exteria_flac.c $(FLAC_LIBS) -lm -o $(BUILD)/test_flac
	$(BUILD)/test_flac "$(abspath $(BUILD)/audio.flac)" "$(abspath $(BUILD)/bad.flac)" "$(abspath $(BUILD)/audio.wav)" 2 48000 "$(abspath $(BUILD)/oversize.flac)"
	$(BUILD)/test_flac "$(abspath $(BUILD)/audio.flac)" "$(abspath $(BUILD)/truncated.flac)" "$(abspath $(BUILD)/audio.wav)" 2 48000 "$(abspath $(BUILD)/oversize.flac)"
	$(BUILD)/test_flac "$(abspath $(BUILD)/mono.flac)" "$(abspath $(BUILD)/bad.flac)" "$(abspath $(BUILD)/audio.wav)" 1 44100 "$(abspath $(BUILD)/oversize.flac)"
	$(BUILD)/test_flac "$(abspath $(BUILD)/surround.flac)" "$(abspath $(BUILD)/bad.flac)" "$(abspath $(BUILD)/audio.wav)" 2 48000 "$(abspath $(BUILD)/oversize.flac)"

# the call codec: encoder, packets, depacketizer and decoder together, under the address sanitizer
.PHONY: test-vp8
test-vp8:
	@$(PKG_CONFIG) --exists vpx || { echo 'libvpx development files with VP8 are required' >&2; exit 1; }
	@mkdir -p $(BUILD)
	$(CC) -std=c99 -Wall -Wextra -Werror -Wconversion -Wno-sign-conversion $(CFLAGS) $(VPX_FLAGS) $(CORE_INC) test_vp8.c ../../core/video/exteria_vp8.c ../../core/calls/exteria_vp8_rtp.c ../../core/base/exteria_status.c $(VPX_LIBS) -lm -o $(BUILD)/test_vp8
	$(BUILD)/test_vp8
