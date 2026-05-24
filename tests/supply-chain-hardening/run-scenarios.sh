#!/usr/bin/env bash
set -euo pipefail

if [ -z "${REPO_DIR:-}" ]; then
  if [ -f ./harden-dev-env.sh ]; then
    REPO_DIR="$(pwd)"
  else
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
fi
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SCRIPT_UNDER_TEST="${SCRIPT_UNDER_TEST:-$REPO_DIR/harden-dev-env.sh}"
SCRIPT_BASH="${SCRIPT_BASH:-bash}"

check_script() {
  if ! grep -q '^confirm_intent()' "$SCRIPT_UNDER_TEST"; then
    printf 'failed to find hardening script at %s\n' "$SCRIPT_UNDER_TEST" >&2
    exit 1
  fi

  "$SCRIPT_BASH" -n "$SCRIPT_UNDER_TEST"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

assert_no_file() {
  [ ! -e "$1" ] || fail "expected missing path: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq "$needle" "$file" || fail "expected '$needle' in $file"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq "$needle" "$file" || fail "did not expect '$needle' in $file"
}

assert_line_count() {
  local file="$1" needle="$2" want="$3" got
  got="$(grep -F "$needle" "$file" | wc -l | tr -d ' ')"
  [ "$got" = "$want" ] || fail "expected $want occurrences of '$needle' in $file, got $got"
}

new_home() {
  local name="$1" home
  home="$WORK_DIR/$name/home"
  mkdir -p "$home"
  printf '%s\n' "$home"
}

install_stubs() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    printf '11.10.0\n'
    ;;
  install)
    if [ "${2:-}" = "-g" ] && [ "${3:-}" = "sfw" ] && [ "${4:-}" = "--ignore-scripts=true" ] && [ "${5:-}" = "--no-audit" ] && [ "${NPM_CONFIG_IGNORE_SCRIPTS:-}" = "true" ] && [ "${NPM_CONFIG_AUDIT:-}" = "false" ]; then
      cat > "$(dirname "$0")/sfw" <<'SFW'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--help" ]; then
  printf 'sfw test stub\nusage: sfw <command> [args]\n'
  exit 0
fi
cmd="$1"
shift
exec "$cmd" "$@"
SFW
      chmod +x "$(dirname "$0")/sfw"
      printf 'installed sfw test stub\n'
      exit 0
    fi
    printf 'unexpected npm args: %s\n' "$*" >&2
    exit 2
    ;;
  config)
    if [ "${2:-}" = "get" ]; then
      key="${3:-}"
      awk -F= -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value }' "$HOME/.npmrc" 2>/dev/null
      exit 0
    fi
    printf 'unexpected npm config args: %s\n' "$*" >&2
    exit 2
    ;;
  *)
    printf 'unexpected npm args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF

  cat > "$bin_dir/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'v22.0.0\n'
EOF

  cat > "$bin_dir/pnpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
config_file="${XDG_CONFIG_HOME:-$HOME/.config}/pnpm/config.yaml"
case "${1:-}" in
  --version)
    printf '11.1.3\n'
    ;;
  config)
    if [ "${2:-}" = "get" ]; then
      key="${3:-}"
      awk -F': ' -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value }' "$config_file" 2>/dev/null
      exit 0
    fi
    printf 'unexpected pnpm config args: %s\n' "$*" >&2
    exit 2
    ;;
  *)
    printf 'unexpected pnpm args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF

  cat > "$bin_dir/yarn" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    printf '4.15.0\n'
    ;;
  config)
    if [ "${2:-}" = "get" ]; then
      case "${3:-}" in
        npmMinimalAgeGate) printf '%s\n' "${YARN_NPM_MINIMAL_AGE_GATE:-}" ;;
        enableScripts) printf '%s\n' "${YARN_ENABLE_SCRIPTS:-}" ;;
        *) printf '\n' ;;
      esac
      exit 0
    fi
    printf 'unexpected yarn config args: %s\n' "$*" >&2
    exit 2
    ;;
  *)
    printf 'unexpected yarn args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF

  cat > "$bin_dir/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    printf '1.3.14\n'
    ;;
  *)
    printf 'unexpected bun args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF

  for cmd in npx bunx uv pip pip3 cargo; do
    cat > "$bin_dir/$cmd" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\${1:-}" in
  --version) printf '$cmd test-stub\n' ;;
  *) printf 'unexpected $cmd args: %s\n' "\$*" >&2; exit 2 ;;
