# perfSONAR Testpoint

FROM centos:7

# -----------------------------------------------------------------------
## Commands required to run systemd 

# Don't start any optional services except for the few we need.
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
rm -f /lib/systemd/system/multi-user.target.wants/*;\
rm -f /etc/systemd/system/*.wants/*;\
rm -f /lib/systemd/system/local-fs.target.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -f /lib/systemd/system/basic.target.wants/*;\
rm -f /lib/systemd/system/anaconda.target.wants/*;

STOPSIGNAL SIGRTMIN+3

# setting systemd boot target
# multi-user.target: analogous to runlevel 3, Text mode
RUN systemctl set-default multi-user.target
RUN systemctl mask dev-hugepages.mount sys-fs-fuse-connections.mount

# -----------------------------------------------------------------------

RUN yum -y install \
    epel-release \
    http://software.internet2.edu/rpms/el7/x86_64/latest/packages/perfsonar-repo-0.11-1.noarch.rpm \
    && yum -y install \
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

# Initialize the database
RUN su - postgres -c "/usr/pgsql-10/bin/pg_ctl init"

# Overlay the configuration files
COPY postgresql/postgresql.conf /var/lib/pgsql/$PG_VERSION/data/postgresql.conf
COPY postgresql/pg_hba.conf /var/lib/pgsql/$PG_VERSION/data/pg_hba.conf

# Change own user
RUN chown -R postgres:postgres /var/lib/pgsql/$PG_VERSION/data/*

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

# The following ports are used:
# pScheduler: 443
# owamp:861, 8760-9960 (tcp and udp)
# twamp: 862, 18760-19960 (tcp and udp)
# simplestream: 5890-5900
# nuttcp: 5000, 5101
# iperf2: 5001
# iperf3: 5201
# ntp: 123 (udp)
EXPOSE 123/udp 443 861 862 5000 5001 5101 5201 5890-5900 8760-9960/tcp 8760-9960/udp 18760-19960/tcp 18760-19960/udp

# add cgroups, logging, and postgres directory
VOLUME ["/var/lib/pgsql", "/var/log", "/etc/rsyslog.d", "/sys/fs/cgroup" ]

CMD ["/usr/sbin/init"]
