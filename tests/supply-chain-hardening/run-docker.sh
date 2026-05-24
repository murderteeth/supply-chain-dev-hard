#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
image_name="${IMAGE_NAME:-supply-chain-dev-hardening-test}"

docker build -t "$image_name" "$repo_root/tests/supply-chain-hardening"
docker run --rm -v "$repo_root:/repo:ro" "$image_name" "$@"
