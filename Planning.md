# Znuny 7.2 Docker Implementation Plan

## Overview

Rebuild the Docker setup for **Znuny 7.2** from scratch, replacing the old OTRS 6 / CentOS 7 implementation with a modern Debian 12-based stack. GitHub Actions will build and push the image to **ghcr.io** on version tag pushes.

---

## Key Decisions

| Topic | Decision |
|---|---|
| Base image | `debian:12-slim` |
| Znuny install | Source tarball from `download.znuny.org` |
| Database | MariaDB 10.11 companion container |
| Web server | Apache 2 with `mod_perl`, `mpm_prefork` |
| Process manager | Supervisord |
| Registry | `ghcr.io/<owner>/znuny` |
| CI trigger | Push on `v*` tags only |
| Architectures | `linux/amd64`, `linux/arm64` |

---

## Repository Structure

```
znuny-docker/
├── .github/
│   └── workflows/
│       └── build-push.yml          # GitHub Actions: build & push to ghcr.io
├── znuny/
│   ├── Dockerfile                  # Main Znuny 7.2 image (Debian 12)
│   ├── entrypoint.sh               # Container entrypoint / startup logic
│   ├── functions.sh                # Core helper functions (DB setup, config, backups, etc.)
│   ├── util_functions.sh           # Logging utilities (print_info, print_error, etc.)
│   ├── znuny_backup.sh             # Automated backup script (called via cron)
│   └── etc/
│       └── supervisord/
│           └── znuny.conf          # Supervisord program definitions (apache2, cron, rsyslog)
├── mariadb/
│   ├── Dockerfile                  # MariaDB image with Znuny-required config
│   └── etc/
│       └── znuny.cnf               # MariaDB tuning (max_allowed_packet, innodb_log_file_size)
├── docker-compose.yml              # Production stack (znuny + mariadb)
├── docker-compose.override.yml     # Dev overrides (expose ports, bind mounts, debug)
├── .env.example                    # All supported env vars with defaults & descriptions
├── .gitignore
└── README.md
```

---

## Dockerfile (`znuny/Dockerfile`)

### Build stages
Single-stage build on `debian:12-slim`.

### Steps
1. Set `ENV` vars: `ZNUNY_VERSION=7.2.1`, `ZNUNY_ROOT=/opt/znuny`, `ZNUNY_BACKUP_DIR`, `ZNUNY_CONFIG_DIR`, etc.
2. `apt update` + install all required packages per `install.rst` (Debian section):
   - `apache2`, `libapache2-mod-perl2`, `libdbd-mysql-perl`, `libtimedate-perl`, `libnet-dns-perl`, `libnet-ldap-perl`, `libio-socket-ssl-perl`, `libpdf-api2-perl`, `libsoap-lite-perl`, `libtext-csv-xs-perl`, `libjson-xs-perl`, `libapache-dbi-perl`, `libxml-libxml-perl`, `libxml-libxslt-perl`, `libyaml-perl`, `libarchive-zip-perl`, `libcrypt-eksblowfish-perl`, `libencode-hanextra-perl`, `libmail-imapclient-perl`, `libtemplate-perl`, `libdatetime-perl`, `libmoo-perl`, `libyaml-libyaml-perl`, `libjavascript-minifier-xs-perl`, `libcss-minifier-xs-perl`, `libauthen-sasl-perl`, `libauthen-ntlm-perl`, `libhash-merge-perl`, `libical-parser-perl`, `libspreadsheet-xlsx-perl`, `libdata-uuid-perl`
   - `supervisor`, `cron`, `rsyslog`, `mariadb-client`, `wget`, `tar`
3. Download and extract `znuny-latest-7.2.tar.gz` from `https://download.znuny.org/releases/`
4. Create symlink `/opt/znuny` → `/opt/znuny-7.2.x`
5. Create `znuny` user: `useradd -d /opt/znuny -c 'Znuny user' -g www-data -s /bin/bash -M -N znuny`
6. Copy `Config.pm.dist` → `Config.pm`
7. Run `znuny.SetPermissions.pl`
8. Configure Apache:
   - Symlink `scripts/apache2-httpd.include.conf` → `/etc/apache2/conf-available/znuny.conf`
   - `a2dismod mpm_event`, `a2enmod mpm_prefork headers filter perl`, `a2enconf znuny`
