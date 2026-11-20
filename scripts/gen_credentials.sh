#!/usr/bin/env bash
# writes the telegram api id and hash into a header under build/, the values never enter the repository
set -euo pipefail

out="${1:?usage: gen_credentials.sh <header>, with EXTERIA_API_ID and EXTERIA_API_HASH set}"
id="${EXTERIA_API_ID:-}"
hash="${EXTERIA_API_HASH:-}"
[[ "${id}" =~ ^[0-9]+$ ]] || { echo "set EXTERIA_API_ID to the numeric telegram api id" >&2; exit 1; }
[[ "${hash}" =~ ^[0-9a-f]{32}$ ]] || { echo "set EXTERIA_API_HASH to the 32 character telegram api hash" >&2; exit 1; }
mkdir -p "$(dirname "${out}")"
printf '#define EXTERIA_API_ID %s\n#define EXTERIA_API_HASH "%s"\n' "${id}" "${hash}" > "${out}"
