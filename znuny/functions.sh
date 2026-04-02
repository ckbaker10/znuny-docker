#!/bin/bash
# Core helper functions for the Znuny 7.2 container.
#
# Startup modes (ZNUNY_INSTALL):
#   no      – Auto-configure, initialise DB, start services (default)
#   yes     – Launch the web installer at /znuny/installer.pl
#   restore – Restore from backup at $ZNUNY_BACKUP_DATE

. /util_functions.sh

# ---------------------------------------------------------------------------
# Default values (overridable via env)
# ---------------------------------------------------------------------------
DEFAULT_ZNUNY_ROOT_PASSWORD="changeme"
DEFAULT_ZNUNY_DB_PASSWORD="changeme"
DEFAULT_MYSQL_ROOT_PASSWORD="changeme"
DEFAULT_ZNUNY_DB_NAME="znuny"
DEFAULT_ZNUNY_DB_USER="znuny"
DEFAULT_MYSQL_ROOT_USER="root"
DEFAULT_ZNUNY_DB_HOST="mariadb"
DEFAULT_ZNUNY_DB_PORT=3306
DEFAULT_ZNUNY_BACKUP_TIME="0 4 * * *"
DEFAULT_BACKUP_SCRIPT="/znuny_backup.sh"
DEFAULT_ZNUNY_CRON_BACKUP_SCRIPT="/etc/cron.d/znuny_backup"

WAIT_TIMEOUT=3
ZNUNY_CONFIG_DIR="${ZNUNY_ROOT}Kernel/"
ZNUNY_CONFIG_FILE="${ZNUNY_CONFIG_DIR}Config.pm"
ZNUNY_CONFIG_MOUNT_DIR="/Kernel"
ZNUNY_SKINS_MOUNT_DIR="/skins"

# ---------------------------------------------------------------------------
# Must be defined before the env-defaults block that calls it
# ---------------------------------------------------------------------------
function random_string() {
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1
}

# Apply env defaults
[ -z "${ZNUNY_INSTALL}" ]              && ZNUNY_INSTALL="no"
[ -z "${ZNUNY_DB_NAME}" ]              && print_info "ZNUNY_DB_NAME not set, defaulting to ${DEFAULT_ZNUNY_DB_NAME}"   && ZNUNY_DB_NAME=${DEFAULT_ZNUNY_DB_NAME}
[ -z "${ZNUNY_DB_USER}" ]              && print_info "ZNUNY_DB_USER not set, defaulting to ${DEFAULT_ZNUNY_DB_USER}"   && ZNUNY_DB_USER=${DEFAULT_ZNUNY_DB_USER}
[ -z "${ZNUNY_DB_HOST}" ]              && print_info "ZNUNY_DB_HOST not set, defaulting to ${DEFAULT_ZNUNY_DB_HOST}"   && ZNUNY_DB_HOST=${DEFAULT_ZNUNY_DB_HOST}
[ -z "${ZNUNY_DB_PORT}" ]              && print_info "ZNUNY_DB_PORT not set, defaulting to ${DEFAULT_ZNUNY_DB_PORT}"   && ZNUNY_DB_PORT=${DEFAULT_ZNUNY_DB_PORT}
[ -z "${ZNUNY_DB_PASSWORD}" ]          && print_info "ZNUNY_DB_PASSWORD not set, using default"                        && ZNUNY_DB_PASSWORD=${DEFAULT_ZNUNY_DB_PASSWORD}
[ -z "${ZNUNY_ROOT_PASSWORD}" ]        && print_info "ZNUNY_ROOT_PASSWORD not set, using default"                      && ZNUNY_ROOT_PASSWORD=${DEFAULT_ZNUNY_ROOT_PASSWORD}
[ -z "${MYSQL_ROOT_PASSWORD}" ]        && print_info "MYSQL_ROOT_PASSWORD not set, using default"                      && MYSQL_ROOT_PASSWORD=${DEFAULT_MYSQL_ROOT_PASSWORD}
[ -z "${MYSQL_ROOT_USER}" ]            && MYSQL_ROOT_USER=${DEFAULT_MYSQL_ROOT_USER}
[ -z "${ZNUNY_HOSTNAME}" ]             && ZNUNY_HOSTNAME="znuny-$(random_string)" && print_info "ZNUNY_HOSTNAME not set, using '${ZNUNY_HOSTNAME}'"
[ -z "${ZNUNY_BACKUP_TIME}" ]          && ZNUNY_BACKUP_TIME=${DEFAULT_ZNUNY_BACKUP_TIME}
[ -z "${ZNUNY_ARTICLE_STORAGE_TYPE}" ] && ZNUNY_ARTICLE_STORAGE_TYPE="ArticleStorageDB"
[ -z "${ZNUNY_SET_PERMISSIONS}" ]      && ZNUNY_SET_PERMISSIONS="yes"
[ -z "${ZNUNY_ALLOW_NOT_VERIFIED_PACKAGES}" ] && ZNUNY_ALLOW_NOT_VERIFIED_PACKAGES="no"
[ -z "${ZNUNY_DISABLE_EMAIL_FETCH}" ]  && ZNUNY_DISABLE_EMAIL_FETCH="no"

