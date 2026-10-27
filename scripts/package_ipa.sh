#!/usr/bin/env bash
# pack the staged app into an ipa; signing is the ldid pseudo signature from the build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${EXTERIA_IOS_BUILD:-build/ios}"
[[ "${BUILD}" = /* ]] || BUILD="${ROOT}/${BUILD}"
APP="${BUILD}/Exteria.app"
VERSION="$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1], "rb"))["CFBundleShortVersionString"])' "${ROOT}/packaging/Info.plist")"
OUT="${BUILD}/Exteria-v${VERSION}.ipa"
STAGE="${BUILD}/ipa-stage"

[[ -x "${APP}/Exteria" ]] || { echo "missing ${APP}/Exteria, run make app" >&2; exit 1; }
rm -rf "${STAGE}" "${OUT}" "${OUT}.sha256"
mkdir -p "${STAGE}/Payload"
cp -R "${APP}" "${STAGE}/Payload/"
find "${STAGE}/Payload" -type d -exec chmod 755 {} +
find "${STAGE}/Payload" -type f -exec chmod 644 {} +
chmod 755 "${STAGE}/Payload/Exteria.app/Exteria"
(cd "${STAGE}" && zip -qrX "${OUT}" Payload)
rm -rf "${STAGE}"
unzip -tq "${OUT}"
# the app checks the download against this file, which a release carries next to the ipa
if command -v sha256sum >/dev/null; then
    (cd "${BUILD}" && sha256sum "$(basename "${OUT}")" > "$(basename "${OUT}").sha256")
else
    (cd "${BUILD}" && shasum -a 256 "$(basename "${OUT}")" > "$(basename "${OUT}").sha256")
fi
echo "built ${OUT} and ${OUT}.sha256"
