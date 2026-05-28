# fleet-manager

A Claude Code plugin for managing a **fleet of Linux servers** over SSH. Keeps a
per-server inventory and an "active server" pointer, deploys a dedicated SSH key,
and provides guided setup, connectivity diagnostics and system status across hosts.

Modeled on [`synology-manager-plus`](https://github.com/CallMeTechie/synology-manager-plus);
the NAS stays there (DSM-specific), `fleet-manager` is for generic Linux hosts.

## Workspace & persistence

The repo IS your workspace. **Real inventory lives locally and is git-ignored**
(`plugin/context/servers/*.md`, `active-server`, `inventory.md`) — only templates are
committed, so server topology never lands in git and survives `claude plugin update`.

## Commands

| Command | Description |
| - | - |
| `/first-run` | Onboard your first server (interactive intake agent) |
| `/add-server` | Add another server (re-add protected) |
| `/list-servers` | Show the inventory; mark the active server |
| `/use <name>` | Set the active server |
| `/setup-ssh [server]` | Generate + deploy the plugin keypair (idempotent) |
| `/diag [server]` | Connectivity + health check |
| `/status [server]` | Disk / memory / uptime / load |
| `/compose-list [server]` | List Compose projects |
| `/docker-list [server] [--all]` | List containers |
| `/compose-logs [server] <project>` | Compose logs |
| `/compose-up [server] <project\|--file path>` | Start a stack (scope-gated) |
| `/compose-down [server] <project> [--remove]` | Stop a stack (critical → `--confirm`) |
| `/compose-update [server] <project>` | Pull + recreate |
| `/logs [server] [unit]` | System journal (journalctl/syslog) |
| `/health-summary` | Fleet-wide health (one row per server) |
| `/copy <src> <dst>` | Copy local↔server (rsync/scp) |
| `/sync <src> <dst> [--apply]` | Mirror local↔server (dry-run default) |

The active server is targeted when no argument is given; pass a name to override.
Every command prints `→ Ziel: <name> (user@host:port)` before acting.

## Fleet & transfer

`/health-summary` does a sequential one-row-per-server sweep (UP/DOWN/SKIP + verdict),
one SSH round-trip each. `/copy` and `/sync` move files between the local machine and a
server using the `<server>:<path>` syntax (the name before `:` is an inventory server,
resolved through the plugin key). Both require the server's `file_transfer` scope; rsync
is used (`--protect-args`), with an scp fallback for `/copy`. `/sync` is **dry-run by
default** (`--apply` to execute); `--delete` additionally needs the typed
`--confirm-delete=<server>` token, and a protected-path destination needs `--confirm=<server>`.
Paths must be space-free at the command boundary.

## Compose & logs

The compose suite drives `docker compose` on each host via a per-server `docker_cmd`
discovered at `/diag`/intake (e.g. `docker`, `sudo -n docker`) and allowlist-validated.
Compose commands require the server's `docker_compose` scope; `/logs` requires
`system_monitoring`. Destructive actions against a project listed in the profile's
`critical_compose_projects` require a human-typed `--confirm=<project>` token (or
`FM_CONFIRM_CRITICAL=yes`) — a fail-safe against accidental runs (it makes intent
visible in the command line; it is not an agent-proof gate). A never-started stack is
brought up with `/compose-up --file /abs/path/docker-compose.yml`.

## Requirements

- SSH access to each server; the plugin uses its own key `~/.ssh/fleet-manager_ed25519`.
- Bash >= 4, OpenSSH client locally.

### Host-key verification (first connection)

The plugin does **not** disable host-key checking — it relies on the OpenSSH
default, which is the secure choice. Because every connection runs with
`BatchMode=yes` (no interactive prompts), the **first** connection to a host whose
key is not yet in your `~/.ssh/known_hosts` will fail rather than silently
trust-on-first-use. Establish the host key once, out of band, before `/diag`:

```bash
ssh-keyscan -p <port> <host> >> ~/.ssh/known_hosts   # review the fingerprint first
# or simply connect once interactively and accept the key:
ssh -p <port> <user>@<host>
```

This is intentional: it prevents a silent man-in-the-middle on an unknown host.
`/setup-ssh` surfaces this as a likely cause when key auth fails.

## Development

- Unit tests: `for t in tests/unit/*.sh; do bash "$t"; done`
- Static checks: `for s in tests/static/*.sh; do bash "$s"; done`
- Integration (needs Docker + rsync): `bash tests/integration/run-all.sh`

## License

MIT — CallMeTechie
