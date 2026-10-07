# Znuny Docker Architecture and Maintenance

Current implementation: **Znuny 7.3.7**, **Debian 13 (Trixie)** and
**znuny-base:2.0**. This document replaces the original Znuny 7.2 implementation
plan and describes the implemented setup. See [README.md](README.md) for usage.

## Components and decisions

| Component | Implementation |
|---|---|
| Base image | `znuny/Dockerfile.base`: `debian:13-slim`, published as `ghcr.io/ckbaker10/znuny-base:2.0` |
| Application | `znuny/Dockerfile`: versioned source tarball, selected by `ZNUNY_VERSION` build argument |
| Default version | `7.3.7` in Compose and `.env.example`; CI derives the version from the `v*` tag |
| Database | Official `mariadb:10.11` image; server options in Compose, no custom MariaDB build |
| Web server | Apache 2 with `mod_perl` and `mpm_prefork` |
| Processes | Supervisord runs Apache, cron and rsyslog; entrypoint starts the Znuny daemon outside installer mode |
| Published architecture | `linux/amd64` in both workflows; ARM64 is not built by CI |
| HTTP binding | `127.0.0.1:${ZNUNY_HTTP_PORT:-8080}:80`; remote access requires a host reverse proxy |

## Repository map

- [Application Dockerfile](znuny/Dockerfile) downloads `znuny-${ZNUNY_VERSION}.tar.gz`,
  creates the `znuny` user in `www-data`, configures Apache and stages Kernel/skins.
- [Base Dockerfile](znuny/Dockerfile.base) installs system and Perl dependencies.
  `Net::SAML2` and `Jq` come from CPAN; crypto modules come from Debian packages.
  CPAN build tools and temporary files are removed afterwards. See
  [base image maintenance](znuny/README.base.md).
- [Entrypoint](znuny/entrypoint.sh), [helpers](znuny/functions.sh),
  [logging utilities](znuny/util_functions.sh) and [backup script](znuny/znuny_backup.sh)
  implement startup, configuration, migrations and backups.
- [Compose](docker-compose.yml) defines the application and MariaDB services;
  [.env.example](.env.example) lists configuration defaults. There is no checked-in
  `docker-compose.override.yml` or `mariadb/` directory.
- [E2E acceptance test](tests/e2e/run.sh) builds locally with Podman and tests
  installation of 7.3.1 followed by upgrade to the configured target version.
- [SAML guide](README-SAML.md) and [configuration example](Config.pm.saml-example)
  cover optional authentication.

## Startup and persistence

All modes wait for MariaDB. `ZNUNY_INSTALL=yes` prepares files and permissions
for the web installer; the daemon stays stopped until a restart in normal mode.
`restore` restores the selected backup and starts services; this branch does not
run the normal version-change migration. Use backups compatible with the target
version and follow the migration guidance in [README.md](README.md).

In normal mode (`no`), the image's first-start marker triggers `load_defaults`.
On a genuine first installation it prepares `Config.pm`, loads the schema if
the Znuny `valid` table is absent and sets the supplied admin password. Existing
installations keep their admin password. On a recorded version change it syncs
Kernel/skins, runs the target series migration and upgrades add-ons.

On every normal start, Kernel synchronization refreshes standard files while
preserving `Config.pm`, `current_version` and `sp.key`; skins and backup cron are
recreated, permissions and add-ons are handled, configuration is rebuilt and cache
is cleared. The version marker is
`volumes/config/current_version`; these mechanics do not establish support for
arbitrary cross-series migrations.

Compose persists Kernel configuration, article attachments, backups, add-ons and
MariaDB data under `volumes/`. Runtime data and `.env` are ignored by Git.
MariaDB uses utf8mb4 and 256 MB packet/log settings. The Debian 13 client disables
TLS for the bundled database service, which is configured without TLS.

## Build, release and validation

The [base workflow](.github/workflows/build-base.yml) runs on `base-v*` tags and
requires a matching application `FROM` line. It publishes only the versioned
base tag. Publish a changed base before the application tag that depends on it.
The [application workflow](.github/workflows/build-push.yml) runs on `v*` tags
and publishes the application version and `latest`. Both use `GITHUB_TOKEN`,
Buildx and GitHub Actions cache. Neither builds a MariaDB image.

Before an image release, run `tests/e2e/run.sh` with rootless Podman; it tests
schema initialization, correct and incorrect admin logins, required Perl modules,
daemon startup, ticket creation and ticket persistence after the patch upgrade.
The mandatory [release acceptance suite](tests/migration/README.md) additionally
tests synthetic fullbackup migrations from 7.1.3 (filesystem attachments) and
7.2.3 (database attachments), including required intermediate stages and
ticket/article/attachment integrity. Both image publishing workflows require
this suite and the patch E2E to pass before publishing. Complete IdP login,
custom add-ons and custom migration layouts require separate tests.

Maintenance must keep this document, README, SAML guide, base README and examples
consistent with Dockerfiles, Compose, scripts and workflows. Retain old versions
only where they explain an explicitly historical transition or supported source
version. Review local links and executable examples before committing.
