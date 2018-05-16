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
# Based on a Dockerfile at
# https://raw.githubusercontent.com/zokeber/docker-postgresql/master/Dockerfile

# Postgresql version
ENV PG_VERSION 9.5
ENV PGVERSION 95

# Set the environment variables
ENV PGDATA /var/lib/pgsql/9.5/data

# Initialize the database
RUN su - postgres -c "/usr/pgsql-9.5/bin/pg_ctl init"

# Overlay the configuration files
COPY postgresql/postgresql.conf /var/lib/pgsql/$PG_VERSION/data/postgresql.conf
COPY postgresql/pg_hba.conf /var/lib/pgsql/$PG_VERSION/data/pg_hba.conf

# Change own user
RUN chown -R postgres:postgres /var/lib/pgsql/$PG_VERSION/data/*

# End PostgreSQL Setup


# -----------------------------------------------------------------------------

#
# pScheduler Database
#
# Initialize pscheduler database.  This needs to happen as one command
# because each RUN happens in an interim container.

COPY postgresql/pscheduler-build-database /tmp/pscheduler-build-database
RUN  /tmp/pscheduler-build-database
RUN  rm -f /tmp/pscheduler-build-database


# -----------------------------------------------------------------------------

# Rsyslog
# Note: need to modify default CentOS7 rsyslog configuration to work with Docker, 
# as described here: http://www.projectatomic.io/blog/2014/09/running-syslog-within-a-docker-container/
COPY rsyslog/rsyslog.conf /etc/rsyslog.conf
COPY rsyslog/listen.conf /etc/rsyslog.d/listen.conf
COPY rsyslog/python-pscheduler.conf /etc/rsyslog.d/python-pscheduler.conf
COPY rsyslog/owamp_bwctl-syslog.conf /etc/rsyslog.d/owamp_bwctl-syslog.conf


# -----------------------------------------------------------------------------

RUN mkdir -p /var/log/supervisor 
ADD supervisord.conf /etc/supervisord.conf

# The following ports are used:
# pScheduler: 443
# bwctl:4823, 5001-5900, 6001-6200
# owamp:861, 8760-9960
# ranges not supported in docker, so need to use docker run -P to expose all ports

# add pid directory, logging, and postgres directory
VOLUME ["/var/run", "/var/lib/pgsql", "/var/log", "/etc/rsyslog.d" ]

CMD /usr/bin/supervisord -c /etc/supervisord.conf
