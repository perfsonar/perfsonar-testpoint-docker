#!/bin/bash
#
###############################################################################
# NAME: run-testpoint.sh
# 
# USAGE: run-testpoint.sh [options]
# 
# DESCIPTION: 
# This tool initiates a perfSONAR testpoint docker container, and installs a
# pslookup configuration file if not present. (The file should be updated with
# correct details and tool re-run.) 
#
# If the host system already runs apache2, a config is added to map pscheduler
# traffic into the testpoint container.
#
# If the host system is behind a NAT gw, another NAT level is applied for the
# container reapplying the public address detected for the host system. This is
# necessary for the owamp-server inside the container to "be happy".
#
# Most combinations of global ip4 and ip6, and NAT'ed ipv4 and ipv6 addresses
# should be covered.
# 

# Alternativ ports for container
TLSPORT="4443"
WEBPORT="8880"
CONFIGPATH="."
RUNMODE="host"
IMAGE="perfsonar/testpoint:systemd"
HNAME=$(hostname -f)

function usage {
    echo "Usage: `basename $0` [options]"
    echo "-f path                   Path to pslookup configfile. Default '$CONFIGPATH'. Apply 'none' to disable the pslookup service daemon."
    echo "-r run-mode               Force run mode. Valid modes are 'host' and 'nat'. Default is '$RUNMODE'."
    echo "-i image                  Select docker image to apply. Default is $IMAGE."
    echo "-t tls-port               Alternativ TLS port. Default $TLSPORT."
    echo "-w web-port               Alternativ web port. Default $WEBPORT."
    echo "-c                        Only cleanup containers and networks."
    echo "-s                        Only report network state of host."
    echo "-v                        Be verbose."
    echo "-h                        Help message."
    exit 1;
}

function create_ip4_net(){
    # Create docker net with public ipv4 subnet
    # Return public ip
    local PUBIP=$(curl -s https://api.ipify.org)
    if [ -z "$PUBIP" ]; then
	echo "Error: Public ipv4 address not detected." >&2
 	exit 2
    fi
    local SUBIP="${PUBIP%.*}.0/24"
    docker network create --subnet $SUBIP ps-net4 > /dev/null
    echo $PUBIP
}

function create_ip6_net(){
    # Create docker net with public ipv6 subnet
    # Return public ip
    local PUBIP=$(curl -s https://api6.ipify.org)
    if [ -z "$PUBIP" ]; then
	echo "Error: Public ipv6 address not detected." >&2
 	exit 2
    fi
    #local SUBIP="${PUBIP%:*}:0/112"
    if [ -z "$(which subnetcalc)" ]; then
	echo "Error: 'subnetcalc' required. Please install." >&2
	exit 2
    fi
    local SUBIP=$(subnetcalc $PUBIP/64 | grep Network | awk '{print $3}')
    # NOTE: Enabling IPv6 inside containers may result in lost default ipv6 route for host.
    local DEFAULT6GW=$(ip -6 route show default | awk '{print $3}')
    local DEFAULT6DEV=$(ip -6 route show default | awk '{print $5}')
    docker network create --subnet $SUBIP/64 ps-net6 > /dev/null
    if [ "$DEFAULT6GW" -a "$DEFAULT6DEV" -a -z "$(ip -6 route show default)" ]; then
	# Default route is gone. Replace.
	echo "Warning: Replacing lost default ipv6 route for host. This fix overrides routing announcement based default ipv6 routes." >&2
	sudo ip -6 route add default via $DEFAULT6GW dev $DEFAULT6DEV
    fi
    echo $PUBIP
}


# Parse arguments
while getopts ":t:w:i:f:r:chsv" opt; do
    case $opt in
	t)
	    TLSPORT=$OPTARG
	    ;;
	w)
	    WEBPORT=$OPTARG
	    ;;
	f)
	    CONFIGPATH=$OPTARG
	    ;;
	r)
	    RUNMODE=$OPTARG
	    ;;
	i)
	    IMAGE=$OPTARG
	    ;;
	c)
	    CLEANUP_ONLY=1
	    ;;
	s)
	    SHOW_STATE=1
	    ;;
	v)
	    # Output debug info
	    VERBOSE=1
	    ;;
	h)
	    echo "Install server side scripts and crontab for the Micro dependabillity system.";
	    usage
	    ;;
	\?)
	    echo "Invalid option: -$OPTARG" >&2
	    exit 1
	    ;;
	:)
	    echo "Option -$OPTARG requires an argument." >&2
	    exit 1
	    ;;
    esac