9. Copy scripts (`entrypoint.sh`, `functions.sh`, `util_functions.sh`, `znuny_backup.sh`) to `/`
10. Copy supervisord config
11. Move `Kernel/` and `skins/` to staging locations (for host-volume mount support)
12. Log symlinks to stdout/stderr: `ln -sf /dev/stdout /var/log/apache2/access.log` etc.
13. `EXPOSE 80`
14. `CMD ["/entrypoint.sh"]`

---

## entrypoint.sh

Startup modes driven by `ZNUNY_INSTALL` env var:

| `ZNUNY_INSTALL` value | Behaviour |
|---|---|
| `no` (default) | Auto-configure, create/reuse DB, start services |
| `yes` | Run web installer at `http://HOST/znuny/installer.pl` |
| `restore` | Restore from backup at `ZNUNY_BACKUP_DATE` |

### Flow (`ZNUNY_INSTALL=no`)
1. `wait_for_db` — poll MariaDB until ready
2. `check_host_mount_dir` — copy staged `Kernel/` to `$ZNUNY_CONFIG_DIR` if first run
3. `setup_znuny_config` — write DB, SMTP, hostname, timezone, etc. into `Config.pm`
4. Check if DB exists; if not: `create_db` + load `znuny-schema.mysql.sql`, `znuny-initial_insert.mysql.sql`, `znuny-schema-post.mysql.sql`
5. `set_ticket_counter` / `set_permissions` / `install_modules`
6. Start cron: `bin/Cron.sh start znuny`
7. Start daemon: `su -c "bin/znuny.Daemon.pl start" znuny`
8. Rebuild config + clear cache
9. Launch supervisord
10. Signal-trap `SIGTERM` for graceful shutdown

---

## functions.sh — Key Functions

| Function | Purpose |
|---|---|
| `wait_for_db` | Loop until `mysqladmin ping` succeeds |
| `create_db` | `CREATE DATABASE` + `GRANT` for znuny user |
| `setup_znuny_config` | Patch `Config.pm` with env-driven values |
| `add_config_value` | `sed`-based insert/update of a single Config.pm key |
| `load_defaults` | Orchestrate first-run DB init and config setup |
| `restore_backup` | Unpack tar backup, restore DB + files |
| `install_modules` | Install `.opm` addon packages from `$ZNUNY_ADDONS_PATH` |
| `reinstall_modules` | Reinstall all registered addons on container restart |
| `setup_backup_cron` | Write cron entry at `$ZNUNY_BACKUP_TIME` |
| `switch_article_storage_type` | Migrate articles between DB and FS storage |
| `term_handler` | Graceful SIGTERM handler |

---

## MariaDB (`mariadb/Dockerfile`)

- Base: `mariadb:10.11`
- Mount `znuny.cnf` into `/etc/mysql/mariadb.conf.d/50-znuny.cnf` at build time
- Config per `install.rst`:

```ini
[mysql]
max_allowed_packet = 256M

[mysqldump]
max_allowed_packet = 256M

[mysqld]
innodb_log_file_size = 256M
max_allowed_packet   = 256M
character-set-server = utf8mb4
collation-server     = utf8mb4_unicode_ci
```

---

## docker-compose.yml

```yaml
services:
  znuny:
    image: ghcr.io/<owner>/znuny:latest
    ports:
      - "80:80"
    depends_on:
      mariadb:
        condition: service_healthy
    env_file: .env
    volumes:
      - ./volumes/config:/opt/znuny/Kernel
      - ./volumes/article:/opt/znuny/var/article
      - ./volumes/backups:/var/znuny/backups
      - ./volumes/addons:/opt/znuny/addons
      - /etc/localtime:/etc/localtime:ro

  mariadb:
    build: ./mariadb
    expose:
      - "3306"
    env_file: .env
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      retries: 10
    volumes:
      - ./volumes/mysql:/var/lib/mysql
      - /etc/localtime:/etc/localtime:ro
```

---

## .env.example — Supported Variables

### Database
| Variable | Default | Description |
|---|---|---|
| `ZNUNY_DB_NAME` | `znuny` | Database name |
| `ZNUNY_DB_HOST` | `mariadb` | DB hostname |
| `ZNUNY_DB_PORT` | `3306` | DB port |
| `ZNUNY_DB_USER` | `znuny` | DB app user |
| `ZNUNY_DB_PASSWORD` | `changeme` | DB app user password |
| `MYSQL_ROOT_USER` | `root` | DB root user |
| `MYSQL_ROOT_PASSWORD` | `changeme` | DB root password |