esac
EOF
  done

  chmod +x "$bin_dir"/*
}

install_old_version_stubs() {
  local bin_dir="$1"
  install_stubs "$bin_dir"

  for spec in npm:10.9.2 pnpm:10.0.0 yarn:1.22.22 bun:1.2.0; do
    local cmd="${spec%%:*}" version="${spec#*:}"
    cat > "$bin_dir/$cmd" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\${1:-}" in
  --version) printf '$version\n' ;;
  config)
    if [ "\${2:-}" = "get" ]; then
      printf '\n'
      exit 0
    fi
    printf 'unexpected $cmd config args: %s\n' "\$*" >&2
    exit 2
    ;;
  *)
    printf 'unexpected $cmd args: %s\n' "\$*" >&2
    exit 2
    ;;
esac
EOF
  done

  chmod +x "$bin_dir"/npm "$bin_dir"/pnpm "$bin_dir"/yarn "$bin_dir"/bun
}

install_corepack_shim_stubs() {
  local bin_dir="$1" corepack_dir="$bin_dir/corepack-shims"
  install_stubs "$bin_dir"
  mkdir -p "$corepack_dir"

  for cmd in pnpm yarn; do
    cat > "$corepack_dir/$cmd-corepack" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '$cmd corepack shim is not prepared\n' >&2
exit 1
EOF
    chmod +x "$corepack_dir/$cmd-corepack"
    rm -f "$bin_dir/$cmd"
    ln -s "$corepack_dir/$cmd-corepack" "$bin_dir/$cmd"
  done
}

run_script() {
  local home="$1" bin_dir="$2"
  shift 2
  env -i \
    HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    PATH="$bin_dir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$@" \
    "$SCRIPT_BASH" "$SCRIPT_UNDER_TEST"
}

run_script_without_xdg() {
  local home="$1" bin_dir="$2"
  shift 2
  env -i \
    HOME="$home" \
    PATH="$bin_dir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$@" \
    "$SCRIPT_BASH" "$SCRIPT_UNDER_TEST"
}

scenario_baseline() {
  local home bin_dir log
  home="$(new_home baseline)"
  bin_dir="$WORK_DIR/baseline/bin"
  log="$WORK_DIR/baseline.log"
  install_stubs "$bin_dir"

  run_script "$home" "$bin_dir" HARDEN_ASSUME_YES=1 > "$log" 2>&1

  assert_contains "$home/.npmrc" "save-exact=true"
  assert_contains "$home/.npmrc" "min-release-age=7"
  assert_contains "$home/.npmrc" "audit=true"
  assert_contains "$home/.npmrc" "fund=false"
  assert_contains "$home/.npmrc" "ignore-scripts=true"

  assert_contains "$home/.config/pnpm/config.yaml" "savePrefix: \"\""
  assert_contains "$home/.config/pnpm/config.yaml" "minimumReleaseAge: 10080"
  assert_contains "$home/.config/pnpm/config.yaml" "minimumReleaseAgeStrict: true"
  assert_contains "$home/.config/pnpm/config.yaml" "minimumReleaseAgeIgnoreMissingTime: false"
  assert_contains "$home/.config/pnpm/config.yaml" "blockExoticSubdeps: true"
  assert_contains "$home/.config/pnpm/config.yaml" "trustPolicy: no-downgrade"
  assert_contains "$home/.config/pnpm/config.yaml" "ignoreScripts: true"

  assert_contains "$home/.bashrc" "# >>> Socket Firewall aliases >>>"
  assert_contains "$home/.bashrc" 'alias npm="sfw npm"'
  assert_contains "$home/.bashrc" 'alias pip="sfw pip"'
  assert_contains "$home/.bashrc" 'alias cargo="sfw cargo"'
  assert_contains "$home/.bashrc" "# >>> Yarn hardening defaults >>>"
  assert_contains "$home/.bashrc" 'export YARN_NPM_MINIMAL_AGE_GATE="7d"'
  assert_contains "$home/.bashrc" 'export YARN_ENABLE_SCRIPTS="false"'

  assert_contains "$home/.config/.bunfig.toml" "[install]"
  assert_contains "$home/.config/.bunfig.toml" "minimumReleaseAge = 604800"
  assert_contains "$home/.config/.bunfig.toml" "exact = true"
  assert_contains "$home/.config/.bunfig.toml" "ignoreScripts = true"
  assert_contains "$log" "Socket Firewall wrapper verification"

  pass "baseline strict defaults"
}

scenario_prompt_abort() {
  local home bin_dir log
  home="$(new_home prompt-abort)"
  bin_dir="$WORK_DIR/prompt-abort/bin"
  log="$WORK_DIR/prompt-abort.log"
  install_stubs "$bin_dir"

  if printf 'n\n' | run_script "$home" "$bin_dir" > "$log" 2>&1; then
    fail "prompt abort scenario unexpectedly succeeded"
  fi

  assert_contains "$log" "Continue? [y/N]"
  assert_contains "$log" "ERROR: aborted"
  assert_no_file "$home/.npmrc"
  assert_no_file "$home/.bashrc"

  pass "confirmation abort prevents writes"
}

scenario_prompt_yes_relaxed_custom_age() {
  local home bin_dir log
  home="$(new_home relaxed)"
  bin_dir="$WORK_DIR/relaxed/bin"
  log="$WORK_DIR/relaxed.log"
  install_stubs "$bin_dir"

  printf 'yes\nn\n' | run_script "$home" "$bin_dir" AGE_DAYS=3 STRICT_INSTALL_SCRIPTS=0 > "$log" 2>&1

  assert_contains "$home/.npmrc" "min-release-age=3"
  assert_contains "$home/.npmrc" "ignore-scripts=false"
  assert_contains "$home/.config/pnpm/config.yaml" "minimumReleaseAge: 4320"
  assert_contains "$home/.config/pnpm/config.yaml" "ignoreScripts: false"
  assert_contains "$home/.bashrc" 'export YARN_NPM_MINIMAL_AGE_GATE="3d"'
  assert_contains "$home/.bashrc" 'export YARN_ENABLE_SCRIPTS="true"'
  assert_contains "$home/.config/.bunfig.toml" "minimumReleaseAge = 259200"
  assert_contains "$home/.config/.bunfig.toml" "ignoreScripts = false"

  pass "interactive yes with custom age and relaxed scripts"
}

scenario_socket_firewall_decline() {
  local home bin_dir log
  home="$(new_home socket-decline)"
  bin_dir="$WORK_DIR/socket-decline/bin"
  log="$WORK_DIR/socket-decline.log"
  install_stubs "$bin_dir"

  printf 'yes\nn\n' | run_script "$home" "$bin_dir" > "$log" 2>&1

  assert_contains "$log" "Install Socket Firewall wrapper and shell aliases? [y/N]"
  assert_contains "$log" "skipping Socket Firewall install and aliases by request"
  assert_contains "$log" "skipping Socket Firewall install"
  assert_contains "$log" "skipping Socket Firewall aliases"
  assert_no_file "$bin_dir/sfw"
  assert_not_contains "$home/.bashrc" "# >>> Socket Firewall aliases >>>"
  assert_contains "$home/.bashrc" "# >>> Yarn hardening defaults >>>"
  assert_contains "$home/.npmrc" "ignore-scripts=true"
  assert_not_contains "$log" "Socket Firewall wrapper verification"

  pass "Socket Firewall install can be declined"
}

scenario_socket_firewall_env_skip() {
  local home bin_dir log
  home="$(new_home socket-env-skip)"
  bin_dir="$WORK_DIR/socket-env-skip/bin"
  log="$WORK_DIR/socket-env-skip.log"
  install_stubs "$bin_dir"

  run_script "$home" "$bin_dir" HARDEN_ASSUME_YES=1 HARDEN_INSTALL_SOCKET_FIREWALL=0 > "$log" 2>&1

  assert_contains "$log" "skipping Socket Firewall install and aliases by request"
  assert_contains "$log" "skipping Socket Firewall install"
  assert_contains "$log" "skipping Socket Firewall aliases"
  assert_no_file "$bin_dir/sfw"
  assert_not_contains "$home/.bashrc" "# >>> Socket Firewall aliases >>>"
  assert_contains "$home/.bashrc" "# >>> Yarn hardening defaults >>>"
  assert_contains "$home/.npmrc" "ignore-scripts=true"
  assert_not_contains "$log" "Socket Firewall wrapper verification"

  pass "Socket Firewall can be skipped in noninteractive runs"
}

scenario_existing_config_idempotent() {
  local home bin_dir log
  home="$(new_home existing)"
  bin_dir="$WORK_DIR/existing/bin"
  log="$WORK_DIR/existing.log"
  install_stubs "$bin_dir"

  mkdir -p "$home/.config/pnpm"
  printf 'registry=https://registry.example.invalid/\nignore-scripts=false\n' > "$home/.npmrc"
  printf 'storeDir: /tmp/pnpm-store\nignoreScripts: false\n' > "$home/.config/pnpm/config.yaml"
  printf 'existing shell line\n' > "$home/.bashrc"
  printf '[install]\ncache = "/tmp/bun-cache"\nignoreScripts = false\n' > "$home/.config/.bunfig.toml"

  run_script "$home" "$bin_dir" HARDEN_ASSUME_YES=1 > "$log" 2>&1
  run_script "$home" "$bin_dir" HARDEN_ASSUME_YES=1 >> "$log" 2>&1

  assert_contains "$home/.npmrc.pre-supply-chain-harden.bak" "registry=https://registry.example.invalid/"
  assert_contains "$home/.config/pnpm/config.yaml.pre-supply-chain-harden.bak" "storeDir: /tmp/pnpm-store"
  assert_contains "$home/.bashrc.pre-supply-chain-harden.bak" "existing shell line"
  assert_contains "$home/.config/.bunfig.toml.pre-supply-chain-harden.bak" 'cache = "/tmp/bun-cache"'

  assert_contains "$home/.npmrc" "registry=https://registry.example.invalid/"
  assert_contains "$home/.config/pnpm/config.yaml" "storeDir: /tmp/pnpm-store"
  assert_contains "$home/.bashrc" "existing shell line"
  assert_contains "$home/.config/.bunfig.toml" 'cache = "/tmp/bun-cache"'

  assert_line_count "$home/.bashrc" "# >>> Socket Firewall aliases >>>" 1
  assert_line_count "$home/.bashrc" "# >>> Yarn hardening defaults >>>" 1
  assert_line_count "$home/.npmrc" "ignore-scripts=true" 1
  assert_not_contains "$home/.npmrc" "ignore-scripts=false"

  pass "existing configs are backed up and reruns are idempotent"
}

scenario_missing_tools() {
  local home bin_dir log
  home="$(new_home missing-tools)"
  bin_dir="$WORK_DIR/missing-tools/bin"
  log="$WORK_DIR/missing-tools.log"
  mkdir -p "$bin_dir"

  run_script "$home" "$bin_dir" HARDEN_ASSUME_YES=1 > "$log" 2>&1

  assert_contains "$home/.npmrc" "min-release-age=7"
  assert_contains "$home/.config/pnpm/config.yaml" "minimumReleaseAge: 10080"
  assert_contains "$home/.bashrc" "# >>> Yarn hardening defaults >>>"
  assert_not_contains "$home/.bashrc" "# >>> Socket Firewall aliases >>>"
  assert_contains "$home/.config/.bunfig.toml" "minimumReleaseAge = 604800"
  assert_contains "$log" "skipping Socket Firewall install because npm/node is not available"

  pass "missing package managers still get config defaults"
}

scenario_no_xdg_config_home() {
  local home bin_dir log
  home="$(new_home no-xdg)"
  bin_dir="$WORK_DIR/no-xdg/bin"
  log="$WORK_DIR/no-xdg.log"
  install_stubs "$bin_dir"

  run_script_without_xdg "$home" "$bin_dir" HARDEN_ASSUME_YES=1 > "$log" 2>&1

  assert_contains "$home/.config/pnpm/config.yaml" "minimumReleaseAge: 10080"
  assert_contains "$home/.bunfig.toml" "minimumReleaseAge = 604800"
  assert_contains "$home/.bunfig.toml" "exact = true"
  assert_contains "$home/.bunfig.toml" "ignoreScripts = true"
  assert_no_file "$home/.config/.bunfig.toml"

  pass "home config paths are used when XDG_CONFIG_HOME is unset"
}

scenario_zshrc_blocks() {
  local home bin_dir log
  home="$(new_home zshrc)"
  bin_dir="$WORK_DIR/zshrc/bin"
  log="$WORK_DIR/zshrc.log"
  install_stubs "$bin_dir"
  printf 'existing zsh line\n' > "$home/.zshrc"

  run_script "$home" "$bin_dir" HARDEN_ASSUME_YES=1 > "$log" 2>&1

  assert_contains "$home/.zshrc" "existing zsh line"
  assert_contains "$home/.zshrc" "# >>> Socket Firewall aliases >>>"
  assert_contains "$home/.zshrc" 'alias npm="sfw npm"'
  assert_contains "$home/.zshrc" "# >>> Yarn hardening defaults >>>"
  assert_contains "$home/.zshrc" 'export YARN_NPM_MINIMAL_AGE_GATE="7d"'
  assert_contains "$home/.zshrc.pre-supply-chain-harden.bak" "existing zsh line"

  pass "existing zshrc receives managed blocks"
}

scenario_broken_managed_block_fails() {
  local home bin_dir log
  home="$(new_home broken-block)"
  bin_dir="$WORK_DIR/broken-block/bin"
  log="$WORK_DIR/broken-block.log"
  install_stubs "$bin_dir"
  printf '# >>> Yarn hardening defaults >>>\n' > "$home/.bashrc"

  if run_script "$home" "$bin_dir" HARDEN_ASSUME_YES=1 > "$log" 2>&1; then
    fail "broken managed block scenario unexpectedly succeeded"
  fi

  assert_contains "$log" "contains '# >>> Yarn hardening defaults >>>' without '# <<< Yarn hardening defaults <<<'"
  assert_contains "$home/.bashrc" "# >>> Yarn hardening defaults >>>"
  assert_not_contains "$home/.bashrc" "# <<< Yarn hardening defaults <<<"

  pass "broken managed shell block fails clearly"
}

scenario_corepack_shims_unprepared() {
  local home bin_dir log
  home="$(new_home corepack-shims)"
  bin_dir="$WORK_DIR/corepack-shims/bin"
  log="$WORK_DIR/corepack-shims.log"
  install_corepack_shim_stubs "$bin_dir"

  run_script "$home" "$bin_dir" HARDEN_ASSUME_YES=1 > "$log" 2>&1

  assert_contains "$log" "skipping pnpm preflight because the Corepack shim is not already prepared"
  assert_contains "$log" "skipping Yarn preflight because the Corepack shim is not already prepared"
  assert_contains "$log" "skipping pnpm verification because the Corepack shim is not already prepared"
  assert_contains "$log" "skipping yarn verification because the Corepack shim is not already prepared"
  assert_contains "$log" "skipping Socket Firewall wrapper check for pnpm because the Corepack shim is not already prepared"
  assert_contains "$log" "skipping Socket Firewall wrapper check for yarn because the Corepack shim is not already prepared"
  assert_contains "$home/.config/pnpm/config.yaml" "minimumReleaseAge: 10080"
  assert_contains "$home/.bashrc" "# >>> Yarn hardening defaults >>>"

  pass "unprepared Corepack pnpm/Yarn shims are skipped without provisioning"
}

scenario_unsupported_versions_warn_and_write() {
  local home bin_dir log
  home="$(new_home unsupported-versions)"
  bin_dir="$WORK_DIR/unsupported-versions/bin"
  log="$WORK_DIR/unsupported-versions.log"
  install_old_version_stubs "$bin_dir"

  run_script "$home" "$bin_dir" HARDEN_ASSUME_YES=1 > "$log" 2>&1

  assert_contains "$log" "WARNING: npm 10.9.2 is not covered by this baseline"
  assert_contains "$log" "WARNING: pnpm 10.0.0 is not covered by this baseline"
  assert_contains "$log" "WARNING: Yarn 1.22.22 is not covered by this baseline"
  assert_contains "$log" "WARNING: Bun 1.2.0 is too old for the full baseline"
  assert_contains "$home/.npmrc" "min-release-age=7"
  assert_contains "$home/.config/pnpm/config.yaml" "minimumReleaseAge: 10080"
  assert_contains "$home/.bashrc" "# >>> Yarn hardening defaults >>>"
  assert_contains "$home/.config/.bunfig.toml" "minimumReleaseAge = 604800"

  pass "unsupported package-manager versions warn but still get defaults"
}

main() {
  check_script

  local scenarios=(
    scenario_baseline
    scenario_prompt_abort
    scenario_prompt_yes_relaxed_custom_age
    scenario_socket_firewall_decline
    scenario_socket_firewall_env_skip
    scenario_existing_config_idempotent
    scenario_missing_tools
    scenario_no_xdg_config_home
    scenario_zshrc_blocks
    scenario_broken_managed_block_fails
    scenario_corepack_shims_unprepared
    scenario_unsupported_versions_warn_and_write
  )

  for scenario in "${scenarios[@]}"; do
    "$scenario"
  done
}

main "$@"
