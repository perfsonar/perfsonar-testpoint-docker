## perfSONAR 4.0 Testpoint docker container

NOTE: This is a work in progress, and does not yet work correctly!!!

The docker container runs all perfSONAR 4.0 Services in the "Testpoint" bundle, as described at:
http://docs.perfsonar.net/install_options.html

This can be used to run perfSONAR 4.0 Testpoint services on any OS that supports docker.

Download the container:
>docker pull bltierney/perfsonar4.0-testpoint-docker

To register your perfSONAR testpoint, start a container shell, and edit the file
/etc/perfsonar/lsregistrationdaemon.conf with the location and administrator information for your site.

If this host will be part of a centrally configured mesh, also edit the file 
/etc/perfsonar/meshconfig-agent.conf, and update the 'configuration_url'.

>docker run -it bltierney/perfsonar4.0-testpoint-docker /bin/bash

After editing the configuration files, exit the container and commit the change.
> docker commit -m "added config settings" containerID bltierney/perfsonar4.0-testpoint-docker

Run the container:
>docker run -d -P --net=host -v "/var/run,/var/lib/pgsql" bltierney/perfsonar4.0-testpoint-docker

## Testing

Test the perfSONAR tools from another host with pscheduler and owamp installed:
>owping hostname

>pscheduler task clock --source hostname --dest localhost
>pscheduler task throughput --dest hostname

## Notes:
The perfSONAR hostname/IP is assumed to be the same as the base host. To use a different
name/IP for the perfSONAR container, see: https://docs.docker.com/articles/networking/
It also assume the base host is running NTP, and not running httpd, postgres, or anything else 
listening on the list of ports below.

## Security:
make sure the following ports are allowed by the base host:
 pScheduler: 443, bwctl:4823, 5001-5900, 6001-6200 ; owamp:861, 8760-9960
See: http://www.perfsonar.net/deploy/security-considerations/