### Znuny
| Variable | Default | Description |
|---|---|---|
| `ZNUNY_INSTALL` | `no` | Startup mode: `no`, `yes`, `restore` |
| `ZNUNY_ROOT_PASSWORD` | `changeme` | `root@localhost` admin password |
| `ZNUNY_HOSTNAME` | auto | Container FQDN |
| `ZNUNY_LANGUAGE` | `en` | Default language |
| `ZNUNY_TIMEZONE` | `UTC` | Default timezone |
| `ZNUNY_TICKET_COUNTER` | — | Ticket counter start value |
| `ZNUNY_NUMBER_GENERATOR` | `DateChecksum` | Ticket number generator |
| `ZNUNY_SET_PERMISSIONS` | `yes` | Run SetPermissions on start |
| `ZNUNY_ARTICLE_STORAGE_TYPE` | `ArticleStorageDB` | `ArticleStorageDB` or `ArticleStorageFS` |
| `ZNUNY_BACKUP_TIME` | `0 4 * * *` | Cron schedule for backups (or `disable`) |
| `ZNUNY_BACKUP_DATE` | — | Backup to restore (used when `ZNUNY_INSTALL=restore`) |
| `ZNUNY_DROP_DATABASE` | `no` | Drop existing DB on restore |
| `ZNUNY_DISABLE_EMAIL_FETCH` | `no` | Disable mail account polling |
| `ZNUNY_ALLOW_NOT_VERIFIED_PACKAGES` | `no` | Allow unverified addon install |
| `ZNUNY_DEBUG` | `no` | Enable debug mode |

### SMTP
| Variable | Description |
|---|---|
| `ZNUNY_SENDMAIL_MODULE` | e.g. `SMTP`, `SMTPS`, `Sendmail` |
| `ZNUNY_SMTP_SERVER` | SMTP hostname |
| `ZNUNY_SMTP_PORT` | SMTP port |
| `ZNUNY_SMTP_USERNAME` | SMTP auth user |
| `ZNUNY_SMTP_PASSWORD` | SMTP auth password |

---

## GitHub Actions (`.github/workflows/build-push.yml`)

### Trigger
```yaml
on:
  push:
    tags:
      - 'v*'
```

### Steps
1. Checkout code
2. Set up QEMU (multi-arch)
3. Set up Docker Buildx
4. Login to `ghcr.io` using `GITHUB_TOKEN`
5. Extract metadata (tags: `7.2.x` from git tag + `latest`, labels)
6. Build & push `znuny/` image:
   - Platforms: `linux/amd64`, `linux/arm64`
   - Tags: `ghcr.io/${{ github.repository_owner }}/znuny:7.2.x` + `:latest`
   - Cache: `type=gha`
7. Build & push `mariadb/` image:
   - Same platforms and cache strategy
   - Tags: `ghcr.io/${{ github.repository_owner }}/znuny-mariadb:7.2.x` + `:latest`

---

## Notable Differences from Old OTRS Implementation

| Aspect | Old (OTRS 6) | New (Znuny 7.2) |
|---|---|---|
| Base OS | `centos:7` | `debian:12-slim` |
| Install path | `/opt/otrs` | `/opt/znuny` |
| System user | `otrs` / group `apache` | `znuny` / group `www-data` |
| Binary prefix | `otrs.Console.pl`, `otrs.Daemon.pl` | `znuny.Console.pl`, `znuny.Daemon.pl` |
| Apache service | `httpd` | `apache2` |
| MariaDB version | `10.1` | `10.11` |
| CI system | Drone CI (`.drone.yml`) | GitHub Actions |
| Env var prefix | `OTRS_*` | `ZNUNY_*` |
| Multi-arch | No | Yes (`amd64` + `arm64`) |
| DB healthcheck | None (polling loop) | `docker compose` native healthcheck |

---

## Files to Create

1. `znuny/Dockerfile`
2. `znuny/entrypoint.sh`
3. `znuny/functions.sh`
4. `znuny/util_functions.sh`
5. `znuny/znuny_backup.sh`
6. `znuny/etc/supervisord/znuny.conf`
7. `mariadb/Dockerfile`
8. `mariadb/etc/znuny.cnf`
9. `docker-compose.yml`
10. `docker-compose.override.yml`
11. `.env.example`
12. `.github/workflows/build-push.yml`
13. `.gitignore`
14. `README.md`