ZNUNY_ADDONS_PATH="${ZNUNY_ROOT}addons/"
INSTALLED_ADDONS_DIR="${ZNUNY_ADDONS_PATH}installed"
SKINS_PATH="${ZNUNY_ROOT}var/httpd/htdocs/skins/"

mysqlcmd="mysql -u${MYSQL_ROOT_USER} -h ${ZNUNY_DB_HOST} -P ${ZNUNY_DB_PORT} -p${MYSQL_ROOT_PASSWORD}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function random_string() {
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1
}

function wait_for_db() {
  print_info "Waiting for database at ${ZNUNY_DB_HOST}:${ZNUNY_DB_PORT}..."
  while ! mysqladmin ping \
      -h "${ZNUNY_DB_HOST}" \
      -P "${ZNUNY_DB_PORT}" \
      -u "${MYSQL_ROOT_USER}" \
      --password="${MYSQL_ROOT_PASSWORD}" \
      --silent \
      --connect_timeout=3 2>/dev/null; do
    print_info "Database not ready yet. Retrying in ${WAIT_TIMEOUT}s..."
    sleep ${WAIT_TIMEOUT}
  done
  print_info "Database is up."
}

function create_db() {
  print_info "Creating Znuny database '${ZNUNY_DB_NAME}'..."
  $mysqlcmd -e "CREATE DATABASE IF NOT EXISTS \`${ZNUNY_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  [ $? -gt 0 ] && print_error "Could not create database '${ZNUNY_DB_NAME}'!" && exit 1
  $mysqlcmd -e "GRANT ALL ON \`${ZNUNY_DB_NAME}\`.* TO '${ZNUNY_DB_USER}'@'%' IDENTIFIED BY '${ZNUNY_DB_PASSWORD}';"
  [ $? -gt 0 ] && print_error "Could not grant privileges to '${ZNUNY_DB_USER}'!" && exit 1
  $mysqlcmd -e "FLUSH PRIVILEGES;"
  print_info "Database created and user granted."
}

# ---------------------------------------------------------------------------
# Config.pm patching
# ---------------------------------------------------------------------------
function add_config_value() {
  local key="${1}"
  local value="${2}"
  local mask="${3:-false}"
  local display_value="${value}"
  [ "${mask}" == "true" ] && display_value="**********"

  print_info "Setting Config.pm: ${key} = ${display_value}"
  # Delete ALL existing lines for this key (handles duplicates from prior runs),
  # then insert a single canonical entry right after the Home line.
  sed -i -r "/\\\$Self->\{'?${key}'?\}/d" "${ZNUNY_CONFIG_FILE}"
  sed -i "/\\\$Self->{Home} = '\/opt\/znuny';/a \\    \\\$Self->{'${key}'} = '${value}';" "${ZNUNY_CONFIG_FILE}"
}

