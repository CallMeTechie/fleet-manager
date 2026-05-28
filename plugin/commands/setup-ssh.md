---
description: Generate the plugin SSH keypair if missing and deploy it to a server for passwordless auth. Idempotent.
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
---

# Setup SSH

Establish passwordless key auth to a server using the plugin-dedicated keypair.
Idempotent — re-running on a configured server is a no-op.

## Anti-Pattern Rule (do not violate)

**Never invoke `ssh-copy-id` from this command via the Bash tool.** It hangs
without a TTY. Only the user-typed `!`-prefix allocates a PTY for password entry.
This command's job is to **present** the `ssh-copy-id` line as copyable text.

## Steps

### 1. Resolve target + connection details

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"
NAME="$(resolve_server "$(printf '%s' "$ARGUMENTS" | tr -d '[:space:]')")"
```

If `resolve_server` fails (no profile yet), ask via `AskUserQuestion` for: server
name, host, port (default 22), user. Validate host `^[a-zA-Z0-9.-]+$`, port 1–65535,
user `^[a-zA-Z0-9_.-]+$`. Write the **Connection** section of
`context/servers/<name>.md` first (Concern 6 — profile exists before key deploy),
using the `EXAMPLE.md.template` as the base.

### 2. Ensure the plugin keypair exists (never overwrite)

```bash
KEY="$HOME/.ssh/fleet-manager_ed25519"
if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -N "" -f "$KEY" -C "fleet-manager@$(hostname)"
  chmod 600 "$KEY"
fi
```

### 3. Test key auth (cold)

```bash
build_ssh "$NAME"
if "${FM_SSH[@]}" "echo OK" 2>/dev/null | grep -qx OK; then
  echo "Key auth already works for $NAME."; exit 0
fi
```

> **Host key (first connection):** the plugin keeps the OpenSSH default for
> host-key checking (it does **not** auto-trust). With `BatchMode=yes` there is no
> interactive prompt, so a host whose key is not yet in `~/.ssh/known_hosts` makes
> this cold test fail. Establish it once, out of band, after reviewing the
> fingerprint: `ssh-keyscan -p <port> <host> >> ~/.ssh/known_hosts` (or connect
> once interactively and accept the key). Intentional — it blocks a silent
> man-in-the-middle on an unknown host.

### 4. Present the deployment instruction (copy-paste, not auto-run)

Each `bash` block runs in its own subshell, so FM_* from step 3 is gone here.
Re-load the profile and print the exact command so you substitute real values
(never guess host/port):

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"
NAME="$(resolve_server "$(printf '%s' "$ARGUMENTS" | tr -d '[:space:]')")"
load_profile "$NAME"
echo "Show the user (literally, with the leading '!'):"
echo "  ! ssh-copy-id -p $FM_PORT -i ~/.ssh/fleet-manager_ed25519.pub $FM_USER@$FM_HOST"
```

Present the user this **literal text** with the values from the block above:

> **Bitte tippe den folgenden Befehl WÖRTLICH inklusive Ausrufezeichen am Anfang:**
>
> `! ssh-copy-id -p <port> -i ~/.ssh/fleet-manager_ed25519.pub <user>@<host>`
>
> Das `!` ist ein Claude-Code-Prefix und essenziell — es allokiert ein interaktives
> Terminal für die Passworteingabe. Ohne `!` hängt der Befehl deterministisch.

Then ask via `AskUserQuestion`: "ssh-copy-id durchgelaufen, weiter mit Verifikation?"
(Options: "Ja, weiter" / "Abbrechen"). Do NOT auto-poll.

### 5. Re-verify and finalize

```bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT:-plugin}/commands/_fleet-lib.sh"
NAME="$(resolve_server "$(printf '%s' "$ARGUMENTS" | tr -d '[:space:]')")"
build_ssh "$NAME"
if "${FM_SSH[@]}" "echo OK" 2>/dev/null | grep -qx OK; then
  echo "Key auth verified for $NAME. Run /diag $NAME."
else
  cat >&2 <<'MSG'
Key auth still failing. Most common causes:
  1. SSH service not enabled / wrong port.
  2. ssh-copy-id was not run with the leading `!`.
  3. User has no shell access on the server.
  4. Host key not yet in ~/.ssh/known_hosts (BatchMode cannot prompt) — add it:
     ssh-keyscan -p <port> <host> >> ~/.ssh/known_hosts  (review the fingerprint).
Re-run /setup-ssh.
MSG
  exit 1
fi
```
