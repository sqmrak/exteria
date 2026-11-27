#!/usr/bin/env bash
# stages the flat resources of the app bundle for the ipa and the deb, the binaries and the python tree are added by the packages
set -euo pipefail

dest="${1:?usage: stage_bundle.sh <bundle dir>}"
cd "$(dirname "$0")/.."
shopt -s nullglob

rm -rf "${dest}"
mkdir -p "${dest}/exteria-original-icons"
files=(resources/icons/*.png resources/launch/*.png resources/animations/*.tgs resources/animations/*.mp4
    resources/phone/*.png resources/phone/*.txt resources/popup/*.jpg resources/popup/*.png
    resources/fonts/*.ttf resources/fonts/*.otf resources/fonts/*.txt
    resources/chat/*.jpg resources/chat/*.png resources/emoji/*.pack resources/emoji/*.txt
    resources/licenses/*.txt resources/shiro/*.pem resources/maps/*.pem resources/web/*.pem
    resources/sounds/*.caf resources/sounds/*.mp3)
cp "${files[@]}" "${dest}/"
cp resources/icons/Icon*.png "${dest}/exteria-original-icons/"
# a language folder holds one Localizable.strings
for strings in resources/localization/*.lproj/Localizable.strings; do
    lproj="$(basename "$(dirname "${strings}")")"
    mkdir -p "${dest}/${lproj}"
    cp "${strings}" "${dest}/${lproj}/"
done
