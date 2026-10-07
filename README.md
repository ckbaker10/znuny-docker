# znuny-docker

> This project was built with AI assistance — see [AI_DISCLAIMER.md](AI_DISCLAIMER.md) for details.

Dockerised [Znuny 7.3](https://www.znuny.org) based on **Debian 13 (Trixie)**.

The configured default is **Znuny 7.3.7**, using **znuny-base:2.0** and the
official **MariaDB 10.11** image. Both image workflows publish **linux/amd64**.

Images are published to the GitHub Container Registry on every version tag push.

```
ghcr.io/ckbaker10/znuny:<version>
```

---

## Quick Start

```bash
# 1. Copy and edit the environment file
cp .env.example .env
# Edit .env — at minimum change the passwords

# 2. Create volume directories
mkdir -p volumes/{config,article,backups,addons,mysql}

# 3. Start the stack
docker compose up -d

# 4. Open Znuny in your browser
open http://localhost:8080/znuny
```

Default admin credentials: **root@localhost** / value of `ZNUNY_ROOT_PASSWORD` (default: `changeme`).

---

## Repository Structure

```
znuny-docker/
├── .github/workflows/build-push.yml   # CI/CD — builds & pushes images on v* tags
├── znuny/
│   ├── Dockerfile                     # Main Znuny image (Debian 13)
│   ├── Dockerfile.base                # Base image: packages and Perl modules
│   ├── entrypoint.sh                  # Container startup logic
│   ├── functions.sh                   # Helper functions
│   ├── util_functions.sh              # Logging utilities
│   ├── znuny_backup.sh                # Automated backup script (called by cron)
│   └── etc/supervisord/znuny.conf     # Supervisord program definitions
├── tests/e2e/run.sh                   # End-to-end acceptance test (Podman)
├── docker-compose.yml                 # Main stack
├── .env.example                       # All supported variables with descriptions
└── Planning.md                        # Architecture decisions and implementation plan
```

---

## Startup Modes

Set the `ZNUNY_INSTALL` environment variable to choose the startup mode.

| `ZNUNY_INSTALL` | Behaviour |
|---|---|
| `no` (default) | Auto-configure, initialise the database, start all services |
| `yes` | Launch the web installer — daemon does **not** start until mode is switched to `no` |
| `restore` | Restore the backup specified by `ZNUNY_BACKUP_DATE` |

### Web Installer Mode (`ZNUNY_INSTALL=yes`)

Use this mode when you want full control over the initial configuration via the browser UI.

```bash
# 1. Set installer mode in .env
ZNUNY_INSTALL=yes

# 2. Start the stack
docker compose up -d

# 3. Open the installer in your browser and complete all steps
#    https://<hostname>/znuny/installer.pl

# 4. After the installer finishes, switch to normal mode
#    Edit .env:
ZNUNY_INSTALL=no

# 5. Restart the container — daemon and cron will now start
docker compose up -d
```

> **Note:** The Znuny daemon does not start while `ZNUNY_INSTALL=yes` because
> `Config.pm` has no database configuration until the installer writes it.
> Always restart with `ZNUNY_INSTALL=no` after completing the web installer.

---

## Environment Variables

See [`.env.example`](.env.example) for the full reference with descriptions and defaults.

### Essential variables to change

| Variable | Description |
|---|---|
| `ZNUNY_ROOT_PASSWORD` | Znuny admin (`root@localhost`) password |
| `ZNUNY_HOSTNAME` | Fully-qualified hostname shown in Znuny (e.g. `znuny.example.com`) |
| `ZNUNY_DB_PASSWORD` | Znuny application database password |
| `MYSQL_ROOT_PASSWORD` | MariaDB root password |
| `GITHUB_REPOSITORY_OWNER` | Your GitHub username/org (used in image tags) |

---

## Volumes

| Host path | Container path | Purpose |
|---|---|---|
| `./volumes/config` | `/opt/znuny/Kernel` | Znuny configuration (`Config.pm` etc.) |
| `./volumes/article` | `/opt/znuny/var/article` | Article attachments (if using `ArticleStorageFS`) |
| `./volumes/backups` | `/var/znuny/backups` | Automated backup output |
| `./volumes/addons` | `/opt/znuny/addons` | Drop `.opm` addon files here for auto-install |
| `./volumes/mysql` | `/var/lib/mysql` | MariaDB data directory |

---

## Automated Backups

Backups run automatically via cron at the schedule defined by `ZNUNY_BACKUP_TIME`
(default: `0 4 * * *` — daily at 04:00). Backups are written to `./volumes/backups`
and files older than `ZNUNY_BACKUP_ROTATION` days (default: 30) are pruned automatically.

To disable backups:
```env
ZNUNY_BACKUP_TIME=disable
```

---

## Restoring a Backup

For the offline volume snapshot created by this project's update procedure, use
[the patch-update rollback commands](#3-roll-back-with-both-the-old-image-and-the-old-data).
They restore the database files and matching configuration together.

For a Znuny `backup.pl` fullbackup, use the [migration/import procedure below](#migrating-an-existing-znuny-71--72--73-system-to-this-stack),
starting at step 2 with a fresh target. Copy the complete timestamp directory
from `volumes/backups` to the new target as `volumes/backups/source`. Select the
matching row for the backup's source version, then run steps 3–5. This also
covers restoring a 7.3 backup into the current 7.3.7 image.

`ZNUNY_INSTALL=restore` is a legacy alternative for compatible backups, not the
procedure used here. Its `ZNUNY_BACKUP_DATE` must be the exact existing directory
or filename (including `.tar.gz` for an archive). It can replace application
files from a fullbackup and starts services without the staged migration checks.

---

## Resetting the Admin Password

If the `root@localhost` password is unknown (e.g. after running the web installer),
reset it directly inside the running container:

```bash
docker exec -it znuny-docker-znuny-1 \
  su -c "/opt/znuny/bin/znuny.Console.pl Admin::User::SetPassword root@localhost 'YourNewPassword'" \
  -s /bin/bash znuny
```

The change takes effect immediately — no restart required.

---

## Installing Addons

Place `.opm` addon files in `./volumes/addons/`. They are automatically installed
at container startup. Successfully installed addons are moved to
`./volumes/addons/installed/`.

---

## SMTP Configuration

```env
ZNUNY_SENDMAIL_MODULE=SMTP
ZNUNY_SMTP_SERVER=smtp.example.com
ZNUNY_SMTP_PORT=587
ZNUNY_SMTP_USERNAME=user@example.com
ZNUNY_SMTP_PASSWORD=secret
```

---

## Building the Images Locally

```bash
# Build the Znuny image (MariaDB uses an official pre-built image)
docker compose build

# Build with a specific Znuny version
docker compose build --build-arg ZNUNY_VERSION=7.3.7
```

The Znuny image builds on `ghcr.io/ckbaker10/znuny-base` (see
[znuny/README.base.md](znuny/README.base.md)). To test changes to
`Dockerfile.base` before publishing it, build the base locally and pass it
with `--from` (Podman/Buildah), as the end-to-end test does.

---

## End-to-End Acceptance Test

`tests/e2e/run.sh` builds the base image and two Znuny versions locally with
Podman and checks, in an isolated compose project (`znuny-e2e`, port 18080):

1. fresh install of the older version: database schema and `Config.pm` are set
   up automatically, the admin password from `ZNUNY_ROOT_PASSWORD` works, a
   wrong one is rejected, required Perl modules (incl. SAML, JWT, Jq) are
   present, the daemon runs, a ticket can be created
2. upgrade of the same volumes to the newer version: patch level migration
   runs, the ticket is still there, login and daemon still work

```bash
tests/e2e/run.sh                               # 7.3.1 -> ZNUNY_VERSION from .env.example
E2E_FROM_VERSION=7.3.6 E2E_TO_VERSION=7.3.7 tests/e2e/run.sh
E2E_KEEP=1 tests/e2e/run.sh                    # keep the stack for debugging
```

Requirements: `podman`, `podman-compose` and `curl`. Nothing is pushed, and
all containers, networks and volume data of the test are removed afterwards
(the locally built images stay). Further options are listed in the script
header. Run it before tagging a release.

---

## Publishing Images via GitHub Actions

Every release requires the [migration acceptance suite](tests/migration/README.md)
to pass against the proposed image. From this checkout, before creating a tag:

```bash
bash tests/migration/release.sh 7.3.7
```

Use the proposed release version. This builds local candidate images and checks
7.1.3 → 7.2.3 → target with filesystem attachments, 7.2.3 → target with database
attachments, and the existing 7.3.1 → target patch-update E2E. A failed or missing
case blocks the release. Both publishing workflows enforce this through a
required migration job. New minor series need extended intermediate stages and
tests before publishing is enabled.

If the base image changed, publish it first with a `base-v*` tag (see
[README.base.md](znuny/README.base.md)). Then push a version tag to trigger the
build-and-push workflow:

```bash
git tag v7.3.7
git push origin v7.3.7
```

This builds a `linux/amd64` image and pushes:

- `ghcr.io/<owner>/znuny:7.3.7`
- `ghcr.io/<owner>/znuny:latest`

The workflow requires **no additional secrets** — it uses the built-in `GITHUB_TOKEN`.

Make sure the repository has **"Read and write permissions"** enabled for Actions under:
`Settings → Actions → General → Workflow permissions`.

---

## Reverse Proxy (Apache)

Example host-side Apache virtual host with SSL termination and security headers.
Adjust `ServerName` and certificate paths to match your environment.

```apacheconf
<VirtualHost *:80>
    ServerName znuny.example.com
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName znuny.example.com

    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/your-cert.pem
    SSLCertificateKeyFile /etc/ssl/private/your-key.key

    # Security headers
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

    # Proxy to Znuny container (adjust port to match ZNUNY_HTTP_PORT)
    ProxyPreserveHost On
    ProxyPass        / http://127.0.0.1:8080/
    ProxyPassReverse / http://127.0.0.1:8080/
    ProxyTimeout 300

    ErrorLog  ${APACHE_LOG_DIR}/znuny_error.log
    CustomLog ${APACHE_LOG_DIR}/znuny_access.log combined
</VirtualHost>
```

Required Apache modules: `mod_rewrite`, `mod_ssl`, `mod_proxy`, `mod_proxy_http`, `mod_headers`.

```bash
a2enmod rewrite ssl proxy proxy_http headers
```

---

## Patch Level Updates (7.3.x → 7.3.7)

Run these commands in the checkout that owns the existing stack. The current
installation must already be 7.3.x. Schedule downtime and keep users, inbound
mail delivery and external jobs away from the stack until the checks below pass.

### 1. Record the old version, download the target and take an offline snapshot

```bash
set -e -o pipefail
docker compose exec -T znuny cat /opt/znuny/Kernel/current_version
docker compose exec -T znuny cat /opt/znuny/RELEASE
mkdir -p work/rollback
test ! -e work/rollback/pre-update.tar.gz
cp .env work/rollback/pre-update.env
sed -i 's/^ZNUNY_VERSION=.*/ZNUNY_VERSION=7.3.7/' .env
docker compose pull znuny
docker compose stop
tar --numeric-owner -czpf work/rollback/pre-update.tar.gz volumes
```

The archive includes configuration, attachments, add-ons and the stopped
MariaDB data directory. Run the archive commands with permission to read and
restore every file in `volumes/` (use `sudo tar` if your Docker-created
files require root). If pulling or archiving fails, stop here. Restore
`work/rollback/pre-update.env` to `.env` before restarting the old stack.
Keep both snapshot files private and copy them off-host. The `work/`
directory is ignored by Git. Use a new snapshot directory for later updates.

### 2. Start the database, then the target application

```bash
docker compose up -d mariadb
docker compose up -d --no-deps znuny
docker compose logs --tail=100 znuny
docker compose exec -T znuny cat /opt/znuny/Kernel/current_version
docker compose exec -T znuny cat /opt/znuny/RELEASE
docker compose exec -T znuny su -s /bin/bash -c \
  'cd /opt/znuny && bin/znuny.Daemon.pl status' znuny
curl -fsS -o /dev/null http://127.0.0.1:8080/znuny/index.pl
```

Use your configured `ZNUNY_HTTP_PORT` instead of 8080 if changed.
The new image's first-start marker triggers the version comparison against
`volumes/config/current_version`. On a difference, the entrypoint refreshes
Kernel files while keeping `Config.pm` and `sp.key`, runs
`scripts/MigrateToZnuny7_3.pl --verbose` and upgrades add-ons. Normal startup
then rebuilds configuration, clears cache and starts services. This automatic
path also starts background jobs, so keep external input blocked during checks.

Check the logs for **Migration completed!**, migration/package errors and
daemon failures. Both version checks must report 7.3.7. Log in with the existing
admin password, open an existing ticket and attachment, and create a test ticket.
Verify custom add-ons and SAML if used. The version marker alone is not proof
of success: the helper can write it even if a migration command failed.

If migration/package checks fail, stop the application and use the offline
migration and compatible package commands in
[step 4 below](#4-run-the-selected-target-migration-offline), or roll back.
Accept user/mail traffic only after the checks pass.

### 3. Roll back with both the old image and the old data

Before the target receives new production data, restore the stopped snapshot:

```bash
docker compose stop
test ! -e work/rollback/volumes-after-failure
mv volumes work/rollback/volumes-after-failure
tar --numeric-owner -xzpf work/rollback/pre-update.tar.gz
cp work/rollback/pre-update.env .env
docker compose up -d
docker compose logs --tail=100 znuny
```

Use the same permissions as for archiving. The failed-state volumes remain
available for diagnosis. Check the old version, login and attachments before
reopening traffic. Do not point the old image at a migrated database. If new
tickets or mail reached the target, reconcile those records before restoring
the snapshot.

---

## Migrating an Existing Znuny 7.1 / 7.2 / 7.3 System to This Stack

Run host-side commands from this repository directory. The procedure below is
for a **MySQL/MariaDB source**, gzip fullbackup and the standard article directory
`var/article` beneath the Znuny home. It uses the Compose services `znuny` and
`mariadb` and this project's `./volumes/` mounts. A PostgreSQL source or a custom
external article directory needs a separate data conversion/copy procedure;
do not use these commands for those layouts.

| Source version | First target image | Required migrations |
|---|---|---|
| 7.1.x | Locally built 7.2.3 | `MigrateToZnuny7_2.pl`, then 7.3.7 with `MigrateToZnuny7_3.pl` |
| 7.2.x | Published 7.3.7 | `MigrateToZnuny7_3.pl` |
| 7.3.x up to 7.3.7 | Published 7.3.7 | `MigrateToZnuny7_3.pl` |

Prepare compatible add-on packages for each target series before downtime.
The stages below keep the application stopped until migration completes.
The normal `restore` entrypoint is deliberately bypassed: it starts services
without running a cross-series migration, and a fullbackup can overwrite the
target application with source code.

### 1. Stop and back up the source

This source example assumes a Debian installation at `/opt/znuny`, Apache 2,
and Postfix as its local MTA. Run as root on the **source host**. If the home
directory differs, replace `/opt/znuny` in these commands; stop the actual source
MTA if it is not Postfix. Keep the source stopped through cutover.

```bash
set -e -o pipefail
systemctl stop apache2
systemctl stop postfix
su -s /bin/bash -c 'cd /opt/znuny && bin/Cron.sh stop && bin/znuny.Daemon.pl stop' znuny
install -d -o znuny -g www-data /var/znuny/migration-backup
su -s /bin/bash -c 'cd /opt/znuny && scripts/backup.pl -d /var/znuny/migration-backup -t fullbackup -c gzip' znuny
ls -1 /var/znuny/migration-backup
```

The last command lists timestamp directories. Copy the **complete selected
directory**, containing `Config.tar.gz`, `Application.tar.gz` and
`DatabaseBackup.sql.gz`, to the target host. In the following steps it is named
`./volumes/backups/source`: rename the copied timestamp directory to `source`.
Keep a second copy outside the target stack. This is a directory of archives,
not one archive named after a timestamp.

### 2. Prepare a fresh target and select the first image

Use a separate checkout with empty data directories. Do not import into an
existing production stack: the SQL dump and article files belong to the source.

```bash
set -e -o pipefail
test ! -e .env
test ! -e volumes/config
test ! -e volumes/mysql
cp .env.example .env
mkdir -p volumes/{config,article,backups,addons,mysql}
```

Edit `.env`: set `ZNUNY_DB_PASSWORD`, `MYSQL_ROOT_PASSWORD`,
`ZNUNY_HOSTNAME`, `ZNUNY_ARTICLE_STORAGE_TYPE` to match the source backend
(`ArticleStorageDB` or `ArticleStorageFS`), and SMTP settings. Keep
`ZNUNY_DB_HOST=mariadb`, `ZNUNY_DB_NAME=znuny`, `ZNUNY_DB_USER=znuny`.
Set `ZNUNY_INSTALL=no`, `ZNUNY_DISABLE_EMAIL_FETCH=yes`,
`ZNUNY_BACKUP_TIME=disable` and `ZNUNY_DEBUG=no` during migration.

For a **7.1 source**, set `ZNUNY_VERSION=7.2.3` in `.env` and build the
intermediate image with this repository's Dockerfile. This avoids assuming
that a 7.2.3 registry tag exists:

```bash
docker compose build znuny
```

For a **7.2 or 7.3 source**, set `ZNUNY_VERSION=7.3.7` and pull:

```bash
docker compose pull znuny
```

After copying the source backup directory to `volumes/backups/source`, verify
the three archives and start **only the database**:

```bash
test -f volumes/backups/source/Config.tar.gz
test -f volumes/backups/source/Application.tar.gz
test -f volumes/backups/source/DatabaseBackup.sql.gz
gzip -t volumes/backups/source/{Config.tar.gz,Application.tar.gz,DatabaseBackup.sql.gz}
docker compose up -d mariadb
```

### 3. Import the source data without starting the application

The following one-off container uses the selected image and the same persistent
volumes as the future service. It bypasses `/entrypoint.sh`. It copies the
target Kernel/skins, extracts the source `Config.pm`, generated `ZZZAAuto.pm`
and standard article directory, rewrites the database connection for Compose,
then imports SQL. The generated source settings are needed by the 7.2 migration;
do not rebuild the 7.2 configuration before its database migration. The migration
itself updates/deploys the settings in the required order.
It never extracts the complete old application onto the target.

```bash
docker compose run --rm --no-deps --entrypoint /bin/bash znuny -c '
  . /functions.sh
  set -e -o pipefail
  wait_for_db
  check_host_mount_dir
  check_custom_skins_dir
  backup=/var/znuny/backups/source
  tar -xzf "$backup/Config.tar.gz" -C /opt/znuny \
    Kernel/Config.pm Kernel/Config/Files/ZZZAAuto.pm
  tar -xzf "$backup/Application.tar.gz" -C /opt/znuny ./var/article
  set_permissions
'
```

Before the next command, edit `volumes/config/Config.pm`: set the Home assignment
to exactly `$Self->{Home} = '/opt/znuny';`. The project helper inserts the Compose
settings after this line. This edit is required if the source Home differs or
its assignment uses different quoting. The database fields are rewritten from
`.env` by the next command; do not start the service in between.

```bash
docker compose run --rm --no-deps --entrypoint /bin/bash znuny -c '
  . /functions.sh
  set -e -o pipefail
  wait_for_db
  add_config_value DatabaseHost "$ZNUNY_DB_HOST"
  add_config_value DatabasePort "$ZNUNY_DB_PORT"
  add_config_value Database "$ZNUNY_DB_NAME"
  add_config_value DatabaseUser "$ZNUNY_DB_USER"
  add_config_value DatabasePw "$ZNUNY_DB_PASSWORD" true
  add_config_value FQDN "$ZNUNY_HOSTNAME"
  create_db
  gzip -dc /var/znuny/backups/source/DatabaseBackup.sql.gz |
    MYSQL_PWD="$ZNUNY_DB_PASSWORD" mariadb \
      -h "$ZNUNY_DB_HOST" -P "$ZNUNY_DB_PORT" -u "$ZNUNY_DB_USER" "$ZNUNY_DB_NAME"
  set_permissions
'
```

After this command, the database assignments in `volumes/config/Config.pm`
must match `.env` and point to `mariadb`. Keep credentials private when checking.

Custom Kernel files, certificates and custom skins are not imported by these
commands. Copy the source custom files from the retained backup individually
after checking their compatibility with each target series; keep an extra copy
outside `volumes/config`, because startup refreshes standard Kernel files.

### 4. Run the selected target migration offline

For the **7.1 source**, execute this intermediate 7.2.3 stage:

```bash
docker compose run --rm --no-deps --entrypoint /bin/bash znuny -c '
  . /functions.sh
  set -e -o pipefail
  wait_for_db
  check_custom_skins_dir
  set_permissions
  su -s /bin/bash -c "cd /opt/znuny && scripts/MigrateToZnuny7_2.pl --verbose --non-interactive" znuny
  su -s /bin/bash -c "cd /opt/znuny && bin/znuny.Console.pl Admin::Package::UpgradeAll" znuny
  su -s /bin/bash -c "cd /opt/znuny && bin/znuny.Console.pl Admin::Package::ReinstallAll" znuny
  su -s /bin/bash -c "cd /opt/znuny && scripts/MigrateToZnuny7_2.pl --verbose --non-interactive" znuny
  printf "%s\n" "$ZNUNY_VERSION" > /opt/znuny/Kernel/current_version
'
```

All migration runs must finish with **Migration completed!** and exit
successfully. If a migration or package command fails, keep the app stopped.
`--non-interactive` skips the migration script's backup prompt; use it here only
after the source backup and archive checks above succeeded.
For unavailable add-ons, put the compatible `.opm` files in `volumes/addons`,
install them with the following command using the **actual package filename**,
and rerun the failed stage. Here `CompatiblePackage.opm` is that filename:

```bash
docker compose run --rm --no-deps --entrypoint /bin/bash znuny -c   'su -s /bin/bash -c "cd /opt/znuny && bin/znuny.Console.pl Admin::Package::Install /opt/znuny/addons/CompatiblePackage.opm" znuny'
```

After the 7.2 migration succeeds, set `ZNUNY_VERSION=7.3.7` in `.env` and
run `docker compose pull znuny`. A 7.2 or 7.3 source already selected this image.
Now run the final 7.3 stage for **all source versions**:

```bash
docker compose run --rm --no-deps --entrypoint /bin/bash znuny -c '
  . /functions.sh
  set -e -o pipefail
  wait_for_db
  sync_kernel_new_files
  check_custom_skins_dir
  set_permissions
  su -s /bin/bash -c "cd /opt/znuny && scripts/MigrateToZnuny7_3.pl --verbose --non-interactive" znuny
  su -s /bin/bash -c "cd /opt/znuny && bin/znuny.Console.pl Admin::Package::UpgradeAll" znuny
  su -s /bin/bash -c "cd /opt/znuny && bin/znuny.Console.pl Admin::Package::ReinstallAll" znuny
  su -s /bin/bash -c "cd /opt/znuny && scripts/MigrateToZnuny7_3.pl --verbose --non-interactive" znuny
  su -s /bin/bash -c "cd /opt/znuny && bin/znuny.Console.pl Maint::Config::Rebuild" znuny
  su -s /bin/bash -c "cd /opt/znuny && bin/znuny.Console.pl Maint::Cache::Delete" znuny
  printf "%s\n" "$ZNUNY_VERSION" > /opt/znuny/Kernel/current_version
'
```

The version marker is written only after the commands succeed, so normal startup
does not interpret the restored database as an empty installation or rerun the
automatic version transition. The existing source admin password remains valid.

### 5. Start, verify and cut over

```bash
docker compose up -d --no-deps znuny
docker compose logs --tail=100 znuny
docker compose exec -T znuny cat /opt/znuny/RELEASE
docker compose exec -T znuny cat /opt/znuny/Kernel/current_version
docker compose exec -T znuny su -s /bin/bash -c   'cd /opt/znuny && bin/znuny.Daemon.pl status' znuny
curl -fsS -o /dev/null http://127.0.0.1:8080/znuny/index.pl
```

Use your `ZNUNY_HTTP_PORT` instead of 8080 if changed. Both version checks must
show 7.3.7. Log in with a source admin account, open an existing ticket and its
attachments, create a test ticket, and verify your add-ons and SAML login if
configured. An HTTP response alone is not a successful migration.

Keep inbound mail delivery and user traffic directed away from the target
until these checks pass. `ZNUNY_DISABLE_EMAIL_FETCH=yes` disables polling only;
it does not disable SMTP delivery, external mail injection or other daemon jobs.
Then route the reverse proxy to this stack, set
`ZNUNY_DISABLE_EMAIL_FETCH=no` and restore your `ZNUNY_BACKUP_TIME` schedule
in `.env`, and recreate the application:

```bash
docker compose up -d --no-deps --force-recreate znuny
```

### 6. Rollback before accepting new traffic

If a stage fails, stop the target with `docker compose stop znuny`; keep its
database and volumes for diagnosis. Do not downgrade the image over a migrated
database. The stopped source still contains the unchanged source database.
On the **source host**, resume it with:

```bash
su -s /bin/bash -c 'cd /opt/znuny && bin/Cron.sh start && bin/znuny.Daemon.pl start' znuny
systemctl start apache2
systemctl start postfix
```

Route users and mail back to the source. Once the target has accepted tickets
or mail, this rollback would lose those new records; stop intake and reconcile
them before returning to the source.

The mandatory release suite tests this offline procedure with synthetic fullbackups:
7.1.3 → 7.2.3 → 7.3.7 with filesystem attachments and 7.2.3 → 7.3.7 with database
attachments. It verifies preserved ticket/article IDs, article body, binary
attachment bytes, admin login, database, daemon and target versions. The existing
E2E additionally covers 7.3.1 → 7.3.7. See [suite instructions](tests/migration/README.md)
and [recorded results](tests/migration/RESULTS.md). These fixtures contain no
add-ons or custom authentication; rehearse with your own copy for those
installation-specific features before production cutover. Upstream references explain the series
requirements: [7.2 update](https://doc.znuny.org/znuny-7_2/updating/update-7.2.html)
and [7.3 update](https://doc.znuny.org/znuny/updating/update-7.3.html).

---

## Development

Enable debug mode by setting `ZNUNY_DEBUG=yes` in `.env`, then:

```bash
docker compose up
docker compose logs -f
```
