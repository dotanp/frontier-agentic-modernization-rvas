#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /.dockerenv || ! -f /bootstrap/setup.sh ]]; then
    echo "Run this test inside its dedicated Docker image, not on the host." >&2
    exit 1
fi

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

shellcheck --severity=error /bootstrap/setup.sh /tests/setup.test.sh
bash -n /bootstrap/setup.sh

mkdir -p /fixture/oracle-init /test-bin /etc/apt/sources.list.d /etc/systemd/system
cat > /fixture/docker-compose.yml <<'COMPOSE'
services:
  oracle-db:
    image: oracle-test-fixture
    environment:
      ORACLE_PASSWORD: ${ORACLE_PASSWORD:?ORACLE_PASSWORD must be set}
      APP_USER: ${APP_USER:-photoalbum}
      APP_USER_PASSWORD: ${APP_USER_PASSWORD:?APP_USER_PASSWORD must be set}
  photoalbum-java-app:
    image: app-test-fixture
    environment:
      SPRING_DATASOURCE_PASSWORD: ${APP_USER_PASSWORD:?APP_USER_PASSWORD must be set}
      APP_ADMIN_PASSWORD: ${APP_ADMIN_PASSWORD:?APP_ADMIN_PASSWORD must be set}
COMPOSE
printf '.env\n' > /fixture/.gitignore
printf '#!/bin/bash\n' > /fixture/oracle-init/create-user.sh
git -C /fixture init --quiet
git -C /fixture add .
git -C /fixture -c user.name=BootstrapTest -c user.email=test@example.invalid \
    commit --quiet -m "Create offline application fixture"

# Stub VM provisioning boundaries; keep the actual script, RNG and Compose parser.
for command in apt-get usermod lsb_release dpkg ora2pg psql; do
    printf '#!/bin/sh\nprintf "test-fixture\\n"\n' > "/test-bin/$command"
done
cat > /test-bin/systemctl <<'SYSTEMCTL'
#!/bin/sh
printf '%s\n' "$*" >> /tmp/systemctl-actions
SYSTEMCTL
cat > /test-bin/curl <<'CURL'
#!/bin/sh
printf 'test-fixture\n'
CURL
cat > /test-bin/gpg <<'GPG'
#!/bin/sh
overwrite=false
while [ "$1" != -o ]; do
    if [ "$1" = --yes ]; then overwrite=true; fi
    shift
done
if [ -e "$2" ] && [ "$overwrite" = false ]; then
    echo "gpg: refusing to overwrite an existing keyring noninteractively" >&2
    exit 1
fi
cat > "$2"
GPG
printf '#!/bin/sh\nexit 1\n' > /test-bin/wget
cat > /test-bin/git <<'GIT'
#!/bin/sh
if [ "$1" = clone ]; then
    exec /usr/bin/git clone --quiet /fixture "$3"
fi
exec /usr/bin/git "$@"
GIT
cat > /test-bin/docker <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == --version ]]; then
    exec /usr/local/bin/docker "$@"
fi
[[ "$1" == compose ]] || exit 1
shift
options=(compose)
while (( $# )); do
    case "$1" in
        config)
            exec /usr/local/bin/docker "${options[@]}" "$@"
            ;;
        pull|up|ps)
            printf '%s\n' "$1" >> /tmp/compose-actions
            /usr/local/bin/docker "${options[@]}" config --quiet
            exit 0
            ;;
        *)
            options+=("$1")
            shift
            ;;
    esac
