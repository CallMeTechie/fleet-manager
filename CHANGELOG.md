# Changelog

All notable changes to fleet-manager are documented here. Format: Keep a Changelog;
versioning: SemVer.

## [0.3.3] - 2026-08-03

### Fixed

- The inventory no longer lives inside the plugin directory. `_fleet-lib.sh`
  derived `FM_CONTEXT` from its own location, which Claude Code installs into a
  version-pinned cache path (`.../fleet-manager/0.3.2/context`). Every
  `claude plugin update` therefore started from an empty inventory and stranded
  the previous version's server profiles, `active-server` and `inventory.md` in
  a directory nobody looks at. The default is now
  `${XDG_CONFIG_HOME:-~/.config}/fleet-manager`; `FM_CONTEXT_DIR` still
  overrides it.

### Added

- One-time migration of a pre-0.3.3 in-plugin inventory. It fires only when the
  legacy directory holds real profiles and the new one holds none, so it cannot
  clobber a live inventory, and it copies rather than moves.
- `tests/unit/test-context-dir.sh`: covers override precedence, the XDG default,
  the `$HOME/.config` fallback, and all migration guards.

## [0.3.2] - 2026-08-03

### Fixed

- `plugin.json`: `repository` is now a string URL. The object form introduced in
  0.3.1 failed manifest validation (`expected string, received object`) and made
  `claude plugin install fleet-manager@fleet-manager` impossible.

### Changed

- Plugin context moved from `plugin/CLAUDE.md` to `plugin/skills/fleet-manager/SKILL.md`.
  A `CLAUDE.md` at the plugin root is never loaded as context, so the command
  reference and operational guidelines it carried had no effect.
- The active server is now recorded only in `plugin/context/active-server`.
  `/use`, `/first-run` and the `fleet-intake` agent no longer mirror it into a
  managed block — that duplicate dirtied a version-controlled file on every
  `/use` and was overwritten on `plugin update`.

### Removed

- The `<!-- fleet-manager:managed-start -->` block and the session `Notes`
  section, along with `plugin/CLAUDE.md` itself.

## [0.3.1] - 2026-05-28

### Changed

- Replace personal author/copyright name with `CallMeTechie` across README,
  LICENSE, `plugin.json`, and `marketplace.json` for a consistent public identity.
- `marketplace.json.name`: rename `fleet-manager-local` → `fleet-manager` to
  match the public repository.
- Release-job git config now uses the GitHub noreply address.

### Added

- `plugin.json`: `homepage` and `repository` fields pointing at the public repo.

### Fixed

- README link to sibling plugin now points to its repository, not the user profile.

## [0.3.0] - 2026-05-27

### Added

- `/health-summary`: sequential fleet health sweep (UP/DOWN/SKIP + verdict), one
  field-safe SSH round-trip per server.
- `/copy` and `/sync`: local↔server file transfer via rsync (`--protect-args`),
  `<server>:<path>` endpoint syntax, scp fallback for `/copy`. `/sync` is dry-run by
  default; `--delete` is gated by a `--confirm-delete=<server>` match token.
- `_transfer-lib.sh` (endpoint parsing, boundary-safe protected-path gate, rsync-rsh
  builder, local/remote rsync detection); `server_health_line` in `_fleet-lib.sh`.
- Mock fixture gains real rsync; unit + integration coverage. CI now runs all
  `tests/unit/*.sh` (previously only the lib suite).

## [0.2.0] - 2026-05-27

### Added

- Docker Compose suite: `/compose-list`, `/docker-list`, `/compose-logs`,
  `/compose-up` (with `--file` first-deploy), `/compose-down` (critical-gated),
  `/compose-update`; plus `/logs` (journalctl + syslog fallback).
- Per-server `docker_cmd` discovery (probed at `/diag`/intake, allowlist-validated).
- `_compose-lib.sh`; `_fleet-lib.sh` gains scope/protected-resource/confirm gates
  and an `FM_SSH_EXTRA_OPTS` seam.
- Enforced scopes (`docker_compose`, `system_monitoring`) and a `--confirm=<project>`
  critical-project gate.
- Scripted docker/journalctl mock stub + committed fixtures; unit + integration
  coverage, incl. command-body gate tests.

## [0.1.0] - 2026-05-26

### Added

- Phase 1 foundation: multi-server inventory with an active-server model.
- Shared lib `_fleet-lib.sh`: profile parsing (strict/text), tilde-expanded key paths,
  SSH argument-array builder, atomic inventory/active-server writes, target echo.
- Commands: `/first-run`, `/add-server` (re-add protected), `/list-servers`, `/use`,
  `/setup-ssh`, `/diag`, `/status`.
- `fleet-intake` setup agent.
- Tests: unit (lib), static (shellcheck/frontmatter/markdownlint/manifests/abspath),
  integration against a mock SSH server.
- CI: validate, integration, release workflows.
