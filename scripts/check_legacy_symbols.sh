#!/usr/bin/env bash
# every symbol the armv7 slice imports must exist in the iOS 5 runtime, or dyld refuses to launch it
set -euo pipefail

BIN="${1:?usage: check_legacy_symbols.sh <fat executable>}"
TC="${EXTERIA_TC:?set EXTERIA_TC to the ios toolchain bin directory}"
SDK5="${EXTERIA_SDK_V5:?set EXTERIA_SDK_V5 to an iphoneos 5.x sdk}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

"${TC}/lipo" -thin armv7 "${BIN}" -output "${WORK}/armv7"
"${TC}/nm" -u "${WORK}/armv7" | awk '{print $NF}' | sort -u > "${WORK}/need"

libs=("${SDK5}"/usr/lib/*.dylib "${SDK5}"/usr/lib/system/*.dylib)
for name in UIKit Foundation Security CoreGraphics QuartzCore CoreFoundation CoreText ImageIO AVFoundation CoreMedia CoreVideo CoreAudio AudioToolbox CoreLocation CoreMotion MobileCoreServices CFNetwork AssetsLibrary AddressBook AddressBookUI; do
    libs+=("${SDK5}/System/Library/Frameworks/${name}.framework/${name}")
done
for lib in "${libs[@]}"; do
    [[ -f "${lib}" && ! -L "${lib}" ]] || continue
    "${TC}/nm" -gU "${lib}" 2>/dev/null | awk '{print $NF}' || true
done | sort -u > "${WORK}/have"

[[ -s "${WORK}/have" ]] || { echo "no exports read from ${SDK5}" >&2; exit 1; }
missing="$(comm -23 "${WORK}/need" "${WORK}/have")"
if [[ -n "${missing}" ]]; then
    echo "armv7 slice imports symbols the iOS 5 runtime does not export:" >&2
    echo "${missing}" >&2
    exit 1
fi
echo "armv7 imports: $(wc -l < "${WORK}/need") symbols, all present in ${SDK5##*/}"

# the arm64 slice is built against a newer sdk, which moves classes into frameworks that ios 10 and 11
# do not have (AVAudioPlayer lives in AVFAudio there)
"${TC}/lipo" -thin arm64 "${BIN}" -output "${WORK}/arm64"
allowed=" AddressBook AddressBookUI AssetsLibrary AudioToolbox AVFoundation CFNetwork CoreAudio CoreFoundation CoreGraphics CoreLocation CoreMedia CoreMotion CoreText CoreVideo Foundation ImageIO MediaPlayer MobileCoreServices QuartzCore Security UIKit "
bad=""
while read -r path _; do
    case "${path}" in
    /System/Library/Frameworks/*.framework/*) name="${path##*/}"; [[ "${allowed}" == *" ${name} "* ]] || bad+="${path}"$'\n' ;;
    esac
done < <("${TC}/otool" -L "${WORK}/arm64" | tail -n +2)
if [[ -n "${bad}" ]]; then
    echo "arm64 slice loads frameworks the old systems do not carry:" >&2
    echo "${bad}" >&2
    exit 1
fi
echo "arm64 loads only frameworks of ios 10"
