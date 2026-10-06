#!/usr/bin/env bash
# End-to-end acceptance test for the Znuny image.
#
# Builds the base image and two Znuny versions locally, then in an isolated
# compose project:
#   1. fresh install of E2E_FROM_VERSION (schema, config, admin login, ticket)
#   2. upgrade of the same volumes to E2E_TO_VERSION (migration, data kept)
# Nothing is pushed; everything is removed afterwards unless E2E_KEEP=1.
#
# Usage: tests/e2e/run.sh
# Environment (all optional):
#   E2E_FROM_VERSION  version for the fresh install   (default: 7.3.1)
#   E2E_TO_VERSION    version to upgrade to           (default: ZNUNY_VERSION in .env.example)
#   E2E_BASE_IMAGE    use this base image instead of building znuny/Dockerfile.base
#   E2E_ENGINE        container engine                (default: podman)
#   E2E_COMPOSE       compose command                 (default: podman-compose)
#   E2E_PROJECT       compose project name            (default: znuny-e2e)
#   E2E_PORT          host port for the web UI        (default: 18080)
#   E2E_TIMEOUT       seconds to wait for startup     (default: 600)
#   E2E_KEEP          1 = keep stack and work dir for debugging

set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
ENGINE=${E2E_ENGINE:-podman}
read -r -a COMPOSE <<<"${E2E_COMPOSE:-podman-compose}"
PROJECT=${E2E_PROJECT:-znuny-e2e}
PORT=${E2E_PORT:-18080}
TIMEOUT=${E2E_TIMEOUT:-600}
FROM_VERSION=${E2E_FROM_VERSION:-7.3.1}
TO_VERSION=${E2E_TO_VERSION:-$(sed -n 's/^ZNUNY_VERSION=//p' "$REPO/.env.example")}
IMAGE=localhost/${PROJECT}-znuny
BASE_IMAGE=${E2E_BASE_IMAGE:-localhost/${PROJECT}-base:local}
URL=http://127.0.0.1:${PORT}/znuny
ADMIN_PASSWORD=e2e-$(date +%s)
TICKET_TITLE="e2e ticket $$"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT}.XXXXXX")
FAILURES=0

log() { printf '\n== %s\n' "$*"; }
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

compose() {
    (cd "$WORK" && "${COMPOSE[@]}" -p "$PROJECT" -f docker-compose.yml -f e2e.override.yml "$@")
}

container() {
    "$ENGINE" ps -q \
        --filter "label=com.docker.compose.project=$PROJECT" \
        --filter "label=com.docker.compose.service=znuny" | head -n 1
}

as_znuny() {
    "$ENGINE" exec -i "$(container)" su -s /bin/bash -c "$1" znuny
}

cleanup() {
    local rc=$?
    if [ "${E2E_KEEP:-0}" = "1" ]; then
        echo "E2E_KEEP=1: stack '$PROJECT' and $WORK kept"
        return "$rc"
    fi
    compose down >/dev/null 2>&1 || true
    # podman-compose down keeps the network it created
    "$ENGINE" network rm "${PROJECT}_default" >/dev/null 2>&1 || true
    # Volume files belong to container UIDs; remove them from inside a container.
    "$ENGINE" run --rm -v "$WORK:/work" docker.io/library/debian:13-slim \
        rm -rf /work/volumes >/dev/null 2>&1 || true
    rm -rf "$WORK"
    return "$rc"
}
trap cleanup EXIT

build_images() {
    if [ -z "${E2E_BASE_IMAGE:-}" ]; then
        log "Building base image $BASE_IMAGE"
        "$ENGINE" build -q -f "$REPO/znuny/Dockerfile.base" -t "$BASE_IMAGE" "$REPO/znuny" >/dev/null
    fi
    local version
    for version in "$FROM_VERSION" "$TO_VERSION"; do
        log "Building $IMAGE:$version"
        "$ENGINE" build -q --from "$BASE_IMAGE" --build-arg "ZNUNY_VERSION=$version" \
            -t "$IMAGE:$version" "$REPO/znuny" >/dev/null
    done
}

