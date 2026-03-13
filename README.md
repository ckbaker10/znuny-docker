# znuny-docker

Dockerised [Znuny 7.2](https://www.znuny.org) based on **Debian 12 (Bookworm)**.

Images are published to the GitHub Container Registry on every version tag push.

```
ghcr.io/<owner>/znuny:<version>
ghcr.io/<owner>/znuny-mariadb:<version>
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
open http://localhost/znuny
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
├── docker-compose.yml                 # Production stack
├── docker-compose.override.yml        # Dev overrides (debug mode, exposed DB port)
├── .env.example                       # All supported variables with descriptions
└── Planning.md                        # Architecture decisions and implementation plan
```

---

## Startup Modes

Set the `ZNUNY_INSTALL` environment variable to choose the startup mode.

| `ZNUNY_INSTALL` | Behaviour |
|---|---|
| `no` (default) | Auto-configure, initialise the database, start all services |
| `yes` | Skip auto-setup; run the web installer at `/znuny/installer.pl` |
| `restore` | Restore the backup specified by `ZNUNY_BACKUP_DATE` |

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

## Development

The `docker-compose.override.yml` is applied automatically and:

- Enables `ZNUNY_DEBUG=yes`
- Maps Znuny on port **8080** (instead of 80)
- Exposes MariaDB on **port 3306** for local database clients

```bash
docker compose up        # uses override automatically
docker compose logs -f   # follow all logs
```
