# Synthetic backup migration acceptance test

## Mandatory release acceptance

Before creating a release tag, run the complete suite for the candidate version:

```bash
bash tests/migration/release.sh 7.3.7
```

Replace 7.3.7 with the proposed 7.3.x release. The wrapper builds local images
from the checkout, tests both backup migrations, then runs the existing
7.3.1 patch-update E2E. It publishes nothing. A failed or missing case blocks
the release. For a changed base, build it locally and set `RELEASE_BASE_IMAGE`
to that fully qualified local image before invoking the wrapper.

Both publishing workflows require the reusable `migration-checks.yml` workflow
to succeed first. Base releases test a base built from the current checkout;
application releases test the version from the proposed tag. Only synthetic
`result.json` summaries are uploaded, never backups, environment files or raw
logs. Extending a new minor series requires adding its intermediate migration
stages and cases; targets outside 7.3.x are rejected until that work is done.

## Running an individual case

Run from the repository root as the normal rootless Podman user. Requirements:
Python 3 (standard library only), Podman and podman-compose. The test uses the
project Compose services, isolated project names and localhost port 18091/18092.
It does not use production data, send mail or contact an identity provider.

Build the two source/intermediate images using this project's Dockerfile:

```bash
podman build --from ghcr.io/ckbaker10/znuny-base:2.0 \
  --build-arg ZNUNY_VERSION=7.1.3 -t localhost/znuny-migration-test:7.1.3 znuny
podman build --from ghcr.io/ckbaker10/znuny-base:2.0 \
  --build-arg ZNUNY_VERSION=7.2.3 -t localhost/znuny-migration-test:7.2.3 znuny
podman pull ghcr.io/ckbaker10/znuny:7.3.7
python3 tests/migration/run.py --case 7.1.3 --storage ArticleStorageFS
python3 tests/migration/run.py --case 7.2.3 --storage ArticleStorageDB --port 18092
```

For an unpublished candidate, pass `--target VERSION --target-image IMAGE`
to use its locally built image. The two cases can run concurrently on distinct
ports; the release wrapper waits for both and requires both to pass.

Each run creates a fresh source, sets a random synthetic admin password, creates
a ticket with an article and binary attachment, verifies the configured storage
backend, and takes a gzip fullbackup after stopping the application processes.
It imports that backup into a separate empty database and volumes and executes
the actual import/migration Bash blocks from [the project README](../../README.md).
Only the host container engine and Compose project/file selection are replaced.
The source configuration already uses the target Home path `/opt/znuny`.

Success requires preserved ticket/article IDs, article body and attachment
bytes/SHA-256, the same storage backend, preserved admin login, working target
database and daemon, and matching RELEASE/version marker. Migration commands
must exit successfully and print `Migration completed!`.

All command output, synthetic backups, database volumes, source fixture results,
backup hashes and `result.json` remain under an ignored `work/migration-*`
directory. A failure identifies its local log; raw logs are not printed to chat.
Only containers and networks with the run's own project labels are removed on
exit. Test images and runtime artifacts remain for reproduction and diagnosis.

These two cases cover standard MySQL/MariaDB installations without add-ons.
They do not validate PostgreSQL conversion, custom external article paths,
custom Kernel/skin migration, actual SAML/IdP login or a production cutover.