function setup_znuny_config() {
  print_info "Configuring Znuny (Config.pm)..."

  # Database
  add_config_value "DatabaseUser" "${ZNUNY_DB_USER}"
  add_config_value "DatabasePw"   "${ZNUNY_DB_PASSWORD}" true
  add_config_value "DatabaseHost" "${ZNUNY_DB_HOST}"
  add_config_value "DatabasePort" "${ZNUNY_DB_PORT}"
  add_config_value "Database"     "${ZNUNY_DB_NAME}"

  # General
  add_config_value "FQDN"       "${ZNUNY_HOSTNAME}"
  add_config_value "SecureMode" "1"
  [ -n "${ZNUNY_LANGUAGE}" ] && add_config_value "DefaultLanguage" "${ZNUNY_LANGUAGE}"
  [ -n "${ZNUNY_TIMEZONE}" ] && add_config_value "OTRSTimeZone"    "${ZNUNY_TIMEZONE}" \
                              && add_config_value "UserDefaultTimeZone" "${ZNUNY_TIMEZONE}"

  # SMTP
  [ -n "${ZNUNY_SENDMAIL_MODULE}" ]  && add_config_value "SendmailModule"           "Kernel::System::Email::${ZNUNY_SENDMAIL_MODULE}"
  [ -n "${ZNUNY_SMTP_SERVER}" ]      && add_config_value "SendmailModule::Host"     "${ZNUNY_SMTP_SERVER}"
  [ -n "${ZNUNY_SMTP_PORT}" ]        && add_config_value "SendmailModule::Port"     "${ZNUNY_SMTP_PORT}"
  [ -n "${ZNUNY_SMTP_USERNAME}" ]    && add_config_value "SendmailModule::AuthUser" "${ZNUNY_SMTP_USERNAME}"
  [ -n "${ZNUNY_SMTP_PASSWORD}" ]    && add_config_value "SendmailModule::AuthPassword" "${ZNUNY_SMTP_PASSWORD}" true

  setup_backup_cron
  reinstall_modules
}

# ---------------------------------------------------------------------------
# Host-volume mount helpers
# ---------------------------------------------------------------------------
function check_host_mount_dir() {
  # On first run (or upgrade), copy the staged Kernel/ from /Kernel → $ZNUNY_CONFIG_DIR
  if [ "$(ls -A ${ZNUNY_CONFIG_MOUNT_DIR} 2>/dev/null)" ] && [ ! "$(ls -A ${ZNUNY_CONFIG_DIR} 2>/dev/null)" ]; then
    print_info "Copying default Znuny config to ${ZNUNY_CONFIG_DIR}..."
    mkdir -p "${ZNUNY_CONFIG_DIR}"
    cp -rfp "${ZNUNY_CONFIG_MOUNT_DIR}/." "${ZNUNY_CONFIG_DIR}/"
    [ $? -gt 0 ] && print_error "Failed to copy config to ${ZNUNY_CONFIG_DIR}!" && exit 1
    print_info "Done."
  else
    print_info "Existing config directory found — skipping copy."
  fi
}

function sync_kernel_new_files() {
  # Copy files added in a new Znuny version into the persistent Kernel volume
  # without overwriting any existing files (preserves Config.pm and customisations).
  print_info "Syncing new Kernel files from image to ${ZNUNY_CONFIG_DIR}..."
  cp -rn "${ZNUNY_CONFIG_MOUNT_DIR}/." "${ZNUNY_CONFIG_DIR}/"
  print_info "Kernel sync done."
}

function check_custom_skins_dir() {
  print_info "Copying default skins to ${SKINS_PATH}..."
  mkdir -p "${SKINS_PATH}"
  cp -rfp "${ZNUNY_SKINS_MOUNT_DIR}/." "${SKINS_PATH}/"
  [ $? -gt 0 ] && print_error "Failed to copy skins!" && exit 1
  print_info "Done."
}

