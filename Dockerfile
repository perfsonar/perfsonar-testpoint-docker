# perfSONAR Testpoint

FROM centos:centos7
MAINTAINER perfSONAR <perfsonar-user@perfsonar.net>


RUN yum -y install epel-release
RUN yum -y install http://software.internet2.edu/rpms/el7/x86_64/main/RPMS/perfSONAR-repo-0.8-1.noarch.rpm
RUN yum -y update; yum clean all
RUN yum -y install perfsonar-testpoint
RUN yum -y install supervisor rsyslog net-tools sysstat iproute bind-utils tcpdump # grab a few other needed tools

# -----------------------------------------------------------------------

#
# PostgreSQL Server
#

# shouldn't be necessary but isn't added to path via rpm
ENV PATH="/usr/pgsql-9.5/bin:${PATH}"

# Initialize the database
RUN su postgres -c 'pg_ctl init -D /var/lib/pgsql/9.5/data'

# Overlay the configuration files
COPY --chown=postgres:postgres ["postgresql/postgresql.conf", "postgresql/pg_hba.conf", "/var/lib/pgsql/9.5/data/"]

# End PostgreSQL Setup


# -----------------------------------------------------------------------------

#
# pScheduler Database
#
# Initialize pscheduler database.  This needs to happen as one command
# because each RUN happens in an interim container.

# Start the server
RUN su postgres -c "pg_ctl start -w -t 60" && \
    # Generate the password file
    random-string --safe --length 60 > '/etc/pscheduler/database/database-password' && \
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


# -----------------------------------------------------------------------------

# Rsyslog
# Note: need to modify default CentOS7 rsyslog configuration to work with Docker,
# as described here: http://www.projectatomic.io/blog/2014/09/running-syslog-within-a-docker-container/
COPY rsyslog/rsyslog.conf /etc/rsyslog.conf
COPY ["rsyslog/listen.conf", "rsyslog/python-pscheduler.conf", "rsyslog/owamp-syslog.conf", "/etc/rsyslog.d/"]

# -----------------------------------------------------------------------------

RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisord.conf

# The following ports are used:
# pScheduler: 443
# owamp:861, 8760-9960
# ranges not supported in docker, so need to use docker run -P to expose all ports

# add pid directory, logging, and postgres directory
VOLUME ["/var/run", "/var/lib/pgsql", "/var/log", "/etc/rsyslog.d" ]

CMD /usr/bin/supervisord -c /etc/supervisord.conf
