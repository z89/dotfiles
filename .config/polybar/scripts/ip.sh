#!/bin/bash
state="$(cat /dev/shm/state)"

! [[ -f "/dev/shm/state" ]] && echo "internal" > /dev/shm/state

ip=$(curl -s https://ipinfo.io/ip)
address=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d '/' -f 1)

## external network address
if [ -z "$ip" ]; then
	externalAddress="  not available"
else	 
	externalAddress="  $ip"
fi


## local network address
if [ -z "$address" ]; then
	internalAddress="󰈀  not connected"
else 
	internalAddress="󰈀  $address"
fi

## program options
case "$1" in
	-s|--switch)
		[[ "$state" == "external" ]] && echo "internal" > /dev/shm/state || echo "external" > /dev/shm/state
	;;
	-f|--fetch)
		[[ "$state" == "external" ]] && echo "$externalAddress" || echo "$internalAddress"
	;;
	-h|--help)
		echo -e "ip.sh was created by z89 for a polybar module\n"
		echo "-s || --switch		choose between an external or internal address"
		echo "-f || --fetch		prints the current address depending on the chosen state"
	;;
	
	*)
		echo "no args specified, see -h || --help for more information"
	;;
esac