# ---------------------------------------------------------------------------
# Database initialisation
# ---------------------------------------------------------------------------
function load_defaults() {
  local version_file="${ZNUNY_CONFIG_DIR}/current_version"

  # Detect minor version change and run DB update script if needed
  if [ -f "${version_file}" ]; then
    local current_version
    current_version=$(cat "${version_file}")
    local new_version
    new_version=$(echo "${ZNUNY_VERSION}" | cut -d'-' -f1)
    print_info "Installed version: ${current_version} | Container version: ${new_version}"
    if [ "${current_version}" != "${new_version}" ]; then
      print_info "Version change detected — running migration..."
      sync_kernel_new_files
      check_custom_skins_dir
      upgrade_minor_version
      upgrade_modules
      echo "${new_version}" > "${version_file}"
    fi
  else
    # Genuine first boot — initialise config and database
    local ver
    ver=$(grep 'VERSION' "${ZNUNY_ROOT}RELEASE" | cut -d'=' -f2 | tr -d ' ')
    echo "${ver}" > "${version_file}"

    check_host_mount_dir
    check_custom_skins_dir
    setup_znuny_config
  fi

  $mysqlcmd -e "USE \`${ZNUNY_DB_NAME}\`" 2>/dev/null
  if [ $? -gt 0 ]; then
    create_db
    if [ "${ZNUNY_INSTALL}" == "no" ]; then
      print_info "Loading DB schema..."
      $mysqlcmd "${ZNUNY_DB_NAME}" < "${ZNUNY_ROOT}scripts/database/znuny-schema.mysql.sql"
      [ $? -gt 0 ] && print_error "Failed to load znuny-schema.mysql.sql!" && exit 1
      print_info "Loading initial DB inserts..."
      $mysqlcmd "${ZNUNY_DB_NAME}" < "${ZNUNY_ROOT}scripts/database/znuny-initial_insert.mysql.sql"
      [ $? -gt 0 ] && print_error "Failed to load znuny-initial_insert.mysql.sql!" && exit 1
      print_info "Loading DB schema constraints..."
      $mysqlcmd "${ZNUNY_DB_NAME}" < "${ZNUNY_ROOT}scripts/database/znuny-schema-post.mysql.sql"
      [ $? -gt 0 ] && print_error "Failed to load znuny-schema-post.mysql.sql!" && exit 1
      print_info "Database schema loaded."
    fi
  else
    print_info "Database '${ZNUNY_DB_NAME}' already exists — skipping init."
  fi
}

# ---------------------------------------------------------------------------
# Backup & restore
# ---------------------------------------------------------------------------
function restore_backup() {
  [ -z "$1" ] && print_error "ZNUNY_BACKUP_DATE not set." && exit 1

  check_host_mount_dir
  setup_znuny_config

  local restore_file="${ZNUNY_BACKUP_DIR}/${ZNUNY_BACKUP_DATE}"
  local temp_dir restore_dir

  if [ -f "${restore_file}" ]; then
    tar tf "${restore_file}" &>/dev/null || { print_error "Backup archive is corrupt!"; exit 1; }
    temp_dir=$(mktemp -d)
    tar zxvf "${restore_file}" -C "${temp_dir}"
    [ $? -gt 0 ] && print_error "Failed to extract backup!" && exit 1
    restore_dir="${temp_dir}/$(ls -t "${temp_dir}" | head -n1)"
  elif [ -d "${restore_file}" ]; then
    restore_dir="${restore_file}"
  else
    print_error "Backup '${restore_file}' not found!" && exit 1
  fi

  $mysqlcmd -e "USE \`${ZNUNY_DB_NAME}\`" 2>/dev/null
  if [ $? -eq 0 ]; then
    if [ "${ZNUNY_DROP_DATABASE}" == "yes" ]; then
      print_warning "ZNUNY_DROP_DATABASE=yes — dropping existing database..."
      $mysqlcmd -e "DROP DATABASE \`${ZNUNY_DB_NAME}\`"
    else
      print_error "Database '${ZNUNY_DB_NAME}' already exists. Set ZNUNY_DROP_DATABASE=yes to overwrite." && exit 1
    fi
  fi

  create_db
  su -c "${ZNUNY_ROOT}scripts/restore.pl -b ${restore_dir} -d ${ZNUNY_ROOT}" -s /bin/bash znuny
  [ $? -gt 0 ] && print_error "Restore failed!" && exit 1
  print_info "Restore completed."
}

