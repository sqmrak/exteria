#!/usr/bin/env bash
# writes <ipa>.sha256 next to the ipa, the file the in-app update checks the download against
set -euo pipefail

ipa="${1:?usage: ipa_sha256.sh <ipa>}"
[[ -f "${ipa}" ]] || { echo "missing ${ipa}" >&2; exit 1; }
dir="$(dirname "${ipa}")"
name="$(basename "${ipa}")"
if command -v sha256sum >/dev/null; then
    (cd "${dir}" && sha256sum "${name}" > "${name}.sha256")
else
    (cd "${dir}" && shasum -a 256 "${name}" > "${name}.sha256")
fi
