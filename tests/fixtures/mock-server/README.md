# Mock server fixture (Phase 1)

A minimal Debian + sshd container that responds to exactly the SSH surface used by
`/diag` and `/status`: `echo`, `df`, `free`, `uptime`, `nproc`, `uname`,
`/etc/os-release`, `command -v docker`, `sudo -n true`.

**No real docker daemon** — `MOCK_DOCKER=yes` installs a tiny `docker` stub on PATH
so `command -v docker` succeeds; `MOCK_DOCKER=no` removes it. `MOCK_SUDO=nopasswd|passwd`
toggles whether `sudo -n true` succeeds. The Phase-2 compose suite will add a real
daemon mock.

Build/run is driven by `tests/integration/run-all.sh`; the plugin public key is passed
via the `FLEET_PUBKEY` env var and installed into `deploy`'s `authorized_keys`.
