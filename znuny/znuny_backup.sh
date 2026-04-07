#!/bin/bash
# Automated backup script for the Znuny container.
# Called from cron (configured by setup_backup_cron in functions.sh).

# Source exported env vars written by setup_backup_cron
[ -f /.backup.env ] && . /.backup.env

ZNUNY_ROOT="${ZNUNY_ROOT:-/opt/znuny/}"
ZNUNY_BACKUP_DIR="${ZNUNY_BACKUP_DIR:-/var/znuny/backups}"
ZNUNY_BACKUP_TYPE="${ZNUNY_BACKUP_TYPE:-fullbackup}"
ZNUNY_BACKUP_COMPRESSION="${ZNUNY_BACKUP_COMPRESSION:-gzip}"
ZNUNY_BACKUP_ROTATION="${ZNUNY_BACKUP_ROTATION:-30}"

mkdir -p "${ZNUNY_BACKUP_DIR}"
chown znuny:www-data "${ZNUNY_BACKUP_DIR}"

echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Starting Znuny backup (type=${ZNUNY_BACKUP_TYPE}, compress=${ZNUNY_BACKUP_COMPRESSION})..."

su -c "${ZNUNY_ROOT}scripts/backup.pl \
  -d ${ZNUNY_BACKUP_DIR} \
  -t ${ZNUNY_BACKUP_TYPE} \
  -c ${ZNUNY_BACKUP_COMPRESSION}" \
  -s /bin/bash znuny

if [ $? -eq 0 ]; then
  echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backup completed successfully."
  # Remove backups older than ZNUNY_BACKUP_ROTATION days
  find "${ZNUNY_BACKUP_DIR}" \( -name "*.tar.gz" -o -name "*.tar.bz2" \) \
    -mtime "+${ZNUNY_BACKUP_ROTATION}" -delete
  echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Cleaned up backups older than ${ZNUNY_BACKUP_ROTATION} days."
else
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Backup failed!" >&2
  exit 1
fi
