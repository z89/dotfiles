#!/bin/bash
state="$(cat /dev/shm/state)"

! [[ -f "/dev/shm/state" ]] && echo "internal" > /dev/shm/state

ip=$(curl -s https://ipinfo.io/ip)
ethernet=$(ip -4 addr show enp7s0 | grep -oP "(?<=inet ).*(?=/)")
wireless=$(ip -4 addr show wlan0 | grep -oP "(?<=inet ).*(?=/)")

## external network address
if [ -z "$ip" ]; then
	externalAddress="  not available"
else	 
	externalAddress="  $ip"
fi


## local network address
if [ -z "$ethernet" ]; then
	if [ -z "$wireless" ]; then
		internalAddress="󰖪  not available"
	else 
		internalAddress="󰖩  $wireless"
	fi
else 
	internalAddress="󰈀  $ethernet"
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
