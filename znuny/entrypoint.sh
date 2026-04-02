#!/bin/bash
# Entrypoint for the Znuny 7.2 Docker container.
#
# Startup modes (set via ZNUNY_INSTALL env var):
#   no      – Auto-configure, initialise database, start all services (default)
#   yes     – Skip auto-setup; run the web installer at /znuny/installer.pl
#   restore – Restore a backup specified by ZNUNY_BACKUP_DATE

. /functions.sh

# ---------------------------------------------------------------------------
# Debug mode
# ---------------------------------------------------------------------------
if [ "${ZNUNY_DEBUG}" == "yes" ]; then
  print_info "Debug mode enabled."
  set -x
  env
fi

# ---------------------------------------------------------------------------
# Wait for the database to become available
# ---------------------------------------------------------------------------
wait_for_db

# ---------------------------------------------------------------------------
# Mode: web installer
# ---------------------------------------------------------------------------
if [ "${ZNUNY_INSTALL}" == "yes" ]; then
  print_info "Installer mode — open http://<hostname>/znuny/installer.pl to proceed."
  check_host_mount_dir
  check_custom_skins_dir
  ${ZNUNY_ROOT}bin/znuny.SetPermissions.pl --znuny-user=znuny --web-group=www-data "${ZNUNY_ROOT}"

# ---------------------------------------------------------------------------
# Mode: restore from backup
# ---------------------------------------------------------------------------
elif [ "${ZNUNY_INSTALL}" == "restore" ]; then
  print_info "Restore mode — restoring backup: ${ZNUNY_BACKUP_DATE}"
  restore_backup "${ZNUNY_BACKUP_DATE}"
  set_permissions
  not_allowed_pkgs_install
  install_modules "${ZNUNY_ADDONS_PATH}"
  set_ticket_counter
  rm -f "${ZNUNY_ROOT}var/tmp/firsttime"

  su -c "${ZNUNY_ROOT}bin/Cron.sh start" -s /bin/bash znuny
  su -c "${ZNUNY_ROOT}bin/znuny.Daemon.pl start" -s /bin/bash znuny
  su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Maint::Config::Rebuild" -s /bin/bash znuny
  su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Maint::Cache::Delete" -s /bin/bash znuny
  switch_article_storage_type

  if [ "${ZNUNY_DISABLE_EMAIL_FETCH}" == "yes" ]; then
    disable_email_fetch
  else
    enable_email_fetch
  fi

# ---------------------------------------------------------------------------
# Mode: normal (default)
# ---------------------------------------------------------------------------
else
  print_info "Starting Znuny ${ZNUNY_VERSION}..."

  if [ -e "${ZNUNY_ROOT}var/tmp/firsttime" ]; then
    # Detect genuine first boot before load_defaults writes the version file
    _version_file="${ZNUNY_CONFIG_DIR}/current_version"
    _first_boot=false
    [ ! -f "${_version_file}" ] && _first_boot=true

    load_defaults

    # Only set the admin password on genuine first boot, not on patch updates,
    # and only when ZNUNY_ROOT_PASSWORD is explicitly provided.
    if [ "${_first_boot}" == "true" ] && [ -n "${ZNUNY_ROOT_PASSWORD}" ]; then
      print_info "Setting admin password for root@localhost..."
      su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Admin::User::SetPassword root@localhost ${ZNUNY_ROOT_PASSWORD}" \
         -s /bin/bash znuny
    fi
  fi

  # Always sync new Kernel files from the image into the persistent volume.
  # Uses cp -rn so existing files (Config.pm, customisations) are never overwritten.
  # This ensures modules added in a new Znuny version (e.g. SAML) are available
  # even when no version bump is detected.
  sync_kernel_new_files
  # Always (re-)copy skins — /opt/znuny/var/httpd/htdocs/skins/ is left empty
  # in the image (skins are staged at /skins) and is not a mounted volume,
  # so it must be populated on every container start.
  check_custom_skins_dir
  # Always (re-)install the backup cron — /etc/cron.d is ephemeral inside the
  # container and is lost on every restart, so we must recreate it each boot.
  setup_backup_cron
  set_permissions
  not_allowed_pkgs_install
  install_modules "${ZNUNY_ADDONS_PATH}"
  set_ticket_counter
  rm -f "${ZNUNY_ROOT}var/tmp/firsttime"

  su -c "${ZNUNY_ROOT}bin/Cron.sh start" -s /bin/bash znuny
  su -c "${ZNUNY_ROOT}bin/znuny.Daemon.pl start" -s /bin/bash znuny
  su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Maint::Config::Rebuild" -s /bin/bash znuny
  su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Maint::Cache::Delete" -s /bin/bash znuny
  switch_article_storage_type

  if [ "${ZNUNY_DISABLE_EMAIL_FETCH}" == "yes" ]; then
    disable_email_fetch
  else
    enable_email_fetch
  fi
fi

# ---------------------------------------------------------------------------
# Hand off to supervisord
# ---------------------------------------------------------------------------
print_info "Starting supervisord..."
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf &

# Brief pause to let supervisord (and apache) start
sleep 2

# In installer mode the daemon must NOT start — Config.pm has no DB config yet.
# It will be started on the next container restart after the web installer runs.
if [ "${ZNUNY_INSTALL}" != "yes" ]; then
  print_info "Restarting Znuny daemon..."
  su -c "${ZNUNY_ROOT}bin/znuny.Daemon.pl stop" -s /bin/bash znuny
  sleep 1
  su -c "${ZNUNY_ROOT}bin/znuny.Daemon.pl start" -s /bin/bash znuny
fi

print_info "Znuny ${ZNUNY_VERSION} is ready."

# ---------------------------------------------------------------------------
# Signal handling — stay alive and allow graceful shutdown
# ---------------------------------------------------------------------------
trap term_handler SIGTERM SIGINT

while true; do
  tail -f /dev/null & wait ${!}
done
