# perfSONAR Testpoint

FROM centos:centos7
MAINTAINER Brian Tierney <bltierney@es.net>


RUN yum -y install epel-release
RUN yum -y install http://software.internet2.edu/rpms/el7/x86_64/main/RPMS/Internet2-repo-0.7-1.noarch.rpm 
RUN yum -y update; yum clean all
RUN yum -y install perfsonar-testpoint
RUN yum -y install supervisor rsyslog net-tools sysstat iproute bind-utils tcpdump # grab a few other needed tools

# -----------------------------------------------------------------------

# PostgreSQL Setup

# Based on a Dockerfile at
# https://raw.githubusercontent.com/zokeber/docker-postgresql/master/Dockerfile

# Postgresql version
ENV PG_VERSION 9.5
ENV PGVERSION 95

# Set the environment variables
ENV PGDATA /var/lib/pgsql/9.5/data

# Working directory
# not sure if this is needed?
WORKDIR /var/lib/pgsql

# Initialize the database
RUN su - postgres -c "/usr/pgsql-9.5/bin/pg_ctl init"

# Copy config file
COPY postgresql-data/postgresql.conf /var/lib/pgsql/$PG_VERSION/data/postgresql.conf
COPY postgresql-data/pg_hba.conf /var/lib/pgsql/$PG_VERSION/data/pg_hba.conf

# Change own user
RUN chown -R postgres:postgres /var/lib/pgsql/$PG_VERSION/data/*

# End PostgreSQL Setup

# -----------------------------------------------------------------------

# Hot patch the database loader so it doesn't barf when not
# interactive.

# TODO: Remove this after pS 4.0.0.3.  Probably harmless if left here.
RUN sed -i -e 's/^\(\$INTERACTIVE.*\)$/\1 || true/g' \
    /usr/libexec/pscheduler/internals/db-update 

# Initialize pscheduler database.  This needs to happen as one command
# because each RUN happens in an interim container.


RUN    su - postgres -c "/usr/pgsql-9.5/bin/pg_ctl start -w -t 60" \
    && su - root     -c "pscheduler internal db-update" \
    && su - postgres -c "/usr/pgsql-9.5/bin/pg_ctl stop  -w -t 60"

#config rsyslog
COPY rsyslog/python-pscheduler.conf /etc/rsyslog.d/python-pscheduler.conf
COPY rsyslog/owamp_bwctl-syslog.conf /etc/rsyslog.d/owamp_bwctl-syslog.conf

RUN mkdir -p /var/log/supervisor 
ADD supervisord.conf /etc/supervisord.conf

# The following ports are used:
# pScheduler: 443
# bwctl:4823, 5001-5900, 6001-6200
# owamp:861, 8760-9960
# ranges not supported in docker, so need to use docker run -P to expose all ports

# add pid directory and postgres directory
VOLUME ["/var/run", "/var/lib/pgsql"]


CMD /usr/bin/supervisord -c /etc/supervisord.conf
