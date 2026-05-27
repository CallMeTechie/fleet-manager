# Claude fleet-manager

This repository is your workspace for managing a fleet of Linux servers over SSH.
It persists a per-server inventory and an "active server" pointer across sessions.

<!-- fleet-manager:managed-start -->

## Active Server

_none — run `/use <name>` (see `/list-servers` for the inventory)_

> The managed block intentionally contains NO hostnames/IPs. The real inventory
> (hosts, users, ports) lives in the git-ignored `context/inventory.md` and the
> per-server profiles. View it with `/list-servers`.

## SSH Key

- Plugin key: `~/.ssh/fleet-manager_ed25519` (deployed per server via `/setup-ssh`)

## Scoped Operations (per server)

Each server profile carries its own authorized categories: system_monitoring,
file_operations, package_management, service_management, docker_compose,
file_transfer. **Enforced** for compose commands (`docker_compose`) and `/logs`
(`system_monitoring`) — a command refuses if its scope is unticked. Ad-hoc SSH
remains **advisory** (honor scopes/protected resources before destructive commands).
Destructive compose actions against `critical_compose_projects` need a matching
`--confirm=<project>` token.

<!-- fleet-manager:managed-end -->

## Available Commands

| Command | Description |
| - | - |
| `/first-run` | Onboard your first server (interactive intake agent) |
| `/add-server` | Add another server to the inventory |
| `/list-servers` | Show the inventory; mark the active server |
| `/use <name>` | Set the active server |
| `/setup-ssh [server]` | Generate the plugin keypair and deploy it (idempotent) |
| `/diag [server]` | Connectivity + health check (SSH, sudo, docker, disk, load) |
| `/status [server]` | Disk / memory / uptime / load snapshot |
| `/compose-list [server]` | List Compose projects |
| `/docker-list [server] [--all]` | List containers |
| `/compose-logs [server] <project>` | Compose logs |
| `/compose-up [server] <project\|--file path>` | Start a stack |
| `/compose-down [server] <project> [--remove]` | Stop a stack (critical → `--confirm`) |
| `/compose-update [server] <project>` | Pull + recreate |
| `/logs [server] [unit]` | System journal (journalctl/syslog) |
| `/health-summary` | Fleet-wide health (one row per server) |
| `/copy <src> <dst>` | Copy local↔server (rsync/scp) |
| `/sync <src> <dst> [--apply]` | Mirror local↔server (dry-run default) |

## Operational Guidelines

### Before Operations

1. Resolve the target: explicit argument wins, else the active server.
2. **Always confirm the target** — every command prints `→ Ziel: <name> (user@host:port)` first.
3. Check the server's profile for authorized scopes and protected resources.

### During Operations

1. Use SSH via the `FM_SSH=(...)` array from `_fleet-lib.sh` — never string-interpolate.
2. Prefer non-destructive operations (list before delete, backup before modify).
3. For destructive actions against `critical_compose_projects` or `protected_paths`,
   confirm the server name and the resource explicitly before proceeding.

### After Operations

1. Update the profile's "Discovered State" when state changes.
2. Regenerate `inventory.md` after inventory changes (`write_inventory`).

## Notes

_Space for session notes — preserved across `/first-run` and `/add-server` re-runs:_

---
