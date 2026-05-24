# Supply Chain Dev Hardening

Developer-machine hardening defaults for JavaScript package managers and Socket Firewall aliases.

## Pinned Bootstrap

Pin the raw URL to an immutable commit and verify the script hash before executing it:

```bash
(
  set -euo pipefail

  url='https://raw.githubusercontent.com/YOUR_ORG/supply-chain-dev-hard/COMMIT_SHA/harden-dev-env.sh'
  sha256='d72eb97b4c353b6ead9f8f9a7aaf76fd3a6baf440204cc56f0bcef78e0d37b94'
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

## Intended Audience

This script is for individual developer machines that want user-level package-manager hardening defaults. It is not meant as unattended CI or centrally enforced fleet policy.

It writes idempotent user-level baseline policy for npm, pnpm, Yarn, and Bun where each tool exposes a suitable user-level control. It assumes you already install and update your preferred package managers through your normal trusted path.

For npm, pnpm, and Bun, project configs, environment variables, and command-line flags can still override these user-level defaults. Yarn defaults are shell environment variables because Yarn has no true home-global `.yarnrc.yml`; change or remove the managed shell block for Yarn-specific exceptions.

## Package-Manager Coverage

- npm: exact saves, audit enabled, funding prompts disabled, `min-release-age`, and strict lifecycle-script blocking by default.
- pnpm: exact saves, release-age gate, strict missing-time handling, exotic transitive dependency blocking, trust-policy downgrade protection, and lifecycle-script blocking by default.
- Yarn: shell environment defaults for age gate, hardened mode, checksum behavior, exact saves, and lifecycle-script blocking by default.
- Bun: exact saves, release-age gate, and lifecycle-script blocking by default.
- Socket Firewall: best-effort global `sfw` install when npm/node are already available, plus shell aliases for npm, npx, Bun, Bunx, pnpm, Yarn, uv, pip, pip3, and cargo when `sfw` is available.

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

To bypass the confirmation prompt in a controlled local bootstrap:

```bash
HARDEN_ASSUME_YES=1 bash harden-dev-env.sh
```

By default, lifecycle scripts are disabled. To allow lifecycle scripts in the written defaults:

```bash
STRICT_INSTALL_SCRIPTS=0 bash harden-dev-env.sh
```

The default release-age gate is 7 days. Override it with `AGE_DAYS`:

```bash
AGE_DAYS=3 bash harden-dev-env.sh
```

## Notes

- npm `min-release-age` is in days and requires npm 11.10+. Older npm versions may still honor other `.npmrc` defaults such as `ignore-scripts` and `save-exact`.
- pnpm user-level YAML policy requires pnpm 11.1.3+. An unprepared Corepack pnpm shim is treated as not installed for verification.
- Yarn policy requires modern Yarn 4.15+. Yarn Classic is intentionally unsupported because it has no release-age gate.
- Bun policy requires Bun 1.3+.
- Package managers are not installed or updated by this script. Install npm, pnpm, Yarn, or Bun through your normal trusted path.
- Verification avoids Corepack provisioning: package-manager probes run with Corepack network access disabled, so a Corepack shim must already have its exact package-manager version prepared or that tool's preflight/verification is skipped.
- Socket Firewall is installed only when npm/node are already available, with lifecycle scripts disabled.
- Socket Firewall verification confirms wrapper invocation, not malware blocking; aliases take effect in new shells or after sourcing the updated shell rc file.
- npm `before` is an absolute publish-date cutoff and takes precedence over `min-release-age` when both are set in the same or higher-priority npm config. This script leaves existing `before` settings intact as intentional user policy and prints the active value during verification.
- `ignore-scripts=true` is intentionally strict and may require per-project exceptions for packages that build native binaries.

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

## Testing

Run the standard Docker scenarios:

```bash
bash tests/supply-chain-hardening/run-docker.sh
```

Run the Bash 3.2 compatibility scenarios, used as the macOS Bash compatibility proxy:

```bash
bash tests/supply-chain-hardening/run-macos-compat.sh
```

The scenario coverage includes strict defaults, confirmation aborts, relaxed script settings, custom `AGE_DAYS`, existing config backups, idempotent reruns, missing package managers, unset `XDG_CONFIG_HOME`, `.zshrc` managed blocks, broken managed block failures, unprepared Corepack shims, and unsupported package-manager version warnings.

## Release Process

1. Update `harden-dev-env.sh`.
2. Run standard Docker tests: `bash tests/supply-chain-hardening/run-docker.sh`.
3. Run Bash 3.2 compatibility tests: `bash tests/supply-chain-hardening/run-macos-compat.sh`.
4. Review the script diff: `git diff -- harden-dev-env.sh`.
5. Generate the SHA256: `sha256sum harden-dev-env.sh` or `shasum -a 256 harden-dev-env.sh`.
6. Update the pinned bootstrap snippet with the new immutable raw URL and SHA256.
7. Tag or pin to an immutable commit.
8. Publish only after explicit human confirmation.

The helper below runs the verification sequence and prints a bootstrap snippet:

```bash
bash scripts/release-check.sh
```

It does not tag, publish, push, or bless a new trusted bootstrap. Those steps require explicit human action after reviewing the diff and printed snippet.

## References

- npm config `before` and `min-release-age`
- pnpm `savePrefix` and `minimumReleaseAge`
- Yarn `.yarnrc.yml` lookup and environment variables
- Yarn `npmMinimalAgeGate`
- Yarn `defaultSemverRangePrefix`
- Bun `minimumReleaseAge`