prepare_workdir() {
    cp "$REPO/docker-compose.yml" "$WORK/"
    sed -e "s/^ZNUNY_HTTP_PORT=.*/ZNUNY_HTTP_PORT=$PORT/" \
        -e 's/^ZNUNY_BACKUP_TIME=.*/ZNUNY_BACKUP_TIME=disable/' \
        "$REPO/.env.example" >"$WORK/.env"
    printf 'ZNUNY_ROOT_PASSWORD=%s\n' "$ADMIN_PASSWORD" >>"$WORK/.env"
    cat >"$WORK/e2e.override.yml" <<EOF
services:
  znuny:
    image: $IMAGE:\${ZNUNY_VERSION}
EOF
    mkdir -p "$WORK"/volumes/{config,article,backups,addons,mysql}
}

start_version() {
    local version=$1 waited=0 id
    sed -i "s/^ZNUNY_VERSION=.*/ZNUNY_VERSION=$version/" "$WORK/.env"
    ZNUNY_VERSION=$version compose up -d >"$WORK/up-$version.log" 2>&1
    while :; do
        id=$(container)
        if [ -n "$id" ] && "$ENGINE" logs "$id" 2>&1 | grep -c "Znuny $version is ready\." >/dev/null; then
            pass "Znuny $version started"
            return 0
        fi
        if [ -n "$id" ] && [ "$("$ENGINE" inspect -f '{{.State.Running}}' "$id")" != "true" ]; then
            break
        fi
        [ "$waited" -ge "$TIMEOUT" ] && break
        sleep 5
        waited=$((waited + 5))
    done
    fail "Znuny $version did not become ready; last log lines:"
    [ -n "$id" ] && "$ENGINE" logs --tail 30 "$id" 2>&1 | sed 's/^/      /'
    exit 1
}

stop_stack() {
    compose stop >/dev/null 2>&1
    compose down >/dev/null 2>&1
}

check_release() {
    local version=$1 release
    release=$(as_znuny 'sed -n "s/^VERSION = //p" /opt/znuny/RELEASE')
    [ "$release" = "$version" ] && pass "RELEASE is $version" || fail "RELEASE is '$release', expected $version"
}

check_no_errors_after_ready() {
    local count
    count=$("$ENGINE" logs "$(container)" 2>&1 | sed -n '/is ready\./,$p' | grep -c 'ERROR' || true)
    [ "$count" -eq 0 ] && pass "no errors logged after startup" || fail "$count error lines after startup"
}

check_database() {
    as_znuny '/opt/znuny/bin/znuny.Console.pl Maint::Database::Check' 2>&1 | grep -c 'Connection successful' >/dev/null \
        && pass "Maint::Database::Check connects" || fail "Maint::Database::Check failed"
}

