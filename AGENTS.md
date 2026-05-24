# AGENTS.md

This repository maintains `harden-dev-env.sh`, a developer-machine supply-chain hardening script. Treat changes here as security-sensitive because users may run the script against their real home directory.

## Scope

- The main implementation is `harden-dev-env.sh`.
- Test coverage lives in `tests/supply-chain-hardening/`.
- Release verification lives in `scripts/release-check.sh`.
- User-facing behavior and the pinned bootstrap snippet are documented in `README.md`.

## Safety Rules

- Do not run `harden-dev-env.sh` against the real workspace user environment unless the human explicitly asks for that.
- Prefer the scenario harness for behavior checks; it creates isolated temporary homes and stub package-manager binaries.
- Do not make the release helper tag, push, publish, upload, or bless a new trusted bootstrap. It may run tests, compute SHA256, and print a snippet only.
- Keep the bootstrap URL pinned to an immutable commit or tag and keep the SHA256 in sync with `harden-dev-env.sh`.
- Preserve the confirmation prompt and `HARDEN_ASSUME_YES=1` behavior unless the human explicitly approves a behavior change.
- Preserve Bash 3.2 compatibility. Avoid Bash features newer than macOS system Bash unless the compatibility test is intentionally updated.

## Development Workflow

After changing shell scripts, run:

```bash
bash -n harden-dev-env.sh
bash -n tests/supply-chain-hardening/run-scenarios.sh
bash -n tests/supply-chain-hardening/run-docker.sh
bash -n tests/supply-chain-hardening/run-macos-compat.sh
bash -n scripts/release-check.sh
```

After behavior changes, run:

```bash
bash tests/supply-chain-hardening/run-docker.sh
bash tests/supply-chain-hardening/run-macos-compat.sh
```

For release readiness, run:

```bash
bash scripts/release-check.sh
```

Review its printed bootstrap snippet manually before updating docs, tagging, or publishing.

## Test Expectations

Keep scenario coverage for:

- strict default baseline
- confirmation abort preventing writes
- relaxed scripts and custom `AGE_DAYS`
- existing config backups and idempotent reruns
- missing package managers
- no `XDG_CONFIG_HOME`
- `.zshrc` managed block writes
- broken managed block failure
- unprepared Corepack pnpm/Yarn shim skips
- unsupported package-manager versions warning while still writing defaults
- Bash 3.2 compatibility as the macOS Bash proxy

## Editing Guidance

- Keep changes small and auditable.
- Use shell builtins and common POSIX tools where practical, but the script may remain Bash.
- Keep comments focused on non-obvious security or compatibility decisions.
- Update `README.md` when user-facing behavior, supported package-manager versions, bootstrap instructions, tests, or release steps change.
