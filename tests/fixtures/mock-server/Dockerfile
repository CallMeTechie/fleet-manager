FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server sudo procps coreutils ca-certificates rsync \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/sshd

# Test user
RUN useradd -m -s /bin/bash deploy

# Behavior toggles consumed by setup-stubs.sh:
#   MOCK_DOCKER=yes|no        -> whether `docker` is on PATH
#   MOCK_SUDO=nopasswd|passwd -> whether `sudo -n true` succeeds
ENV MOCK_DOCKER=yes
ENV MOCK_SUDO=nopasswd

COPY setup-stubs.sh /usr/local/bin/setup-stubs.sh
RUN chmod +x /usr/local/bin/setup-stubs.sh
COPY docker-fixtures/ /usr/local/bin/docker-fixtures/

EXPOSE 22
# This is an EPHEMERAL TEST FIXTURE, not a production image. sshd must run as root:
# it accepts a login as the unprivileged `deploy` user (reading shadow + privilege
# separation), writes /etc/sudoers.d at startup, and binds privileged port 22. The
# managed surface is exercised exclusively as `deploy`. Documented exception.
# nosemgrep: dockerfile.security.missing-user.missing-user
CMD ["/usr/local/bin/setup-stubs.sh"]
