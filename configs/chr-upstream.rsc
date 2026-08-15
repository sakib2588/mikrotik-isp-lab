# 2026-08-15 10:24:00 by RouterOS 7.23.3
# system id = IUXPpFKZwMO
#
/interface bridge
add name=loopback0
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
/routing bgp instance
add as=65002 name=as65002 router-id=10.255.255.3
/snmp community
set [ find default=yes ] addresses=192.168.56.0/24 name=lab-ro
/ip address
add address=192.168.56.13/24 interface=ether2 network=192.168.56.0
add address=172.16.0.2/30 interface=ether1 network=172.16.0.0
add address=10.255.255.3 interface=loopback0 network=10.255.255.3
/ip dhcp-client
add interface=ether1 name=client1
/ip firewall address-list
add address=203.0.113.0/24 list=MY-NETWORKS
add address=0.0.0.0/0 list=MY-NETWORKS
/ip route
add blackhole dst-address=203.0.113.0/24
add blackhole distance=254 dst-address=0.0.0.0/0
/routing bgp connection
add instance=as65002 local.address=172.16.0.2 .role=ebgp name=core-link \
    output.network=MY-NETWORKS remote.address=172.16.0.1 .as=65001
/snmp
set contact="Nazmus Sakib" enabled=yes location="Home lab, Dhaka"
/system identity
set name=CHR-UPSTREAM
