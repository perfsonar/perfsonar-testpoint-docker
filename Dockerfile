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
COPY rsyslog/owamp-syslog.conf /etc/rsyslog.d/owamp-syslog.conf


# -----------------------------------------------------------------------------

RUN mkdir -p /var/log/supervisor
ADD supervisord.conf /etc/supervisord.conf

# The following ports are used:
# pScheduler: 443
# owamp:861, 8760-9960
# ranges not supported in docker, so need to use docker run -P to expose all ports

# add pid directory, logging, and postgres directory
VOLUME ["/var/run", "/var/lib/pgsql", "/var/log", "/etc/rsyslog.d" ]

CMD /usr/bin/supervisord -c /etc/supervisord.conf
