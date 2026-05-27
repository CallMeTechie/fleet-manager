# docker fixtures (provenance)

Canonical Docker Compose v2 outputs used by the mock `docker` stub. Hand-curated to
the v2 `compose ls --format json` shape (array of `{Name, Status, ConfigFiles}`,
Status like `running(2)`/`exited(0)`/`created(0)`), deliberately including:

- a **multi-file** `ConfigFiles` (`db`) to exercise `compose_config_args` splitting,
- an **empty** `ConfigFiles` (`broken`) to exercise the hard-abort path,
- three status variants (running / exited / created).

Regenerate from a real host with `docker compose ls --format json` /
`docker ps --format '...'` when one is available; keep the variants above.
