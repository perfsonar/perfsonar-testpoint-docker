# perfSONAR Testpoint

FROM centos:centos7
MAINTAINER Brian Tierney <bltierney@es.net>

RUN yum -y install epel-release
RUN yum -y install http://software.internet2.edu/rpms/el7/x86_64/main/RPMS/Internet2-repo-0.7-1.noarch.rpm 
RUN yum -y update; yum clean all
RUN yum -y install perfsonar-testpoint
RUN yum -y install supervisor net-tools sysstat tcsh tcpdump # grab a few other favorite tools
# initialize pscheduler database
#RUN su postgres -c "/usr/pgsql-9.5/bin/pg_ctl start"
#RUN pscheduler internal db-update
#RUN /usr/pgsql-9.5/bin/pg_ctl stop
# trying another method
RUN service postgresql start && pscheduler internal db-update && service postgresql stop

RUN mkdir -p /var/log/supervisor 
ADD supervisord.conf /etc/supervisord.conf

# The following ports are used:
# pScheduler: 443
# bwctl:4823, 5001-5900, 6001-6200
# owamp:861, 8760-9960
# ranges not supported in docker, so need to use docker run -P to expose all ports

# add pid directory
VOLUME /var/run

CMD /usr/bin/supervisord -c /etc/supervisord.conf

