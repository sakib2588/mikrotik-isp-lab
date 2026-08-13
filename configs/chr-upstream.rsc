# 2026-08-13 11:30:14 by RouterOS 7.23.3
# system id = IUXPpFKZwMO
#
/interface bridge
add name=loopback0
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
/ip address
add address=192.168.56.13/24 interface=ether2 network=192.168.56.0
add address=172.16.0.2/30 interface=ether1 network=172.16.0.0
add address=10.255.255.3 interface=loopback0 network=10.255.255.3
/ip dhcp-client
add interface=ether1 name=client1
/system identity
set name=CHR-UPSTREAM
