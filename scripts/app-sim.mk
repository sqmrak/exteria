# the app for the iOS Simulator: the arm64 slice of app-ios.mk built against the iphonesimulator sdk for one
# architecture of the simulator, EXTERIA_SIM_ARCH (arm64 or x86_64); scripts/build_simulator.sh drives it
EXTERIA_SIM_ARCH ?= arm64
EXTERIA_SIM_MIN ?= 14.0
EXTERIA_SIM_SDK ?= $(shell xcrun --sdk iphonesimulator --show-sdk-path)

# the armv7 slice is never built here, so its inputs only need a name
override EXTERIA_SDK_V7 := /nonexistent
override EXTERIA_OPENSSL_V7 := /nonexistent
override EXTERIA_VIDEO_V7 := /nonexistent
override EXTERIA_SDK_V64 := $(EXTERIA_SIM_SDK)
override V64_TARGET := -target $(EXTERIA_SIM_ARCH)-apple-ios$(EXTERIA_SIM_MIN)-simulator -isysroot $(EXTERIA_SIM_SDK)

include scripts/app-ios.mk

# the current sdk marks the old calls deprecated and the current clang makes a few old warnings errors; the device
# build keeps its strict flags, this one only has to run
SIM_RELAX := -Wno-error -Wno-deprecated-declarations -Wno-deprecated-implementations -Wno-unguarded-availability-new \
             -Wno-error=implicit-function-declaration -Wno-error=incompatible-function-pointer-types \
             -Wno-error=incompatible-pointer-types -Wno-error=int-conversion
OBJC_FLAGS += $(SIM_RELAX)
C_FLAGS += $(SIM_RELAX)
CXX_FLAGS += -D_LIBCPP_DISABLE_AVAILABILITY
TGV_FLAGS += -D_LIBCPP_DISABLE_AVAILABILITY

.PHONY: sim-binary print-resources
inputs:
	@test -x "$(EXTERIA_TC)/clang" || { echo "missing toolchain in EXTERIA_TC" >&2; exit 1; }
	@test -f "$(EXTERIA_SIM_SDK)/usr/include/stdlib.h" || { echo "missing iphonesimulator sdk" >&2; exit 1; }
	@test -f "$(EXTERIA_OPENSSL_V64)/lib/libcrypto.a" -a -f "$(EXTERIA_OPENSSL_V64)/lib/libssl.a" || { echo "missing openssl in $(EXTERIA_OPENSSL_V64)" >&2; exit 1; }
	@for lib in $(VIDEO_V64_LIBS); do test -f "$$lib" || { echo "missing codec $$lib" >&2; exit 1; }; done

sim-binary: $(EXTERIA_IOS_BUILD)/arm64/$(APP_NAME)

print-resources:
	@echo $(RES)
