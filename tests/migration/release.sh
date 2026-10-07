#!/usr/bin/env bash
# Mandatory release acceptance: synthetic backup migrations and patch E2E.
# Optional RELEASE_BASE_IMAGE uses a locally built candidate base (base release).
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO"
TARGET_VERSION=${1:-$(sed -n 's/^ZNUNY_VERSION=//p' .env.example)}
if [[ ! "$TARGET_VERSION" =~ ^7\.3\.[0-9]+$ ]]; then
    echo 'Extend migration stages/tests before releasing a new minor series.' >&2
    exit 1
fi
BASE_IMAGE=${RELEASE_BASE_IMAGE:-$(awk '/^FROM / { print $2; exit }' znuny/Dockerfile)}
TARGET_IMAGE=localhost/znuny-migration-test:${TARGET_VERSION}
mkdir -p work
for version in 7.1.3 7.2.3 "$TARGET_VERSION"; do
    podman build --from "$BASE_IMAGE" --build-arg "ZNUNY_VERSION=$version" \
        -t "localhost/znuny-migration-test:$version" znuny
done
# Host wall clock, never container time.
started=$(date +%s)
python3 tests/migration/run.py --case 7.1.3 --storage ArticleStorageFS \
    --target "$TARGET_VERSION" --target-image "$TARGET_IMAGE" --port 18091 &
pid71=$!
python3 tests/migration/run.py --case 7.2.3 --storage ArticleStorageDB \
    --target "$TARGET_VERSION" --target-image "$TARGET_IMAGE" --port 18092 &
pid72=$!
failed=0
wait "$pid71" || failed=1
wait "$pid72" || failed=1
if [ "$failed" -ne 0 ]; then
    echo 'Backup migration acceptance failed; release blocked.' >&2
    exit 1
fi
E2E_BASE_IMAGE="$BASE_IMAGE" E2E_PROJECT="znuny-release-$$" E2E_PORT=18093 \
    E2E_FROM_VERSION=7.3.1 E2E_TO_VERSION="$TARGET_VERSION" TMPDIR="$REPO/work" \
    bash tests/e2e/run.sh
echo "Release acceptance passed for $TARGET_VERSION in $(($(date +%s) - started)) host seconds."
