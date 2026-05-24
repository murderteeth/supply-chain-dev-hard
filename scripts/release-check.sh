#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/harden-dev-env.sh"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$script" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$script" | awk '{print $1}'
  else
    printf 'ERROR: need sha256sum or shasum\n' >&2
    exit 1
  fi
}

commit_ref() {
  if git -C "$repo_root" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$repo_root" rev-parse HEAD
  else
    printf 'COMMIT_SHA'
  fi
}

bash -n "$script"
bash -n "$repo_root/tests/supply-chain-hardening/run-scenarios.sh"

"$repo_root/tests/supply-chain-hardening/run-scenarios-on-linux.sh"
"$repo_root/tests/supply-chain-hardening/run-scenarios-on-macos.sh"

sha256="$(hash_file)"
ref="$(commit_ref)"
remote_url="${BOOTSTRAP_RAW_URL:-https://raw.githubusercontent.com/YOUR_ORG/supply-chain-dev-hard/$ref/harden-dev-env.sh}"

cat <<EOF
SHA256: $sha256

Pinned bootstrap:

(
  set -euo pipefail

  url='$remote_url'
  sha256='$sha256'
  tmp="\$(mktemp)"
  trap 'rm -f "\$tmp"' EXIT
  curl -fsSL "\$url" -o "\$tmp"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "\$sha256" "\$tmp" | sha256sum -c -
  elif command -v shasum >/dev/null 2>&1; then
    actual="\$(shasum -a 256 "\$tmp" | awk '{print \$1}')"
    [ "\$actual" = "\$sha256" ]
  else
    printf 'ERROR: need sha256sum or shasum\n' >&2
    exit 1
  fi
  bash "\$tmp"
)

No tag, push, publish, or trust update was performed.
Review the script diff and the snippet above before taking release action.
EOF
