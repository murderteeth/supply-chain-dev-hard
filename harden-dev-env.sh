#!/usr/bin/env bash
set -euo pipefail

# Default to a 7-day release-age speed bump. Different package managers use
# different units, so derive the equivalent minute/second values once.
AGE_DAYS="${AGE_DAYS:-7}"
AGE_MINUTES="$((AGE_DAYS * 24 * 60))"
AGE_SECONDS="$((AGE_DAYS * 24 * 60 * 60))"

# Lifecycle scripts are a major npm supply-chain execution path. Keep them off
# globally by default; set STRICT_INSTALL_SCRIPTS=0 when a project needs them.
STRICT_INSTALL_SCRIPTS="${STRICT_INSTALL_SCRIPTS:-1}"
SOCKET_FIREWALL_ENABLED=0

# This baseline intentionally supports only the latest stable major versions as
# of this gist revision. Update these gates when bumping the gist.
SUPPORTED_NPM_MAJOR=11
SUPPORTED_PNPM_MAJOR=11
SUPPORTED_YARN_MAJOR=4
SUPPORTED_BUN_MAJOR=1

MIN_NPM_VERSION=11.10.0
MIN_PNPM_VERSION=11.1.3
MIN_YARN_VERSION=4.15.0
MIN_BUN_VERSION=1.3.0

log() { printf '[harden] %s\n' "$*"; }
warn() { printf '[harden] WARNING: %s\n' "$*" >&2; }
fail() {
  printf '[harden] ERROR: %s\n' "$*" >&2
  exit 1
}

confirm_intent() {
  local answer

  if [ "${HARDEN_ASSUME_YES:-0}" = "1" ]; then
    return
  fi

  cat <<'EOF'
[harden] This script is for individual developer machines that want user-level
[harden] package-manager hardening defaults.
[harden]
[harden] It will update user config for npm, pnpm, Yarn shell defaults, and Bun.
[harden] It can optionally install the current Socket Firewall wrapper globally
[harden] when npm/node are available, then add Socket Firewall shell aliases for
[harden] JavaScript, Python, and Rust package-manager entrypoints.
[harden]
[harden] These are defaults, not mandatory controls; project config, environment
[harden] variables, and CLI flags may override them.
[harden]
[harden] This is not meant as unattended CI or centrally enforced fleet policy.
[harden] Existing config files get one-time *.pre-supply-chain-harden.bak backups.
EOF

  printf '[harden] Continue? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) fail "aborted" ;;
  esac
}

confirm_socket_firewall() {
  local answer setting
  setting="${HARDEN_INSTALL_SOCKET_FIREWALL:-}"

  case "$setting" in
    1|true|TRUE|yes|YES)
      SOCKET_FIREWALL_ENABLED=1
      return
      ;;
    0|false|FALSE|no|NO)
      SOCKET_FIREWALL_ENABLED=0
      log "skipping Socket Firewall install and aliases by request"
      return
      ;;
    "")
      ;;
    *)
      fail "HARDEN_INSTALL_SOCKET_FIREWALL must be 1 or 0"
      ;;
  esac

  if [ "${HARDEN_ASSUME_YES:-0}" = "1" ]; then
    SOCKET_FIREWALL_ENABLED=1
    return
  fi

  printf '[harden] Install Socket Firewall wrapper and shell aliases? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      SOCKET_FIREWALL_ENABLED=1
      ;;
    *)
      SOCKET_FIREWALL_ENABLED=0
      log "skipping Socket Firewall install and aliases by request"
      ;;
  esac
}

