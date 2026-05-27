#!/usr/bin/env bash
set -euo pipefail

# Authorized key (public) provided at runtime via env.
mkdir -p /home/deploy/.ssh
if [ -n "${FLEET_PUBKEY:-}" ]; then
  echo "$FLEET_PUBKEY" > /home/deploy/.ssh/authorized_keys
fi
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys 2>/dev/null || true

# Docker presence toggle: install a scripted stub fed by committed fixtures.
if [ "${MOCK_DOCKER:-yes}" = "yes" ]; then
  mkdir -p /opt/fixtures
  cp /usr/local/bin/docker-fixtures/* /opt/fixtures/ 2>/dev/null || true
  cat > /usr/local/bin/docker <<'STUB'
#!/bin/sh
# Scripted docker stub. Recognizes the Phase-2 command surface; emits fixtures.
case "$*" in
  *"info"*)            echo "27.0.0" ;;
  *"compose ls"*)      cat /opt/fixtures/compose-ls.json ;;
  *"ps"*)              cat /opt/fixtures/docker-ps.txt ;;
  *"compose"*"logs"*)  echo "web-app-1  | listening on :80"; echo "web-db-1   | ready" ;;
  *"compose"*"up"*)    echo "Container started"; exit 0 ;;
  *"compose"*"down"*)  echo "Container removed"; exit 0 ;;
  *"compose"*"stop"*)  echo "Container stopped"; exit 0 ;;
  *"compose"*"pull"*)  echo "Pulled"; exit 0 ;;
  *)                   echo "stub: unhandled docker args: $*" >&2; exit 2 ;;
esac
STUB
  chmod +x /usr/local/bin/docker
else
  rm -f /usr/local/bin/docker
fi

# journalctl stub for /logs tests. A `-u <unit>` query returns nothing (like real
# journalctl for an unknown unit → exercises the /compose-logs hint); a plain query
# returns mock lines.
cat > /usr/local/bin/journalctl <<'JSTUB'
#!/bin/sh
case "$*" in
  *"-u "*) exit 0 ;;
  *) echo "May 27 10:00:00 mock systemd[1]: Started mock service."
     echo "May 27 10:00:01 mock sshd[42]: Accepted publickey for deploy" ;;
esac
JSTUB
chmod +x /usr/local/bin/journalctl

# Sudo toggle.
if [ "${MOCK_SUDO:-nopasswd}" = "nopasswd" ]; then
  echo "deploy ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/deploy
  chmod 0440 /etc/sudoers.d/deploy
else
  rm -f /etc/sudoers.d/deploy
fi

ssh-keygen -A
exec /usr/sbin/sshd -D -e
