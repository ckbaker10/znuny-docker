# znuny-docker

Dockerised [Znuny 7.2](https://www.znuny.org) based on **Debian 12 (Bookworm)**.

Images are published to the GitHub Container Registry on every version tag push.

```
ghcr.io/ckbkr10/znuny:<version>
ghcr.io/ckbkr10/znuny-mariadb:<version>
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
│   ├── Dockerfile                     # Main Znuny image (Debian 12)
│   ├── entrypoint.sh                  # Container startup logic
│   ├── functions.sh                   # Helper functions
│   ├── util_functions.sh              # Logging utilities
│   ├── znuny_backup.sh                # Automated backup script (called by cron)
│   └── etc/supervisord/znuny.conf     # Supervisord program definitions
├── mariadb/
│   ├── Dockerfile                     # MariaDB 10.11 image
│   └── etc/znuny.cnf                  # MariaDB tuning for Znuny
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

```bash
# 1. Place the backup archive in ./volumes/backups/
# 2. Set the restore variables in .env:
ZNUNY_INSTALL=restore
ZNUNY_BACKUP_DATE=2024-01-15_04-00   # filename without extension
ZNUNY_DROP_DATABASE=yes              # required if DB already exists

# 3. Start the stack
docker compose up
```

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
# Build both images
docker compose build

# Build with a specific Znuny version
docker compose build --build-arg ZNUNY_VERSION=7.2.1
```

---

## Publishing Images via GitHub Actions

Push a version tag to trigger the build-and-push workflow:

```bash
git tag v7.2.1
git push origin v7.2.1
```

This builds multi-arch images (`linux/amd64` + `linux/arm64`) and pushes:

- `ghcr.io/<owner>/znuny:7.2.1`
- `ghcr.io/<owner>/znuny:latest`
- `ghcr.io/<owner>/znuny-mariadb:7.2.1`
- `ghcr.io/<owner>/znuny-mariadb:latest`

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

## Patch Level Updates (7.2.x → 7.2.y)

Updating to a new patch release only requires bumping the version and restarting.
All data is preserved in volumes — the image is replaced, not the data.

```bash
# 1. Update the version in .env
ZNUNY_VERSION=7.2.3

# 2. Pull the new pre-built image
docker compose pull

# 3. Restart the stack
docker compose up -d
```

On startup the container automatically:
- Rebuilds the Znuny configuration (`Maint::Config::Rebuild`)
- Clears the application cache (`Maint::Cache::Delete`)
- Reinstalls any addons found in `./volumes/addons`

For patch level releases these steps are sufficient. If a release explicitly requires
a schema migration or package reinstall, run these commands after the container is up:

```bash
docker exec -it znuny-docker-znuny-1 \
  su -c "scripts/MigrateToZnuny7_2.pl --verbose" -s /bin/bash znuny

docker exec -it znuny-docker-znuny-1 \
  su -c "bin/znuny.Console.pl Admin::Package::ReinstallAll" -s /bin/bash znuny
```

---

## Migrating an Existing Znuny 7.1 System to Docker

Use this process to move a bare-metal or VM-based Znuny 7.1 installation into this
Docker setup. The migration upgrades Znuny to 7.2 at the same time.

### 1. Back up the existing system

On the source system, create a full backup using the bundled script:

```bash
su -c "scripts/backup.pl -d /path/to/backup --backup-type fullbackup" - znuny
```

Copy the resulting archive to `./volumes/backups/` on the Docker host.

### 2. Restore into the container

Set the restore variables in `.env`:

```env
ZNUNY_INSTALL=restore
ZNUNY_BACKUP_DATE=2024-01-15_04-00   # filename without extension
ZNUNY_DROP_DATABASE=yes
```

Start the stack — the entrypoint will restore the database and files automatically:

```bash
docker compose up -d
```

### 3. Run the 7.2 migration

Once the container is running, execute the migration script:

```bash
docker exec -it znuny-docker-znuny-1 \
  su -c "scripts/MigrateToZnuny7_2.pl --verbose" -s /bin/bash znuny
```

### 4. Reinstall addons

```bash
docker exec -it znuny-docker-znuny-1 \
  su -c "bin/znuny.Console.pl Admin::Package::ReinstallAll" -s /bin/bash znuny
```

### 5. Switch to normal mode and restart

Edit `.env`:

```env
ZNUNY_INSTALL=no
```

```bash
docker compose up -d
```

The system is now running Znuny 7.2 in Docker with all data from the original installation.

---

## Development

Enable debug mode by setting `ZNUNY_DEBUG=yes` in `.env`, then:

```bash
docker compose up
docker compose logs -f
```