version_ge() {
  local got="${1#v}" want="${2#v}"
  local gmaj gmin gpatch wmaj wmin wpatch _
  got="${got%%[-+]*}"
  want="${want%%[-+]*}"
  IFS=. read -r gmaj gmin gpatch _ <<< "$got"
  IFS=. read -r wmaj wmin wpatch _ <<< "$want"
  gmaj="${gmaj:-0}"; gmin="${gmin:-0}"; gpatch="${gpatch:-0}"
  wmaj="${wmaj:-0}"; wmin="${wmin:-0}"; wpatch="${wpatch:-0}"

  case "$gmaj$gmin$gpatch$wmaj$wmin$wpatch" in
    *[!0-9]*) return 1 ;;
  esac

  ((10#$gmaj > 10#$wmaj)) && return 0
  ((10#$gmaj < 10#$wmaj)) && return 1
  ((10#$gmin > 10#$wmin)) && return 0
  ((10#$gmin < 10#$wmin)) && return 1
  ((10#$gpatch >= 10#$wpatch))
}

version_major() {
  local version="${1#v}"
  printf '%s\n' "${version%%.*}"
}

check_supported_version() {
  local name="$1" version="$2" supported_major="$3" min_version="$4" upgrade_hint="$5" major
  major="$(version_major "$version")"
  if [ "$major" != "$supported_major" ]; then
    warn "$name $version is not covered by this baseline. $upgrade_hint"
    return 1
  fi
  if ! version_ge "$version" "$min_version"; then
    warn "$name $version is too old for the full baseline. $upgrade_hint"
    return 1
  fi
}

is_corepack_shim() {
  local cmd="$1" path target
  path="$(command -v "$cmd" 2>/dev/null || true)"
  [ -n "$path" ] || return 1
  target="$(readlink "$path" 2>/dev/null || true)"
  case "$path $target" in
    *corepack*) return 0 ;;
    *) return 1 ;;
  esac
}

pm_version() {
  local cmd="$1" out
  # COREPACK_ENABLE_NETWORK=0 prevents Corepack shims from provisioning a tool.
  # If the exact package-manager version is not already prepared, this fails.
  out="$(COREPACK_ENABLE_AUTO_PIN=0 COREPACK_ENABLE_DOWNLOAD_PROMPT=0 COREPACK_ENABLE_NETWORK=0 "$cmd" --version 2>/dev/null)" || return 1
  printf '%s\n' "$out" | head -n1
}

preflight_package_managers() {
  local version

  if command -v npm >/dev/null 2>&1; then
    if version="$(pm_version npm)"; then
      check_supported_version "npm" "$version" "$SUPPORTED_NPM_MAJOR" "$MIN_NPM_VERSION" "Install npm $SUPPORTED_NPM_MAJOR.x >= $MIN_NPM_VERSION for min-release-age support." || true
    else
      warn "npm is installed but cannot be executed; npm policy will be written but not verified"
    fi
  fi

  if command -v pnpm >/dev/null 2>&1; then
    if ! version="$(pm_version pnpm)"; then
      if is_corepack_shim pnpm; then
        log "skipping pnpm preflight because the Corepack shim is not already prepared"
      else
        warn "pnpm is installed but cannot be executed; pnpm policy will be written but not verified"
      fi
    else
      check_supported_version "pnpm" "$version" "$SUPPORTED_PNPM_MAJOR" "$MIN_PNPM_VERSION" "Install pnpm $SUPPORTED_PNPM_MAJOR.x >= $MIN_PNPM_VERSION for the full pnpm policy." || true
    fi
  fi

  if command -v yarn >/dev/null 2>&1; then
    if ! version="$(pm_version yarn)"; then
      if is_corepack_shim yarn; then
        log "skipping Yarn preflight because the Corepack shim is not already prepared"
      else
        warn "Yarn is installed but cannot be executed; Yarn policy will be written but not verified"
      fi
    else
      check_supported_version "Yarn" "$version" "$SUPPORTED_YARN_MAJOR" "$MIN_YARN_VERSION" "Install Yarn $SUPPORTED_YARN_MAJOR.x >= $MIN_YARN_VERSION for npmMinimalAgeGate support." || true
    fi
  fi

  if command -v bun >/dev/null 2>&1; then
    if version="$(pm_version bun)"; then
      check_supported_version "Bun" "$version" "$SUPPORTED_BUN_MAJOR" "$MIN_BUN_VERSION" "Install Bun $SUPPORTED_BUN_MAJOR.x >= $MIN_BUN_VERSION for minimumReleaseAge support." || true
    else
      warn "Bun is installed but cannot be executed; Bun policy will be written but not verified"
    fi
  fi
}

run_pm_if_ready() {
  local cmd="$1"
  shift

  if ! command -v "$cmd" >/dev/null 2>&1; then
    return
  fi

  if is_corepack_shim "$cmd" && ! COREPACK_ENABLE_AUTO_PIN=0 COREPACK_ENABLE_DOWNLOAD_PROMPT=0 COREPACK_ENABLE_NETWORK=0 "$cmd" --version >/dev/null 2>&1; then
    log "skipping $cmd verification because the Corepack shim is not already prepared"
    return
  fi

  COREPACK_ENABLE_AUTO_PIN=0 COREPACK_ENABLE_DOWNLOAD_PROMPT=0 COREPACK_ENABLE_NETWORK=0 "$cmd" "$@" || true
}

confirm_intent
confirm_socket_firewall
preflight_package_managers

CREATED_CONFIG_FILES="
"

remember_created_file() {
  CREATED_CONFIG_FILES="${CREATED_CONFIG_FILES}$1
"
}

created_this_run() {
  case "$CREATED_CONFIG_FILES" in
    *"
$1
"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Preserve the first pre-hardening copy of each config file. The script may be
# rerun safely without overwriting that original backup.
backup_once() {
  local file="$1"
  if created_this_run "$file"; then
    return
  fi
  if [ -f "$file" ] && [ ! -f "$file.pre-supply-chain-harden.bak" ]; then
    cp -p "$file" "$file.pre-supply-chain-harden.bak"
  fi
}

prepare_config_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ]; then
    backup_once "$file"
  else
    touch "$file"
    remember_created_file "$file"
  fi
}

# Upsert key=value settings, used by npm-style rc files.
upsert_eq() {
  local file="$1" key="$2" value="$3" tmp
  prepare_config_file "$file"
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done=0 }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      print key "=" value
      done=1
      next
    }
    { print }
    END { if (!done) print key "=" value }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Upsert simple top-level YAML scalars, used by pnpm config.
upsert_yaml() {
  local file="$1" key="$2" value="$3" tmp
  prepare_config_file "$file"
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done=0 }
    $0 ~ "^" key ":" {
      print key ": " value
      done=1
      next
    }
    { print }
    END { if (!done) print key ": " value }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Replace a marked shell-rc block idempotently. This lets the script add aliases
# once, then update them later without duplicating lines on every rerun.
write_managed_block() {
  local file="$1" name="$2" block="$3" begin_marker end_marker tmp
  prepare_config_file "$file"
  begin_marker="# >>> $name >>>"
  end_marker="# <<< $name <<<"
  if grep -Fxq "$begin_marker" "$file" && ! grep -Fxq "$end_marker" "$file"; then
    fail "$file contains '$begin_marker' without '$end_marker'; inspect or repair it before rerunning"
  fi
  tmp="$(mktemp)"
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"
  {
    cat "$tmp"
    printf '\n# >>> %s >>>\n%s\n# <<< %s <<<\n' "$name" "$block" "$name"
  } > "$file"
  rm -f "$tmp"
}

# Ensure Bun has an [install] section with exact versions, lifecycle-script
# policy, and a release-age gate. Bun reads this from $XDG_CONFIG_HOME/.bunfig.toml
# when XDG_CONFIG_HOME is set, otherwise from $HOME/.bunfig.toml.
upsert_bunfig_install() {
  local file="$1" tmp
  prepare_config_file "$file"
  tmp="$(mktemp)"
  awk -v age="$AGE_SECONDS" -v ignore_scripts="$BUN_IGNORE_SCRIPTS" '
    BEGIN { in_install=0; seen_install=0; inserted=0 }
    /^\[install\][[:space:]]*$/ {
      if (in_install && !inserted) {
        print "minimumReleaseAge = " age
        print "exact = true"
        print "ignoreScripts = " ignore_scripts
        inserted=1
      }
      in_install=1
      seen_install=1
      print
      next
    }
    /^\[/ {
      if (in_install && !inserted) {
        print "minimumReleaseAge = " age
        print "exact = true"
        print "ignoreScripts = " ignore_scripts
        inserted=1
      }
      in_install=0
      print
      next
    }
    in_install && $0 ~ "^[[:space:]]*(minimumReleaseAge|exact|ignoreScripts)[[:space:]]*=" { next }
    { print }
    END {
      if (seen_install && in_install && !inserted) {
        print "minimumReleaseAge = " age
        print "exact = true"
        print "ignoreScripts = " ignore_scripts
      }
      if (!seen_install) {
        print ""
        print "[install]"
        print "minimumReleaseAge = " age
        print "exact = true"
        print "ignoreScripts = " ignore_scripts
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Socket Firewall:
# - install the `sfw` wrapper from npm when npm is already available
# - keep lifecycle scripts disabled during the global install
# - add aliases so ordinary commands like `npm install` become `sfw npm install`
# - use env to bypass existing aliases/functions during npm's global install
#
# This intentionally installs the current `sfw` release rather than pinning a
# version. Treat Socket Firewall itself as part of the user's trusted bootstrap
# path; the install is best-effort and not the root of trust for this baseline.
#
# Socket Firewall Free documents wrapper mode for npm, yarn, pnpm, pip, uv,
# and cargo. This alias set also includes npx, bun, and bunx as JavaScript
# install/execute entrypoints; verify current sfw behavior locally if those
# wrappers are important to your workflow.
if [ "$SOCKET_FIREWALL_ENABLED" = "1" ]; then
  if command -v npm >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
    log "installing Socket Firewall wrapper"
    env NPM_CONFIG_IGNORE_SCRIPTS=true npm install -g sfw --ignore-scripts=true || true
  else
    log "skipping Socket Firewall install because npm/node is not available"
  fi
else
  log "skipping Socket Firewall install"
fi

sfw_aliases='
# Socket Firewall aliases. Use `command npm ...` or the full binary path to bypass.
alias npm="sfw npm"
alias npx="sfw npx"
alias bun="sfw bun"
alias bunx="sfw bunx"
alias pnpm="sfw pnpm"
alias yarn="sfw yarn"
alias uv="sfw uv"
alias pip="sfw pip"
alias pip3="sfw pip3"
alias cargo="sfw cargo"'

if [ "$SOCKET_FIREWALL_ENABLED" = "1" ]; then
  if command -v sfw >/dev/null 2>&1; then
    write_managed_block "$HOME/.bashrc" "Socket Firewall aliases" "$sfw_aliases"
    if [ -f "$HOME/.zshrc" ]; then
      write_managed_block "$HOME/.zshrc" "Socket Firewall aliases" "$sfw_aliases"
    fi
  else
    log "skipping Socket Firewall aliases because sfw is not available"
  fi
else
  log "skipping Socket Firewall aliases"
fi

# npm policy:
# - save exact versions instead of ranges for newly added packages
# - reject packages published inside the speed-bump window
# - keep audit enabled
# - disable install scripts unless explicitly opted out
log "writing npm policy"
upsert_eq "$HOME/.npmrc" "save-exact" "true"
upsert_eq "$HOME/.npmrc" "min-release-age" "$AGE_DAYS"
upsert_eq "$HOME/.npmrc" "audit" "true"
upsert_eq "$HOME/.npmrc" "fund" "false"
if [ "$STRICT_INSTALL_SCRIPTS" = "1" ]; then
  upsert_eq "$HOME/.npmrc" "ignore-scripts" "true"
else
  upsert_eq "$HOME/.npmrc" "ignore-scripts" "false"
fi

# pnpm policy:
# - savePrefix "" saves newly added packages as exact versions
# - release-age is minutes, so 7 days is 10080
# - strict/missing-time settings avoid silently accepting packages without
#   publish-time metadata
# - blockExoticSubdeps blocks git/url/tarball dependencies in transitive deps
# - trustPolicy no-downgrade protects pnpm's trust metadata from weakening
log "writing pnpm policy"
PNPM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/pnpm"
mkdir -p "$PNPM_CONFIG_HOME"
upsert_yaml "$PNPM_CONFIG_HOME/config.yaml" "savePrefix" '""'
upsert_yaml "$PNPM_CONFIG_HOME/config.yaml" "minimumReleaseAge" "$AGE_MINUTES"
upsert_yaml "$PNPM_CONFIG_HOME/config.yaml" "minimumReleaseAgeStrict" "true"
upsert_yaml "$PNPM_CONFIG_HOME/config.yaml" "minimumReleaseAgeIgnoreMissingTime" "false"
upsert_yaml "$PNPM_CONFIG_HOME/config.yaml" "blockExoticSubdeps" "true"
upsert_yaml "$PNPM_CONFIG_HOME/config.yaml" "trustPolicy" "no-downgrade"
if [ "$STRICT_INSTALL_SCRIPTS" = "1" ]; then
  upsert_yaml "$PNPM_CONFIG_HOME/config.yaml" "ignoreScripts" "true"
else
  upsert_yaml "$PNPM_CONFIG_HOME/config.yaml" "ignoreScripts" "false"
fi

# Yarn policy:
# - Yarn has no true home-global .yarnrc.yml; rc files are discovered by
#   walking parent directories from the current project.
# - Use shell environment defaults so interactive Yarn commands get the
#   baseline regardless of project location.
# - modern Yarn supports npmMinimalAgeGate and hardened lockfile checks
# - enableScripts false blocks dependency lifecycle scripts
# - defaultSemverRangePrefix "" saves newly added packages as exact versions
log "writing Yarn shell environment defaults"
if [ "$STRICT_INSTALL_SCRIPTS" = "1" ]; then
  YARN_ENABLE_SCRIPTS_VALUE="false"
else
  YARN_ENABLE_SCRIPTS_VALUE="true"
fi
export YARN_NPM_MINIMAL_AGE_GATE="${AGE_DAYS}d"
export YARN_ENABLE_SCRIPTS="$YARN_ENABLE_SCRIPTS_VALUE"
export YARN_ENABLE_HARDENED_MODE="true"
export YARN_CHECKSUM_BEHAVIOR="throw"
export YARN_DEFAULT_SEMVER_RANGE_PREFIX=""

yarn_env='
# Yarn hardening defaults. Yarn rc files are project/tree-scoped, so keep
# user-level defaults in the shell environment instead.
export YARN_NPM_MINIMAL_AGE_GATE="'"${AGE_DAYS}d"'"
export YARN_ENABLE_SCRIPTS="'"$YARN_ENABLE_SCRIPTS_VALUE"'"
export YARN_ENABLE_HARDENED_MODE="true"
export YARN_CHECKSUM_BEHAVIOR="throw"
export YARN_DEFAULT_SEMVER_RANGE_PREFIX=""'

write_managed_block "$HOME/.bashrc" "Yarn hardening defaults" "$yarn_env"
if [ -f "$HOME/.zshrc" ]; then
  write_managed_block "$HOME/.zshrc" "Yarn hardening defaults" "$yarn_env"
fi

# Bun policy:
# - release-age is seconds
# - exact avoids caret/tilde ranges for newly added packages
# - ignoreScripts follows STRICT_INSTALL_SCRIPTS
log "writing Bun policy"
if [ "$STRICT_INSTALL_SCRIPTS" = "1" ]; then
  BUN_IGNORE_SCRIPTS="true"
else
  BUN_IGNORE_SCRIPTS="false"
fi
if [ -n "${XDG_CONFIG_HOME:-}" ]; then
  BUNFIG_FILE="$XDG_CONFIG_HOME/.bunfig.toml"
else
  BUNFIG_FILE="$HOME/.bunfig.toml"
fi
upsert_bunfig_install "$BUNFIG_FILE"

# Print what each tool sees after writing config. Failures are non-fatal because
# some systems may not have every package manager installed.
log "verification"
if command -v npm >/dev/null 2>&1; then
  run_pm_if_ready npm --version
  run_pm_if_ready npm config get min-release-age
  run_pm_if_ready npm config get before
  run_pm_if_ready npm config get ignore-scripts
fi

if command -v pnpm >/dev/null 2>&1; then
  run_pm_if_ready pnpm --version
  run_pm_if_ready pnpm config get savePrefix
  run_pm_if_ready pnpm config get minimumReleaseAge
  run_pm_if_ready pnpm config get ignoreScripts
fi

if command -v yarn >/dev/null 2>&1; then
  run_pm_if_ready yarn --version
  run_pm_if_ready yarn config get npmMinimalAgeGate
  run_pm_if_ready yarn config get enableScripts
fi

if command -v bun >/dev/null 2>&1; then
  run_pm_if_ready bun --version
fi

verify_sfw_command() {
  local cmd="$1"
  shift
  if command -v "$cmd" >/dev/null 2>&1; then
    if is_corepack_shim "$cmd" && ! COREPACK_ENABLE_AUTO_PIN=0 COREPACK_ENABLE_DOWNLOAD_PROMPT=0 COREPACK_ENABLE_NETWORK=0 "$cmd" --version >/dev/null 2>&1; then
      log "skipping Socket Firewall wrapper check for $cmd because the Corepack shim is not already prepared"
      return
    fi
    log "verifying Socket Firewall wrapper for $cmd"
    if ! COREPACK_ENABLE_AUTO_PIN=0 COREPACK_ENABLE_DOWNLOAD_PROMPT=0 COREPACK_ENABLE_NETWORK=0 sfw "$cmd" "$@"; then
      log "Socket Firewall wrapper check failed for $cmd"
    fi
  fi
}

if [ "$SOCKET_FIREWALL_ENABLED" = "1" ] && command -v sfw >/dev/null 2>&1; then
  log "Socket Firewall wrapper verification"
  sfw --help | sed -n '1,8p' || true
  verify_sfw_command npm --version
  verify_sfw_command npx --version
  verify_sfw_command bun --version
  verify_sfw_command bunx --version
  verify_sfw_command pnpm --version
  verify_sfw_command yarn --version
  verify_sfw_command uv --version
  verify_sfw_command pip --version
  verify_sfw_command pip3 --version
  verify_sfw_command cargo --version
fi

log "done"
log "set STRICT_INSTALL_SCRIPTS=0 before rerunning to allow lifecycle scripts"
