# Znuny 7.2 Docker image
# Base: Debian 12 (Bookworm) slim
# Install method: source tarball from download.znuny.org

FROM debian:12-slim

ARG ZNUNY_VERSION
LABEL maintainer="znuny-docker" \
      org.opencontainers.image.title="Znuny" \
      org.opencontainers.image.description="Znuny ${ZNUNY_VERSION} on Debian 12" \
      org.opencontainers.image.version="${ZNUNY_VERSION}" \
      org.opencontainers.image.source="https://github.com/znuny/znuny"

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
ENV ZNUNY_VERSION=${ZNUNY_VERSION} \
    ZNUNY_ROOT="/opt/znuny/" \
    ZNUNY_BACKUP_DIR="/var/znuny/backups" \
    ZNUNY_CONFIG_MOUNT_DIR="/Kernel" \
    ZNUNY_SKINS_MOUNT_DIR="/skins" \
    SKINS_PATH="/opt/znuny/var/httpd/htdocs/skins/" \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# System packages
# All required Perl modules from the Znuny 7.2 install documentation (Debian)
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Web server
    apache2 \
    libapache2-mod-perl2 \
    libapache-dbi-perl \
    # Database
    mariadb-client \
    libdbd-mysql-perl \
    # Perl modules — required by Znuny
    libtimedate-perl \
    libnet-dns-perl \
    libnet-ldap-perl \
    libio-socket-ssl-perl \
    libpdf-api2-perl \
    libsoap-lite-perl \
    libtext-csv-xs-perl \
    libjson-xs-perl \
    libxml-libxml-perl \
    libxml-libxslt-perl \
    libyaml-perl \
    libyaml-libyaml-perl \
    libarchive-zip-perl \
    libcrypt-eksblowfish-perl \
    libencode-hanextra-perl \
    libmail-imapclient-perl \
    libtemplate-perl \
    libdatetime-perl \
    libmoo-perl \
    libjavascript-minifier-xs-perl \
    libcss-minifier-xs-perl \
    libauthen-sasl-perl \
    libauthen-ntlm-perl \
    libhash-merge-perl \
    libical-parser-perl \
    libspreadsheet-xlsx-perl \
    libdata-uuid-perl \
    # Perl modules — optional
    libcrypt-jwt-perl \
    libcrypt-openssl-x509-perl \
    libdbd-odbc-perl \
    libdbd-pg-perl \
    # Process management & utilities
    supervisor \
    cron \
    rsyslog \
    wget \
    tar \
    locales \
    # Required to allow znuny user to run cron jobs
    libpam-runtime \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    && echo 'LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\nLANGUAGE=en_US.UTF-8' > /etc/environment \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Download & install Znuny
# ---------------------------------------------------------------------------
RUN cd /opt && \
    wget -q "https://download.znuny.org/releases/znuny-${ZNUNY_VERSION}.tar.gz" && \
    tar xfz "znuny-${ZNUNY_VERSION}.tar.gz" && \
    ln -s "/opt/znuny-${ZNUNY_VERSION}" /opt/znuny && \
    rm "znuny-${ZNUNY_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# Create znuny system user and apply initial configuration
# ---------------------------------------------------------------------------
RUN useradd \
      --home-dir /opt/znuny \
      --comment 'Znuny user' \
      --gid www-data \
      --shell /bin/bash \
      --no-create-home \
      --no-user-group \
      znuny && \
    cp /opt/znuny/Kernel/Config.pm.dist /opt/znuny/Kernel/Config.pm && \
    /opt/znuny/bin/znuny.SetPermissions.pl

# ---------------------------------------------------------------------------
# Configure Apache 2
# ---------------------------------------------------------------------------
RUN ln -s /opt/znuny/scripts/apache2-httpd.include.conf \
          /etc/apache2/conf-available/znuny.conf && \
    a2dismod mpm_event  2>/dev/null || true && \
    a2enmod  mpm_prefork headers filter perl && \
    a2enconf znuny && \
    # Redirect Apache logs to container stdout/stderr
    ln -sf /dev/stdout /var/log/apache2/access.log && \
    ln -sf /dev/stderr /var/log/apache2/error.log  && \
    ln -sf /dev/stdout /var/log/apache2/other_vhosts_access.log

# ---------------------------------------------------------------------------
# Allow znuny user to run cron jobs
# ---------------------------------------------------------------------------
RUN echo "+ : znuny : cron crond" >> /etc/security/access.conf && \
    sed -i -e '/pam_loginuid.so/ s/^#*/#/' /etc/pam.d/cron 2>/dev/null || true

# ---------------------------------------------------------------------------
# Suppress rsyslog journal warnings in container environment
# ---------------------------------------------------------------------------
RUN sed -i -e '/imjournal/ s/^/#/' /etc/rsyslog.conf 2>/dev/null || true && \
    sed -i -e '/imklog/    s/^/#/' /etc/rsyslog.conf 2>/dev/null || true

# ---------------------------------------------------------------------------
# Copy startup scripts
# ---------------------------------------------------------------------------
COPY util_functions.sh functions.sh entrypoint.sh znuny_backup.sh /
COPY etc/supervisord/znuny.conf /etc/supervisor/conf.d/znuny.conf
RUN chmod 755 /entrypoint.sh /znuny_backup.sh /functions.sh /util_functions.sh

# ---------------------------------------------------------------------------
# Stage Kernel/ and skins/ outside the app dir so host-mounted volumes work.
# On first container start, entrypoint copies them back in.
# ---------------------------------------------------------------------------
RUN mv /opt/znuny/Kernel /Kernel && \
    mkdir -p /opt/znuny/Kernel && \
    mv /opt/znuny/var/httpd/htdocs/skins /skins && \
    mkdir -p /opt/znuny/var/httpd/htdocs/skins && \
    # Create required runtime directories
    mkdir -p /var/znuny/backups \
             /opt/znuny/var/run \
             /opt/znuny/var/tmp \
             /opt/znuny/addons && \
    # Mark as first-time start
    touch /opt/znuny/var/tmp/firsttime && \
    # Redirect cron log to stdout
    ln -sf /dev/stdout /var/log/cron.log 2>/dev/null || true

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
