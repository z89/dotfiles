#!/bin/bash
externalAddress="  $(curl -s https://ipinfo.io/ip)"

! [[ -f "/dev/shm/state" ]] && echo "internal" > /dev/shm/state

state="$(cat /dev/shm/state)"

ethernet=$(ip -4 addr show enp5s0 | grep -oP "(?<=inet ).*(?=/)")
wireless=$(ip -4 addr show wlan0 | grep -oP "(?<=inet ).*(?=/)")

if [ -z "$ethernet" ]; then
	if [ -z "$wireless" ]; then
		internalAddress="睊  127.0.0.1"
	else 
		internalAddress="直  $wireless"
	fi
else 
	internalAddress="  $ethernet"
fi

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