done
exit 1
DOCKER
chmod +x /test-bin/*
export PATH="/test-bin:$PATH"

if ! bash -x /bootstrap/setup.sh > /tmp/bootstrap-output 2>&1; then
    cat /tmp/bootstrap-output >&2
    fail "fresh bootstrap must supply the required Compose credentials"
fi

[[ -f /opt/photoalbum/.env ]] || fail "environment file was not created"
[[ "$(stat -c '%a %u:%g' /opt/photoalbum/.env)" == '600 0:0' ]] \
    || fail "environment file must be accessible only to root"

mapfile -t passwords < <(grep -E '^(ORACLE_PASSWORD|APP_USER_PASSWORD|APP_ADMIN_PASSWORD)=' \
    /opt/photoalbum/.env | cut -d= -f2-)
[[ "${#passwords[@]}" == 3 ]] || fail "all three passwords must be present"
for password in "${passwords[@]}"; do
    [[ "$password" =~ ^[0-9a-f]{30}$ ]] || fail "password must contain 120 random bits in Oracle-compatible hex"
    if grep -Fq "$password" /tmp/bootstrap-output /var/log/photoalbum-setup.log; then
        fail "password appeared in bootstrap logs"
    fi
done
[[ "${passwords[0]}" != "${passwords[1]}" && "${passwords[0]}" != "${passwords[2]}" \
    && "${passwords[1]}" != "${passwords[2]}" ]] || fail "passwords must be independent"
grep -qx up /tmp/compose-actions || fail "Compose startup was not reached"
grep -qx 'enable photoalbum.service' /tmp/systemctl-actions || fail "reboot persistence was not enabled"
echo "PASS: fresh bootstrap creates protected credentials and reaches service installation"

cp /opt/photoalbum/.env /tmp/env-before-rerun
printf 'keep this file\n' > /opt/photoalbum/local-file
chmod 644 /opt/photoalbum/.env
if ! bash -x /bootstrap/setup.sh > /tmp/bootstrap-rerun-output 2>&1; then
    fail "bootstrap must support a rerun with existing credentials"
fi
cmp -s /tmp/env-before-rerun /opt/photoalbum/.env || fail "rerun rotated existing credentials"
[[ -f /opt/photoalbum/local-file ]] || fail "rerun deleted the existing checkout"
[[ "$(stat -c '%a %u:%g' /opt/photoalbum/.env)" == '600 0:0' ]] \
    || fail "rerun must restore root-only permissions"
for password in "${passwords[@]}"; do
    if grep -Fq "$password" /tmp/bootstrap-rerun-output /var/log/photoalbum-setup.log; then
        fail "password appeared in traced bootstrap logs"
    fi
done
echo "PASS: rerun preserves the checkout and passwords without leaking them under tracing"

printf '#!/bin/sh\nexit 0\n' > /test-bin/sleep
cat > /test-bin/sqlplus <<'SQLPLUS'
#!/usr/bin/env bash
set -euo pipefail
sql=$(cat)
[[ "$*" == '-s / as sysdba' ]] || exit 1
[[ "$sql" == *'ALTER SESSION SET CONTAINER = FREEPDB1;'* ]] || exit 1
[[ "$sql" == *"CREATE USER \"CUSTOMUSER\" IDENTIFIED BY \"${APP_USER_PASSWORD}\""* ]] || exit 1
[[ "$sql" == *'WHENEVER SQLERROR EXIT SQL.SQLCODE'* ]] || exit 1
touch /tmp/oracle-credentials-used
SQLPLUS
chmod +x /test-bin/sleep /test-bin/sqlplus
if ! env APP_USER=customuser APP_USER_PASSWORD="${passwords[1]}" \
    bash /opt/photoalbum/oracle-init/create-user.sh > /tmp/oracle-init-output 2>&1; then
    fail "Oracle initializer must use the configured schema credentials"
fi
[[ -f /tmp/oracle-credentials-used ]] || fail "Oracle initializer still uses hard-coded credentials"
if grep -Fq "${passwords[1]}" /tmp/oracle-init-output; then
    fail "Oracle initializer logged the schema password"
fi
echo "PASS: Oracle initializer uses the configured user/password without credentials in process arguments"
shellcheck --severity=error /opt/photoalbum/oracle-init/create-user.sh
bash -n /opt/photoalbum/oracle-init/create-user.sh

printf '#!/bin/sh\nexit 19\n' > /test-bin/sqlplus
if env APP_USER_PASSWORD="${passwords[1]}" \
    bash /opt/photoalbum/oracle-init/create-user.sh > /tmp/oracle-failure-output 2>&1; then
    fail "Oracle initialization failure must propagate to the container entrypoint"
fi
echo "PASS: Oracle initialization failures are not reported as success"

sed -i 's/^ORACLE_PASSWORD=.*/ORACLE_PASSWORD=/' /opt/photoalbum/.env
cp /opt/photoalbum/.env /tmp/invalid-env
: > /tmp/compose-actions
if bash /bootstrap/setup.sh > /tmp/invalid-env-output 2>&1; then
    fail "an empty existing password must fail validation instead of being replaced"
fi
cmp -s /tmp/invalid-env /opt/photoalbum/.env || fail "invalid existing credentials were overwritten"
grep -q 'ORACLE_PASSWORD must be set' /tmp/invalid-env-output || fail "missing credentials were not reported"
[[ ! -s /tmp/compose-actions ]] || fail "invalid credentials must be rejected before pulling or starting services"
cp /tmp/env-before-rerun /opt/photoalbum/.env
echo "PASS: invalid existing credentials fail explicitly before any service action"

rm /opt/photoalbum/.env
cat > /test-bin/openssl <<'OPENSSL'
#!/bin/sh
if [ -f /tmp/rng-called ]; then
    echo "simulated random generator failure" >&2
    exit 1
fi
touch /tmp/rng-called
exec /usr/bin/openssl "$@"
OPENSSL
chmod +x /test-bin/openssl
: > /tmp/compose-actions
if bash -x /bootstrap/setup.sh > /tmp/rng-failure-output 2>&1; then
    fail "random generator failure must stop bootstrap"
fi
[[ ! -e /opt/photoalbum/.env ]] || fail "random generator failure left a partial environment file"
[[ ! -s /tmp/compose-actions ]] || fail "random generator failure must stop service actions"
grep -q 'simulated random generator failure' /tmp/rng-failure-output || fail "RNG failure was not reported"
rm /test-bin/openssl
echo "PASS: RNG failure stops bootstrap without writing partial credentials"

if ! bash -x /bootstrap/setup.sh > /tmp/second-creation-output 2>&1; then
    fail "bootstrap must recover after a random generator failure"
fi
if cmp -s /tmp/env-before-rerun /opt/photoalbum/.env; then
    fail "separate credential creation reused the same passwords"
fi
while IFS='=' read -r name value; do
    if [[ "$name" == *_PASSWORD ]]; then
        if grep -Fq "$value" /tmp/second-creation-output /var/log/photoalbum-setup.log; then
            fail "credential generation leaked a password under tracing"
        fi
    fi
done < /opt/photoalbum/.env
echo "PASS: separate credential creation generates new passwords without trace leakage"
