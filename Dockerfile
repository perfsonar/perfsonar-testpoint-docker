# perfSONAR Testpoint

FROM centos:centos7

RUN yum -y install \
    epel-release \
    http://software.internet2.edu/rpms/el7/x86_64/latest/packages/perfsonar-repo-0.11-1.noarch.rpm \
    && yum -y install \
    supervisor \
    rsyslog \
    net-tools \
    sysstat \
    iproute \
    bind-utils \
    tcpdump \
    postgresql10-server

# -----------------------------------------------------------------------

#
# PostgreSQL Server
#
# Based on a Dockerfile at
# https://raw.githubusercontent.com/zokeber/docker-postgresql/master/Dockerfile

# Postgresql version
ENV PG_VERSION 10
ENV PGVERSION 10

# Set the environment variables
ENV PGDATA /var/lib/pgsql/10/data

# Create run directory (using /run for Kaniko build)
RUN install -dv --mode=775 --owner=postgres --group=postgres /var/run/postgresql /run/postgresql

# Initialize the database
RUN su - postgres -c "/usr/pgsql-10/bin/pg_ctl init"

# Overlay the configuration files
COPY postgresql/postgresql.conf /var/lib/pgsql/$PG_VERSION/data/postgresql.conf
COPY postgresql/pg_hba.conf /var/lib/pgsql/$PG_VERSION/data/pg_hba.conf

# Change own user
RUN chown -R postgres:postgres /var/lib/pgsql/$PG_VERSION/data/*
RUN chmod 0755 /var/lib/pgsql

#Start postgresql
RUN su - postgres -c "/usr/pgsql-10/bin/pg_ctl start -w -t 60" \
    && yum install -y perfsonar-testpoint perfsonar-toolkit-security \
    && yum clean all \
    && rm -rf /var/cache/yum

# End PostgreSQL Setup

# -----------------------------------------------------------------------------

# Rsyslog
# Note: need to modify default CentOS7 rsyslog configuration to work with Docker, 
# as described here: http://www.projectatomic.io/blog/2014/09/running-syslog-within-a-docker-container/
COPY rsyslog/rsyslog.conf /etc/rsyslog.conf
COPY rsyslog/listen.conf /etc/rsyslog.d/listen.conf
COPY rsyslog/python-pscheduler.conf /etc/rsyslog.d/python-pscheduler.conf
COPY rsyslog/owamp-syslog.conf /etc/rsyslog.d/owamp-syslog.conf

# -----------------------------------------------------------------------------

RUN mkdir -p /var/log/supervisor 
ADD supervisord.conf /etc/supervisord.conf

# The following ports are used:
# pScheduler: 443
# owamp:861, 8760-9960
# twamp: 862, 18760-19960
# simplestream: 5890-5900
# nuttcp: 5000, 5101
# iperf2: 5001
# iperf3: 5201
EXPOSE 443 861 862 5000-5001 5101 5201 8760-9960 18760-19960

# add pid directory, logging, and postgres directory
VOLUME ["/var/run", "/var/lib/pgsql", "/var/log", "/etc/rsyslog.d" ]

CMD /usr/bin/supervisord -c /etc/supervisord.conf
