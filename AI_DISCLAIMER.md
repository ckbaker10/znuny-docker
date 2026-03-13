# AI Disclaimer

This project was created with the assistance of **Claude Sonnet 4.6** (model ID: `claude-sonnet-4-6`), an AI assistant developed by [Anthropic](https://www.anthropic.com), accessed via [Claude Code](https://claude.ai/claude-code) — Anthropic's official CLI.

## Scope of AI Involvement

The following was designed and implemented with AI assistance:

- **Architecture & planning** — `Planning.md`, directory structure, choice of base image and install method
- **Dockerfile** — Debian 12-slim base, Znuny source tarball install, Apache 2 / mod_perl configuration, Perl dependency selection, locale setup, volume staging
- **Container scripts** — `entrypoint.sh`, `functions.sh`, `util_functions.sh`, `znuny_backup.sh`
- **Supervisord configuration** — `znuny/etc/supervisord/znuny.conf`
- **MariaDB image** — `mariadb/Dockerfile`, `mariadb/etc/znuny.cnf`
- **Compose stack** — `docker-compose.yml`, environment variable design
- **CI/CD** — `.github/workflows/build-push.yml` (multi-arch builds, ghcr.io publish)
- **Documentation** — `README.md` including all operational runbooks

## Runtime Bugs Diagnosed and Fixed with AI Assistance

- `random_string: command not found` — function defined after the call site
- `DBI connect failed` — daemon started in installer mode before `Config.pm` was written
- `setlocale: LC_ALL: cannot change locale` — locale not persisted for `su` subshells
- `Cron.sh: Run this script just as Znuny user!` — extra username argument passed incorrectly
- GitHub Actions tagging only `latest`, not the version tag — `metadata-action` interaction
- 404 on skins CSS in installer mode — `check_custom_skins_dir` not called in `yes` mode
- Patch level update crash — wrong migration script (`DBUpdate-to-7.pl` vs `MigrateToZnuny7_2.pl`)

## Human Oversight

All generated code was reviewed, tested on a live server, and iteratively corrected based on real container logs. The AI did not have direct access to the runtime environment — all execution, testing, and final approval was performed by the project author.