done
shift $(($OPTIND - 1))  # (Shift away parsed arguments)


# A n a l y s e   s t a t e   o f   h o s t   s y s t e m 

# Check port status
if [ -z "$(which netstat)" ]; then
    echo "Error: 'netstat' required. Please install net-tools." >&2
    exit 2
fi
if [ "$(netstat -tnlp 2>&1 | grep -e ':443 ')" ]; then
    # Something is listening on port 443
    P443="busy"
fi
if [ "$(netstat -tnlp 2>&1 | grep -e ':80 ')" ]; then
    # Something is listening on port 443
    P80="busy"
fi
if [ "$(netstat -tnlp 2>&1 | grep -e ':$TLSPORT ')" -a "$P443" ]; then
    # To many busy ports
    echo "Error: Both port 443 and $TLSPORT are busy. Apply -t." >&2
    exit 2
fi
if [ "$(netstat -tnlp 2>&1 | grep -e ':$WEBPORT ')" -a "$P80" ]; then
    # To many busy ports
    echo "Error: Both port 80 and $WEBPORT are busy. Apply -w." >&2
    exit 2
fi

# Check IPv4 status
if [ -z "$(which ip)" ]; then
    echo "Error: 'ip' required. Please install iproute2." >&2
    exit 2
fi
GW4=$(ip -4 route show default | awk '{print $3","$5}')
GW4_IP=${GW4%,*}
GW4_DEV=${GW4#*,}
if [[ "$GW4_IP" =~ ^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$ ]]; then
    IP4_ENABLED="yes"
fi
if [[ "$GW4_IP" =~ (^127\.)|(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.) ]]; then
    # Default gw has private (rfc 1918), i.e. host is likely behind NAT.
    NAT4="yes"
else
    GLOBAL4=$(ip -4 addr show dev $GW4_DEV scope global | grep inet | awk '{print $2}' )
fi
# Check IPv6 status
for GW6 in $(ip -6 route show default | awk '{print $3","$5}'); do
    GW6_IP=${GW6%,*}
    GW6_DEV=${GW6#*,}
    if [[ "$GW6_IP" =~ (([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])) ]]; then
	IP6_ENABLED="yes"
	# Assume to be behind NAT
	NAT6="yes"
    fi
    GLOBAL6=$(ip -6 addr show dev $GW6_DEV scope global | grep inet6 | grep -v noprefixroute | awk '{print $2}' )
    
#    if [[ "$GWIP6" =~ 2[0-9a-fA-F]{3}:(([0-9a-fA-F]{1,4}[:]{1,2}){1,6}[0-9a-fA-F]{1,4}) ]]; then
    if [ "$GLOBAL6" ]; then
	# Interface towards default gw has global ipv6 address, i.e. host is not fully behind NAT.
	NAT6=""
	break
    fi
done

# Check web server status
systemctl list-unit-files apache2.service &>/dev/null
if [ $? -eq 0 ]; then
    APACHE2="yes"
fi
systemctl list-unit-files httpd.service &>/dev/null
if [ $? -eq 0 ]; then
    HTTPD="yes"   # (rhel apache)
fi

if [ "$SHOW_STATE" ]; then
    echo "IPv4 enabled: $IP4_ENABLED"
    echo "IPv4 gateway and device: $GW4_IP $GW4_DEV"
    echo "Global IPv4 : $GLOBAL4"
    echo "NAT4: $NAT4"
    echo "IPv6 enabled: $IP6_ENABLED"
    echo "IPv6 gateway and device: $GW6_IP $GW6_DEV"
    echo "Global IPv6 : $GLOBAL6"
    echo "NAT6: $NAT6"
    echo "Port 80 on host: $P80"
    echo "Port 443 on host: $P443"
    exit 0
fi

# A p p l y   a c t i o n s   a c c o r d i n g   t o   h o s t   s y s t e m   s t a t e

if [ -z "$(which docker)" ]; then
    echo "Error: 'docker' required. Please install." >&2
    exit 2
fi
echo "Cleaning up..."
docker kill testpoint 2> /dev/null
docker rm testpoint 2> /dev/null
docker kill testpoint6 2> /dev/null
docker rm testpoint6 2> /dev/null
docker system prune -f 2> /dev/null
docker volume prune -f 2> /dev/null
if [ -f /etc/apache2/conf-available/perfsonar-testpoint-in-docker.conf ]; then
    sudo rm /etc/apache2/conf-available/perfsonar-testpoint-in-docker.conf
fi
echo "done."
if [ "$CLEANUP_ONLY" ]; then exit 0; fi

P443=""
# Rerun port checks after cleanup
if [ "$(netstat -tnlp 2>&1 | grep -e ':443 ')" ]; then
    # Something is listening on port 443
    P443="busy"
fi
P80=""
if [ "$(netstat -tnlp 2>&1 | grep -e ':80 ')" ]; then
    # Something is listening on port 443
    P80="busy"
fi
if [ "$(netstat -tnlp 2>&1 | grep -e ':$TLSPORT ')" -a "$P443" ]; then
    # To many busy ports
    echo "Error: Both port 443 and $TLSPORT are busy. Apply -t." >&2
    exit 2
fi
if [ "$(netstat -tnlp 2>&1 | grep -e ':$WEBPORT ')" -a "$P80" ]; then
    # To many busy ports
    echo "Error: Both port 80 and $WEBPORT are busy. Apply -w." >&2
    exit 2
fi


if [ -z "$IP4_ENABLED" -a -z "$IP6_ENABLED" ]; then
    echo "Error: Host has no network." >2&
    exit 1
fi

if [  "$IP4_ENABLED" -a -z "$NAT4" -a "$IP6_ENABLED" -a -z "$NAT6" -o  "$IP4_ENABLED" -a -z "$NAT4" -a -z "$IP6_ENABLED" -o -z "$IP4_ENABLED" -a "$IP6_ENABLED" -a -z "$NAT6" ]; then
    echo "Host has global ip4+6 stack, or only global ipv4, or only global ipv6."
    echo "Starting testpoint (in host mode publishing all ports)..."
    docker run --restart unless-stopped -d --name testpoint --hostname $HNAME --net=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp -v /sys/fs/cgroup:/sys/fs/cgroup:rw  --cgroupns host "$IMAGE"
    echo "done."

    if [ "$APACHE2" -a "$P443" -o "$APACHE2" -a "$P80" ]; then
	# Fix ports for apache (and pscheduler) in container
	echo  "Reconfig and restart of apache in container..."
	docker exec testpoint sed -i "s/443/$TLSPORT/g"  /etc/apache2/sites-available/default-ssl.conf /etc/apache2/ports.conf  
	docker exec testpoint sed -i "s/80/$WEBPORT/g"  /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf 
	docker exec testpoint systemctl restart apache2
	echo "done."
	
	# Add proxy pass in host to apache in container
	echo  "Reconfig and restart of apache on host..."
	sudo bash -c "echo '
<IfModule proxy_module>	
    ProxyRequests Off					
    <Proxy *>	  					
        <IfVersion >= 2.4>				
            Require all granted				
        </IfVersion>
        <IfVersion < 2.4>
            Order deny,allow
            Allow from all
        </IfVersion>
    </Proxy>
    SSLProxyEngine on
    SSLProxyVerify none
    SSLProxyCheckPeerCN off
    SSLProxyCheckPeerName off
    SSLProxyCheckPeerExpire off
    ProxyPass /pscheduler https://localhost:$TLSPORT/pscheduler status=+I
    ProxyPreserveHost On
</IfModule>	      
'  > /etc/apache2/conf-available/perfsonar-testpoint-in-docker.conf"
	sudo a2enconf perfsonar-testpoint-in-docker
	sudo a2enmod proxy proxy_http
	sudo systemctl restart apache2
	echo "done"
    fi

    if [ "$HTTPD" -a "$P443" -o "$HTTPD" -a "$P80" ]; then
	echo "Warning: HTTPD config needs editing. Not yet implemented..." >2&
    fi   

elif [ "$P443" ]; then
    # To complicated...
    echo "Error: Port 443 busy on host and NAT network detected. Unsupported combination." >&2
    exit 3
fi

if [ "$IP4_ENABLED" -a "$NAT4" -a "$IP6_ENABLED" -a "$NAT6" ]; then
    echo "Host is behind nat4 and nat6."
    
    # Create container networks with public ip-address(es) instide NAT
    echo "Creating ipv4 network..."
    PUBIP4=$(create_ip4_net)
    echo "done."
    echo "Creating ipv6 network..."
    PUBIP6=$(create_ip6_net)
    echo "done."

    # Run container with public IP(s) and port mappings 
    echo "Starting testpoint (in NAT-behind-NAT mode with $PUBIP4 and $PUBIP6 as inner addresses)..."
    docker create --restart unless-stopped --name testpoint --hostname $HNAME --network=ps-net4 --ip=$PUBIP4 -p 443:443/tcp -p 861:861/tcp -p 8760-8800:8760-8800/udp --tmpfs /run --tmpfs /run/lock --tmpfs /tmp -v /sys/fs/cgroup:/sys/fs/cgroup:rw  --cgroupns host "$IMAGE"
    docker network connect --ip6=$PUBIP6 ps-net6 testpoint > /dev/null
    docker start testpoint
    sleep 1   # ... to let container start

    # Adjust port range for owamp server
    docker exec testpoint sed -i 's/testports 8760-9960/testports 8760-8800/g' /etc/owamp-server/owamp-server.conf
    docker exec testpoint systemctl restart owamp-server
    echo "done."
fi

if [ "$IP4_ENABLED" -a "$NAT4" -a -z "$IP6_ENABLED" ]; then
    echo "Host is behind nat4 and has no ipv6."
    
    # Start container with global internal ip4 behind bridge/nat
    # Create container networks with public ip-address(es) inside NAT
    echo "Creating ipv4 network..."
    PUBIP4=$(create_ip4_net)
    echo "done."
    # Run container with public IP(s) and port mappings 
    echo "Starting testpoint (in NAT-behind-NAT mode with $PUBIP4 as inner address)..."
    docker run --restart unless-stopped -d--name testpoint --hostname $HNAME --network=ps-net4 --ip=$PUBIP4 -p 0.0.0.0:443:443/tcp -p 0.0.0.0:861:861/tcp -p 0.0.0.0:8760-8800:8760-8800/udp --tmpfs /run --tmpfs /run/lock --tmpfs /tmp -v /sys/fs/cgroup:/sys/fs/cgroup:rw  --cgroupns host "$IMAGE"
    sleep 1   # ... to let container start
    # Adjust port range for owamp server
    docker exec testpoint sed -i 's/testports 8760-9960/testports 8760-8800/g' /etc/owamp-server/owamp-server.conf
    docker exec testpoint systemctl restart owamp-server
    echo "done."
fi

if [ -z "$IP4_ENABLED" -a "$IP6_ENABLED" -a "$NAT6" ]; then
    echo "Host has no ip4 and is behind nat6."
    
    # Create container networks with public ip-address(es) inside NAT
    echo "Creating ipv6 network..."
    PUBIP6=$(create_ip6_net)
    echo "done."
    # Run container with public IP(s) and port mappings 
    echo "Starting testpoint (in NAT-behind-NAT mode with $PUBIP6 as inner address)..."
    docker run --restart unless-stopped -d--name testpoint --hostname $HNAME --network=ps-net --ip=$PUBIP6 -p [::]:443:443/tcp -p [::]:861:861/tcp -p [::]:8760-8800:8760-8800/udp --tmpfs /run --tmpfs /run/lock --tmpfs /tmp -v /sys/fs/cgroup:/sys/fs/cgroup:rw  --cgroupns host "$IMAGE"
    sleep 1   # ... to let container start

     # Adjust port range for owamp server
    docker exec testpoint sed -i 's/testports 8760-9960/testports 8760-8800/g' /etc/owamp-server/owamp-server.conf
    docker exec testpoint systemctl restart owamp-server
    echo "done."
fi


if [ "$IP4_ENABLED" -a "$NAT4" -a "$IP6_ENABLED" -a -z "$NAT6" ]; then
    echo "Host is behind nat4 but has global ip6."

    # Start ipv4-only container with global internal ip behind bridge/nat
    PUBIP4=$(create_ip4_net)
    echo "Starting ipv4 testpoint (in NAT-behind-NAT mode with $PUBIP4 as inner addresses)..."
    docker run --restart unless-stopped -d --name testpoint --hostname $HNAME --network=ps-net4 --ip=$PUBIP4 -p 0.0.0.0:443:443/tcp -p 0.0.0.0:861:861/tcp -p 0.0.0.0:8760-8800:8760-8800/udp --tmpfs /run --tmpfs /run/lock --tmpfs /tmp -v /sys/fs/cgroup:/sys/fs/cgroup:rw  --cgroupns host "$IMAGE"
    sleep 2   # ... to let container start
    
    # Adjust port range for owamp server
    docker exec testpoint sed -i 's/testports 8760-9960/testports 8760-8800/g' /etc/owamp-server/owamp-server.conf
    docker exec testpoint systemctl restart owamp-server
    echo "done."
    
    # Start ipv6-only container applying host network
    echo "Starting ipv6 testpoint (with host network)..."
    docker run --restart unless-stopped -d --name testpoint6 --hostname $HNAME --net=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp -v /sys/fs/cgroup:/sys/fs/cgroup:rw  --cgroupns host "$IMAGE"

    # Adjust controlport and port range for owamp server
    docker exec testpoint6 sed -i 's/testports 8760-9960/testports 8760-8800/g' /etc/owamp-server/owamp-server.conf
    docker exec testpoint6 bash -c "echo 'srcnode [${GLOBAL6%/*}]:861      # Accept only ipv6 test requests' >> /etc/owamp-server/owamp-server.conf"
    docker exec testpoint6 systemctl restart owamp-server
    # Adjust ports for apache server
    docker exec testpoint6 sed -i "s|80|[${GLOBAL6%/*}]:80|g" /etc/apache2/ports.conf
    docker exec testpoint6 sed -i "s|443|[${GLOBAL6%/*}]:443|g" /etc/apache2/ports.conf
    docker exec testpoint6 systemctl restart apache2
    echo "done."
fi

if [ "$IP4_ENABLED" -a -z "$NAT4" -a "$IP6_ENABLED" -a "$NAT6" ]; then
    echo "Host has global ipv4 but is behind nat6."

    # Start ipv4-only container applying host network
    echo "Starting ipv4 testpoint (with host network)..."
    docker run --restart unless-stopped -d --name testpoint --hostname $HNAME --net=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp -v /sys/fs/cgroup:/sys/fs/cgroup:rw  --cgroupns host "$IMAGE"
    # Adjust ports for apache server
    docker exec testpoint sed -i "s|80|[${GLOBAL4%/*}]:80|g" /etc/apache2/ports.conf
    docker exec testpoint sed -i "s|443|[${GLOBAL4%/*}]:443|g" /etc/apache2/ports.conf
    docker exec testpoint systemctl restart apache2
    echo "done."

    # Start ipv6-only container with global internal ip behind bridge/nat
    PUBIP6=$(create_ip6_net)
    echo "Starting ipv6 testpoint (in NAT-behind-NAT mode with $PUBIP6 as inner addresses)..."
    docker run --restart unless-stopped -d --name testpoint6 --hostname $HNAME --network=ps-net6 --ip=$PUBIP6 -p [::]:443:443/tcp -p [::]:861:861/tcp -p [::]:8760-8800:8760-8800/udp --tmpfs /run --tmpfs /run/lock --tmpfs /tmp -v /sys/fs/cgroup:/sys/fs/cgroup:rw  --cgroupns host "$IMAGE"
    sleep 1   # ... to let container start

    # Adjust port range for owamp server
    docker exec testpoint6 sed -i 's/testports 8760-9960/testports 8760-8800/g' /etc/owamp-server/owamp-server.conf
    docker exec testpoint6 systemctl restart owamp-server
    echo "done."
fi


echo "PSlookup reconfig..."
if [ "$CONFIGPATH" = "none" ]; then
    # Disable pslookup service daemon (ignore errors)
    echo "Disabling pslookup registration..."
    docker exec testpoint systemctl stop perfsonar-lsregistrationdaemon.service 2> /dev/null
else    
    if [ ! -e $CONFIGPATH/lsregistrationdaemon.conf ]; then
    # File missing. Fetch example file
    echo "... config file $CONFIGPATH/lsregistrationdaemon.conf missing. Fetching default example file ...".
    wget -O $CONFIGPATH/lsregistrationdaemon.conf https://raw.githubusercontent.com/perfsonar/ls-registration-daemon/refs/heads/master/lsregistrationdaemon/perfsonar-lsregistrationdaemon/etc/lsregistrationdaemon.conf
    fi

    docker cp -L $CONFIGPATH/lsregistrationdaemon.conf testpoint:/etc/perfsonar/
    docker exec testpoint6 systemctl stop perfsonar-lsregistrationdaemon.service 2> /dev/null    # No need for ls-data from extra ipv6-only container
fi
echo "done."


