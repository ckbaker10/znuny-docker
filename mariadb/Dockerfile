# MariaDB image tuned for Znuny 7.2
# Applies the configuration required by the Znuny installation documentation.

FROM mariadb:10.11

LABEL maintainer="znuny-docker" \
      org.opencontainers.image.title="Znuny MariaDB" \
      org.opencontainers.image.description="MariaDB 10.11 configured for Znuny 7.2"

# Copy Znuny-specific MariaDB configuration
COPY etc/znuny.cnf /etc/mysql/mariadb.conf.d/50-znuny.cnf
