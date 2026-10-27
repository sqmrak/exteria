#!/usr/bin/env bash
# wrap the built ipa into a deb for a package repository; the payload sits under /var/jb and the postinst puts it where the jailbreak expects it
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${EXTERIA_IOS_BUILD:-build/ios}"
[[ "${BUILD}" = /* ]] || BUILD="${ROOT}/${BUILD}"
VERSION="$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1], "rb"))["CFBundleShortVersionString"])' "${ROOT}/packaging/Info.plist")"
IPA="${BUILD}/Exteria-v${VERSION}.ipa"
OUT="${BUILD}/exteria_${VERSION}.deb"
STAGE="${BUILD}/deb-stage"

[[ -f "${IPA}" ]] || { echo "missing ${IPA}, run make ipa" >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo "dpkg-deb is required" >&2; exit 1; }
rm -rf "${STAGE}" "${OUT}"
mkdir -p "${STAGE}/var/jb/Applications" "${STAGE}/DEBIAN" "${STAGE}/unzip"
unzip -q "${IPA}" -d "${STAGE}/unzip"
mv "${STAGE}/unzip/Payload/Exteria.app" "${STAGE}/var/jb/Applications/"
rm -rf "${STAGE}/unzip"
find "${STAGE}/var" -type d -exec chmod 755 {} +
find "${STAGE}/var" -type f -exec chmod 644 {} +
chmod 755 "${STAGE}/var/jb/Applications/Exteria.app/Exteria"
install -m 755 "${ROOT}/packaging/deb/postinst" "${ROOT}/packaging/deb/postrm" "${STAGE}/DEBIAN/"
SIZE="$(du -sk "${STAGE}/var" | cut -f1)"
cat > "${STAGE}/DEBIAN/control" <<CONTROL
Package: com.sqmrak.exteria
Name: Exteria
Version: ${VERSION}
Architecture: all
Description: native telegram client for jailbroken iOS 5+ (armv7 + arm64)
Maintainer: sqmrak
Author: sqmrak
Section: Messaging
Priority: optional
License: GPL-3.0-only
Depends: firmware (>= 5.0)
Installed-Size: ${SIZE}
CONTROL
# gzip members, which dpkg of old jailbreaks can read
dpkg-deb --root-owner-group -Zgzip -b "${STAGE}" "${OUT}"
rm -rf "${STAGE}"
dpkg-deb -I "${OUT}" | sed -n 1,20p
echo "built ${OUT}"
