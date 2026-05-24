# Supply Chain Dev Hardening

Developer-machine hardening defaults for JavaScript package managers and optional Socket Firewall aliases.

This repository maintains [harden-dev-env.sh](./harden-dev-env.sh), a security-sensitive Bash script that writes user-level supply-chain hardening defaults. Users may run it against their real home directory, so changes should stay small, auditable, and covered by the isolated scenario harness.

## How to Install

This is the recommended install command for developers running the script from GitHub. Publish or share the whole snippet below, with `url` pinned to the reviewed commit or tag and `sha256` set to that exact copy of [harden-dev-env.sh](./harden-dev-env.sh). Developers should copy and paste the full block into their terminal.

The snippet downloads the script to a temporary file, verifies its SHA256, then runs it. The normal confirmation prompt still appears unless the caller explicitly sets `HARDEN_ASSUME_YES=1`.

```bash
(
  set -euo pipefail

  url='https://raw.githubusercontent.com/murderteeth/supply-chain-dev-hard/7e80d8f755239e08e9415902fa9f2bf9669465f1/harden-dev-env.sh'
  sha256='651ba8128fa95c67bc7388179fe91f5ebc018c2dc83d0e1d89aa68b09322ddf7'
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  curl -fsSL "$url" -o "$tmp"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$sha256" "$tmp" | sha256sum -c -
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$tmp" | awk '{print $1}')"
    [ "$actual" = "$sha256" ]
  else
    printf 'ERROR: need sha256sum or shasum\n' >&2
    exit 1
  fi
  bash "$tmp"
)
```

Use a raw URL pinned to a specific commit or tag and update `sha256` whenever `harden-dev-env.sh` changes.

## What It Does

The script writes idempotent user-level baseline policy for npm, pnpm, Yarn, and Bun where each tool exposes a suitable user-level control. It assumes users already install and update package managers through their normal trusted path.

For npm, pnpm, and Bun, project configs, environment variables, and command-line flags can still override these user-level defaults. Yarn defaults are shell environment variables because Yarn has no true home-global `.yarnrc.yml`; change or remove the managed shell block for Yarn-specific exceptions.

Package-manager coverage:

- npm: exact saves, audit enabled, funding prompts disabled, `min-release-age`, and strict lifecycle-script blocking by default.
- pnpm: exact saves, release-age gate, strict missing-time handling, exotic transitive dependency blocking, trust-policy downgrade protection, and lifecycle-script blocking by default.
- Yarn: shell environment defaults for age gate, hardened mode, checksum behavior, exact saves, and lifecycle-script blocking by default.
- Bun: exact saves, release-age gate, and lifecycle-script blocking by default.
- Socket Firewall: optional best-effort global `sfw` install when npm/node are already available, plus shell aliases for npm, npx, Bun, Bunx, pnpm, Yarn, uv, pip, pip3, and cargo when `sfw` is available.

The baseline intentionally targets npm 11.x, pnpm 11.x, Yarn 4.x, and Bun 1.x. Older or newer installed tools are warned about, not removed or upgraded.

## Running

Run interactively:

```bash
bash harden-dev-env.sh
```

The script prints the intended changes and asks:

```text
[harden] Continue? [y/N]
```

If you continue, it separately asks whether to install/update Socket Firewall and add shell aliases:

```text
[harden] Install Socket Firewall wrapper and shell aliases? [y/N]
```

To bypass the confirmation prompt in a controlled local bootstrap:

```bash
HARDEN_ASSUME_YES=1 bash harden-dev-env.sh
```

`HARDEN_ASSUME_YES=1` also opts into Socket Firewall to preserve the noninteractive bootstrap behavior. To bypass prompts but skip Socket Firewall:

```bash
HARDEN_ASSUME_YES=1 HARDEN_INSTALL_SOCKET_FIREWALL=0 bash harden-dev-env.sh
```

To opt into Socket Firewall without the second prompt during an interactive run:

```bash
HARDEN_INSTALL_SOCKET_FIREWALL=1 bash harden-dev-env.sh
```

By default, lifecycle scripts are disabled. To allow lifecycle scripts in the written defaults:

```bash
STRICT_INSTALL_SCRIPTS=0 bash harden-dev-env.sh
```

The default release-age gate is 7 days. Override it with `AGE_DAYS`:

```bash
AGE_DAYS=3 bash harden-dev-env.sh
```

## Rollback

The script creates one-time backups named `*.pre-supply-chain-harden.bak` before modifying existing config files.

To roll back, inspect the current file and its backup, then restore or merge only the settings you want to undo. The main files are:

- `~/.npmrc`
- `${XDG_CONFIG_HOME:-~/.config}/pnpm/config.yaml`
- `$XDG_CONFIG_HOME/.bunfig.toml` or `~/.bunfig.toml`
- `~/.bashrc`
- `~/.zshrc`

For shell aliases or Yarn environment defaults, remove only the relevant managed block between:

```sh
# >>> Socket Firewall aliases >>>
# <<< Socket Firewall aliases <<<
# >>> Yarn hardening defaults >>>
# <<< Yarn hardening defaults <<<
```

If using an LLM or coding assistant, ask it to remove or merge only the supply-chain hardening settings, preserving unrelated local configuration.