check_modules() {
    local output missing found
    output=$(as_znuny 'cd /opt/znuny && perl bin/znuny.CheckModules.pl' 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    missing=$(grep -E 'Not installed|failed' <<<"$output" | grep -v optional || true)
    found=$(grep -cE '\.\.\.ok' <<<"$output" || true)
    # About 50 modules are checked; far fewer "ok" lines means the check itself broke.
    if [ -z "$missing" ] && [ "$found" -ge 30 ]; then
        pass "all required Perl modules present ($found ok)"
    else
        fail "Perl module check: $found ok, missing: ${missing:-?}"
    fi
    as_znuny 'perl -MNet::SAML2 -MJq -MCrypt::JWT -e1' >/dev/null 2>&1 \
        && pass "SAML/JWT/Jq modules load" || fail "SAML/JWT/Jq modules do not load"
}

check_daemon() {
    as_znuny '/opt/znuny/bin/znuny.Daemon.pl status' 2>&1 | grep -ci 'running' >/dev/null \
        && pass "Znuny daemon running" || fail "Znuny daemon not running"
}

check_login() {
    local jar code body
    jar=$(mktemp)
    curl -s -c "$jar" -b "$jar" -o /dev/null "$URL/index.pl"
    # A successful login answers with a redirect and a session cookie.
    code=$(curl -s -c "$jar" -b "$jar" -o /dev/null -w '%{http_code}' \
        --data-urlencode Action=Login --data-urlencode User=root@localhost \
        --data-urlencode "Password=$ADMIN_PASSWORD" "$URL/index.pl")
    body=$(curl -s -c "$jar" -b "$jar" "$URL/index.pl")
    rm -f "$jar"
    if [ "$code" = 302 ] && grep -q 'Action=Logout' <<<"$body"; then
        pass "agent login as root@localhost"
    else
        fail "agent login failed (HTTP $code)"
    fi
    code=$(curl -s -o /dev/null -w '%{http_code}' --data-urlencode Action=Login \
        --data-urlencode User=root@localhost --data-urlencode Password=wrong "$URL/index.pl")
    [ "$code" = 200 ] && pass "wrong password rejected" || fail "wrong password: HTTP $code"
    [ "$(curl -s -o /dev/null -w '%{http_code}' "$URL/customer.pl")" = 200 ] \
        && pass "customer interface answers" || fail "customer interface does not answer"
}

ticket_perl() {
    # $1: perl code using $Ticket; runs with the Znuny object manager.
    as_znuny "cd /opt/znuny && perl -I/opt/znuny -I/opt/znuny/Kernel/cpan-lib -e '
        use Kernel::System::ObjectManager;
        local \$Kernel::OM = Kernel::System::ObjectManager->new();
        my \$Ticket = \$Kernel::OM->Get(\"Kernel::System::Ticket\");
        $1'"
}

create_ticket() {
    local id
    id=$(ticket_perl "print \$Ticket->TicketCreate(Title => \"$TICKET_TITLE\", Queue => \"Raw\",
        Lock => \"unlock\", Priority => \"3 normal\", State => \"new\", CustomerNo => \"e2e\",
        CustomerUser => \"e2e\@example.com\", OwnerID => 1, UserID => 1) // q{};" 2>/dev/null)
    [[ "$id" =~ ^[0-9]+$ ]] && pass "ticket created (id $id)" || fail "ticket creation failed: $id"
}

check_ticket() {
    local count
    count=$(ticket_perl "print scalar \$Ticket->TicketSearch(Result => \"COUNT\",
        Title => \"$TICKET_TITLE\", UserID => 1);" 2>/dev/null)
    [ "$count" = 1 ] && pass "ticket '$TICKET_TITLE' present" || fail "ticket not found (count '$count')"
}

check_migration_log() {
    "$ENGINE" logs "$(container)" 2>&1 | grep -c 'Patch level migration complete' >/dev/null \
        && pass "patch level migration ran" || fail "patch level migration did not run"
}

main() {
    echo "Znuny e2e: $FROM_VERSION -> $TO_VERSION (project $PROJECT, port $PORT, work $WORK)"
    build_images
    prepare_workdir

    log "Fresh install of $FROM_VERSION"
    start_version "$FROM_VERSION"
    check_release "$FROM_VERSION"
    check_database
    check_modules
    check_daemon
    check_login
    create_ticket
    check_ticket
    check_no_errors_after_ready
    stop_stack

    if [ "$TO_VERSION" != "$FROM_VERSION" ]; then
        log "Upgrade to $TO_VERSION"
        start_version "$TO_VERSION"
        check_release "$TO_VERSION"
        check_migration_log
        check_database
        check_modules
        check_daemon
        check_login
        check_ticket
        check_no_errors_after_ready
    fi

    log "Result"
    if [ "$FAILURES" -eq 0 ]; then
        echo "All checks passed."
    else
        echo "$FAILURES check(s) failed."
        exit 1
    fi
}

main "$@"