function setup_backup_cron() {
  if [ "${ZNUNY_BACKUP_TIME}" == "disable" ]; then
    print_warning "Automated backups disabled."
    rm -f /etc/cron.d/znuny_backup
    return
  fi

  # Export env vars for the backup cron job
  export -p | sed -e 's/"/'"'"'/g' | grep -E "^declare -x ZNUNY_" > /.backup.env

  local backup_script="${ZNUNY_BACKUP_SCRIPT:-${DEFAULT_BACKUP_SCRIPT}}"
  local cron_file="${ZNUNY_CRON_BACKUP_SCRIPT:-${DEFAULT_ZNUNY_CRON_BACKUP_SCRIPT}}"

  print_info "Setting backup cron: ${ZNUNY_BACKUP_TIME}"
  echo "${ZNUNY_BACKUP_TIME} root . /.backup.env; ${backup_script}" > "${cron_file}"
  chmod 644 "${cron_file}"
}

# ---------------------------------------------------------------------------
# Addon / package management
# ---------------------------------------------------------------------------
function install_modules() {
  local location="${1}"
  mkdir -p "${INSTALLED_ADDONS_DIR}"
  print_info "Checking for addons in ${location}..."
  local packages
  packages=$(ls "${location}"/*.opm 2>/dev/null)
  if [ -z "${packages}" ]; then
    print_info "No addons found."
    return
  fi
  for pkg in ${packages}; do
    print_info "Installing addon: ${pkg}"
    su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Admin::Package::Install ${pkg}" -s /bin/bash znuny
    if [ $? -gt 0 ]; then
      print_warning "Could not install ${pkg} — install manually via the Package Manager."
    else
      mv "${pkg}" "${INSTALLED_ADDONS_DIR}/"
    fi
  done
}

function reinstall_modules() {
  print_info "Reinstalling registered addons..."
  su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Admin::Package::ReinstallAll" -s /bin/bash znuny
  if [ $? -gt 0 ]; then
    print_warning "Could not reinstall addons — do it manually via the Package Manager."
  fi
}

function upgrade_modules() {
  print_info "Upgrading addons..."
  su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Admin::Package::UpgradeAll" -s /bin/bash znuny
  if [ $? -gt 0 ]; then
    print_warning "Could not upgrade addons — do it manually via the Package Manager."
  fi
}

# ---------------------------------------------------------------------------
# Minor version upgrade
# ---------------------------------------------------------------------------
function upgrade_minor_version() {
  print_info "Running patch level migration..."
  su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Maint::Config::Rebuild --cleanup" -s /bin/bash znuny
  local _major_minor
  _major_minor=$(echo "${ZNUNY_VERSION}" | cut -d'.' -f1,2 | tr '.' '_')
  su -c "${ZNUNY_ROOT}scripts/MigrateToZnuny${_major_minor}.pl --verbose" -s /bin/bash znuny
  if [ $? -gt 0 ]; then
    print_error "Patch level migration failed!" && exit 1
  fi
  print_info "Patch level migration complete."
}

# ---------------------------------------------------------------------------
# Ticket counter & permissions
# ---------------------------------------------------------------------------
function set_ticket_counter() {
  if [ -n "${ZNUNY_TICKET_COUNTER}" ]; then
    print_info "Setting ticket counter to: ${ZNUNY_TICKET_COUNTER}"
    echo "${ZNUNY_TICKET_COUNTER}" > "${ZNUNY_ROOT}var/log/TicketCounter.log"
  fi
  if [ -n "${ZNUNY_NUMBER_GENERATOR}" ]; then
    add_config_value "Ticket::NumberGenerator" "Kernel::System::Ticket::Number::${ZNUNY_NUMBER_GENERATOR}"
  fi
}

function set_permissions() {
  if [ "${ZNUNY_SET_PERMISSIONS}" == "yes" ]; then
    print_info "Setting Znuny permissions..."
    ${ZNUNY_ROOT}bin/znuny.SetPermissions.pl --znuny-user=znuny --web-group=www-data "${ZNUNY_ROOT}"
  elif [ "${ZNUNY_SET_PERMISSIONS}" == "skip-article-dir" ]; then
    print_info "Setting permissions (skipping article directory)..."
    ${ZNUNY_ROOT}bin/znuny.SetPermissions.pl --znuny-user=znuny --web-group=www-data "${ZNUNY_ROOT}" --skip-article-dir
  else
    print_info "ZNUNY_SET_PERMISSIONS=${ZNUNY_SET_PERMISSIONS} — skipping."
  fi
}

# ---------------------------------------------------------------------------
# Article storage type
# ---------------------------------------------------------------------------
function switch_article_storage_type() {
  if [ "${ZNUNY_ARTICLE_STORAGE_TYPE}" != "ArticleStorageFS" ] && \
     [ "${ZNUNY_ARTICLE_STORAGE_TYPE}" != "ArticleStorageDB" ]; then
    print_warning "Unknown ZNUNY_ARTICLE_STORAGE_TYPE: ${ZNUNY_ARTICLE_STORAGE_TYPE}"
    return
  fi

  local current_type
  current_type=$(su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Admin::Config::Read \
    --setting-name Ticket::Article::Backend::MIMEBase::ArticleStorage" \
    -s /bin/bash znuny 2>/dev/null | grep Kernel | grep -oE 'ArticleStorage[A-Za-z]+')

  if [ "${current_type}" != "${ZNUNY_ARTICLE_STORAGE_TYPE}" ]; then
    print_info "Switching article storage to ${ZNUNY_ARTICLE_STORAGE_TYPE}..."
    su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Admin::Config::Update \
      --setting-name Ticket::Article::Backend::MIMEBase::ArticleStorage \
      --value Kernel::System::Ticket::Article::Backend::MIMEBase::${ZNUNY_ARTICLE_STORAGE_TYPE}" \
      -s /bin/bash znuny
    su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Admin::Article::StorageSwitch \
      --target ${ZNUNY_ARTICLE_STORAGE_TYPE}" \
      -s /bin/bash znuny
  else
    print_info "Article storage already set to ${ZNUNY_ARTICLE_STORAGE_TYPE}."
  fi
}

# ---------------------------------------------------------------------------
# Email fetch toggle
# ---------------------------------------------------------------------------
function disable_email_fetch() {
  print_info "Disabling email account polling..."
  su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Admin::Config::Update \
    --setting-name Daemon::SchedulerCronTaskManager::Task###MailAccountFetch \
    --valid 0" -s /bin/bash znuny
}

function enable_email_fetch() {
  print_info "Enabling email account polling..."
  su -c "${ZNUNY_ROOT}bin/znuny.Console.pl Admin::Config::Update \
    --setting-name Daemon::SchedulerCronTaskManager::Task###MailAccountFetch \
    --valid 1" -s /bin/bash znuny
}

# ---------------------------------------------------------------------------
# Unverified package install toggle
# ---------------------------------------------------------------------------
function not_allowed_pkgs_install() {
  if [ "${ZNUNY_ALLOW_NOT_VERIFIED_PACKAGES}" == "yes" ]; then
    print_info "Allowing installation of not-verified packages..."
    add_config_value "Package::AllowNotVerifiedPackages" "1"
  fi
}

# ---------------------------------------------------------------------------
# SIGTERM handler
# ---------------------------------------------------------------------------
function term_handler() {
  print_info "SIGTERM received — shutting down Znuny..."
  # Cron.sh expects to be called as the znuny user with no extra user argument
  su -c "${ZNUNY_ROOT}bin/Cron.sh stop" -s /bin/bash znuny
  su -c "${ZNUNY_ROOT}bin/znuny.Daemon.pl stop" -s /bin/bash znuny
  supervisorctl stop all
  exit 143
}
