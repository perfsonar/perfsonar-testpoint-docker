## perfSONAR 4.X Testpoint docker container

NOTE: This now seems to be working. Testers needed. Please submit problems to:
  https://github.com/perfsonar/perfsonar-testpoint-docker/issues

The docker container runs all perfSONAR 4.x Services in the "Testpoint" bundle, as described at:
https://github.com/perfsonar/perfsonar-testpoint-docker/issues

This can be used to run perfSONAR 4.x Testpoint services on any OS that supports docker.

Download the container:
>docker pull perfsoanr/testpoint

To register your perfSONAR testpoint, start a container shell, and edit the file
/etc/perfsonar/lsregistrationdaemon.conf with the location and administrator information for your site.

If this host will be part of a centrally configured mesh, also edit the file 
/etc/perfsonar/meshconfig-agent.conf, and update the 'configuration_url'.

>docker run -it perfsonar/testpoint /bin/bash

After editing the configuration files, exit the container and commit the change.
> docker commit -m "added config settings" containerID perfsonar/testpoint

Run the container:
>docker run -d -P --net=host -v "/var/run" perfsonar/testpoint

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


