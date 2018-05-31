# perfSONAR Testpoint

FROM centos:centos7
MAINTAINER perfSONAR <perfsonar-user@perfsonar.net>

RUN yum -y install \
    # epel-release repo
    epel-release \
    # perfSONAR release repo
    http://software.internet2.edu/rpms/el7/x86_64/main/RPMS/perfSONAR-repo-0.8-1.noarch.rpm && \
    # reload the cache for the new repos
    yum clean expire-cache && \
    # install testpoint bundle and required tools for docker image
    yum -y install \
    perfsonar-testpoint \
    supervisor \
    rsyslog && \
    # clean up
    yum clean all && \
    rm -rf /var/cache/yum/*

#
# PostgreSQL Server
#
# shouldn't be necessary but isn't added to path via rpm
ENV PATH="/usr/pgsql-9.5/bin:${PATH}"
# declare database location
ENV PGDATA="/var/lib/pgsql/9.5/data/"

# Initialize the database
RUN su postgres -c 'pg_ctl init'
# Overlay the configuration files
COPY --chown=postgres:postgres [ \
    "postgresql/postgresql.conf", \
    "postgresql/pg_hba.conf", \
    "/var/lib/pgsql/9.5/data/"]

#
# pScheduler Database
#
# Initialize pscheduler database
RUN su postgres -c "pg_ctl start -w -t 60" && \
    # Generate the password file
    random-string --safe --length 60 \
    > '/etc/pscheduler/database/database-password' && \
    # Generate the DSN file
    printf "host=127.0.0.1 dbname=pscheduler user=pscheduler password=%s\n" \
    cat /etc/pscheduler/database/database-password \
    > /etc/pscheduler/database/database-dsn && \
    # Generate a PostgreSQL password file
    # Format is hostname:port:database:username:password
    printf "*:*:pscheduler:pscheduler:%s\n" \
    cat /etc/pscheduler/database/database-password \
    > "/etc/pscheduler/database/pgpassfile" && \
    chmod 400 /etc/pscheduler/database/pgpassfile && \
    # Build the database
    pscheduler internal db-update && \
    # Set the password in the pScheduler database to match what's on the
    # disk.
    ( \
        printf "ALTER ROLE pscheduler WITH UNENCRYPTED PASSWORD '" \
        && tr -d "\n" < "/etc/pscheduler/database/database-password" \
        && printf "';\n" \
    ) | postgresql-load && \
    # Shut down
    su postgres -c "pg_ctl stop  -w -t 60"

# Rsyslog
COPY rsyslog/rsyslog.conf /etc/rsyslog.conf
COPY ["rsyslog/listen.conf", \
      "rsyslog/python-pscheduler.conf", \
      "rsyslog/owamp-syslog.conf", \
      "/etc/rsyslog.d/"]

# Supervisor
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisord.conf

#
# Expose the proper ports for the perfSONAR tools
#
# owamp
EXPOSE 861
EXPOSE 8760-9960/udp
# pscheduler
EXPOSE 443
# iperf3
EXPOSE 5201
# iperf2
EXPOSE 5001
# nuttcp
EXPOSE 5000
EXPOSE 5101
# traceroute
EXPOSE 33434-33634/udp
# simplestream
EXPOSE 5890-5900
# ntp
EXPOSE 123/udp

# add pid directory, logging, and postgres directory
VOLUME ["/var/run", "/var/lib/pgsql", "/var/log", "/etc/rsyslog.d" ]

CMD /usr/bin/supervisord -c /etc/supervisord.conf