## Development

Repository layout:

- [harden-dev-env.sh](./harden-dev-env.sh): main implementation.
- [tests/supply-chain-hardening/run-scenarios.sh](./tests/supply-chain-hardening/run-scenarios.sh): isolated scenario harness with temporary homes and stub package-manager binaries.
- [tests/supply-chain-hardening/run-scenarios-on-linux.sh](./tests/supply-chain-hardening/run-scenarios-on-linux.sh): Linux scenario runner.
- [tests/supply-chain-hardening/run-scenarios-on-macos.sh](./tests/supply-chain-hardening/run-scenarios-on-macos.sh): Bash 3.2 scenario runner used as the macOS Bash proxy.
- [scripts/release-check.sh](./scripts/release-check.sh): release verification helper that prints a pinned bootstrap snippet.

Do not run `bash harden-dev-env.sh` as a test unless you intentionally want to modify your real user-level package-manager configs. Prefer the scenario harness; it creates isolated temporary homes, sets `HOME` to those temporary paths, and puts stub package-manager binaries first in `PATH`.

After changing shell scripts, run syntax checks:

```bash
bash -n harden-dev-env.sh
bash -n tests/supply-chain-hardening/run-scenarios.sh
bash -n tests/supply-chain-hardening/run-scenarios-on-linux.sh
bash -n tests/supply-chain-hardening/run-scenarios-on-macos.sh
bash -n scripts/release-check.sh
```

Run the fast local scenario harness. This runs on your machine, but the script under test is executed with an isolated temporary `HOME` and stub package-manager binaries:

```bash
bash tests/supply-chain-hardening/run-scenarios.sh
```

After behavior changes, run both Docker-backed suites. These run the same isolated scenarios inside images built from the checked-in Dockerfiles. `run-scenarios-on-linux.sh` verifies behavior in a clean Linux image, and `run-scenarios-on-macos.sh` runs the scenarios under Bash 3.2, which is the compatibility target for macOS system Bash.

Run these when a change affects script behavior, shell syntax, config writes, prompts, package-manager detection, or release readiness. They are usually unnecessary for README-only edits.

```bash
bash tests/supply-chain-hardening/run-scenarios-on-linux.sh
bash tests/supply-chain-hardening/run-scenarios-on-macos.sh
```

The scenario coverage includes strict defaults, confirmation aborts, optional Socket Firewall declines, noninteractive Socket Firewall skips, relaxed script settings, custom `AGE_DAYS`, existing config backups, idempotent reruns, missing package managers, unset `XDG_CONFIG_HOME`, `.zshrc` managed blocks, broken managed block failures, unprepared Corepack shims, and unsupported package-manager version warnings.

## Release

For release readiness, run:

```bash
bash scripts/release-check.sh
```

The helper runs the verification sequence and prints a bootstrap snippet. It does not tag, publish, push, upload, or bless a new trusted bootstrap.

Release process:

1. Update `harden-dev-env.sh`.
2. Run Linux scenarios: `bash tests/supply-chain-hardening/run-scenarios-on-linux.sh`.
3. Run macOS compatibility scenarios: `bash tests/supply-chain-hardening/run-scenarios-on-macos.sh`.
4. Review the script diff: `git diff -- harden-dev-env.sh`.
5. Generate the SHA256: `sha256sum harden-dev-env.sh` or `shasum -a 256 harden-dev-env.sh`.
6. Update the pinned bootstrap snippet with the new immutable raw URL and SHA256.
7. Tag or pin to an immutable commit.
8. Publish only after explicit human confirmation.

## Notes

- npm `min-release-age` is in days and requires npm 11.10+. Older npm versions may still honor other `.npmrc` defaults such as `ignore-scripts` and `save-exact`.
- pnpm user-level YAML policy requires pnpm 11.1.3+. An unprepared Corepack pnpm shim is treated as not installed for verification.
- Yarn policy requires modern Yarn 4.15+. Yarn Classic is intentionally unsupported because it has no release-age gate.
- Bun policy requires Bun 1.3+.
- Package managers are not installed or updated by this script. Install npm, pnpm, Yarn, or Bun through your normal trusted path.
- Verification avoids Corepack provisioning: package-manager probes run with Corepack network access disabled, so a Corepack shim must already have its exact package-manager version prepared or that tool's preflight/verification is skipped.
- Socket Firewall is installed only after confirmation, only when npm/node are already available, and with lifecycle scripts disabled.
- Socket Firewall verification runs only when Socket Firewall is enabled and confirms wrapper invocation, not malware blocking; aliases take effect in new shells or after sourcing the updated shell rc file.
- npm `before` is an absolute publish-date cutoff and takes precedence over `min-release-age` when both are set in the same or higher-priority npm config. This script leaves existing `before` settings intact as intentional user policy and prints the active value during verification.
- `ignore-scripts=true` is intentionally strict and may require per-project exceptions for packages that build native binaries.

## References

- npm config `before` and `min-release-age`
- pnpm `savePrefix` and `minimumReleaseAge`
- Yarn `.yarnrc.yml` lookup and environment variables
- Yarn `npmMinimalAgeGate`
- Yarn `defaultSemverRangePrefix`
- Bun `minimumReleaseAge`
