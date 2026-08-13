# 2026-08-13 11:40:40 by RouterOS 7.23.3
# system id = ePHbsYLgLhG
#
/interface bridge
add name=loopback0
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
/routing bgp instance
add as=65100 name=as65100 router-id=10.255.255.4
/ip address
add address=192.168.56.14/24 interface=ether2 network=192.168.56.0
add address=10.99.0.2/30 interface=ether1 network=10.99.0.0
add address=10.255.255.4 interface=loopback0 network=10.255.255.4
/ip dhcp-client
add interface=ether1 name=client1
/ip firewall address-list
add address=198.51.100.0/24 list=MY-NETWORKS
/ip route
add blackhole dst-address=198.51.100.0/24
/routing bgp connection
add instance=as65100 local.address=10.99.0.2 .role=ebgp name=core-link \
    output.network=MY-NETWORKS remote.address=10.99.0.1 .as=65001
/system identity
set name=CHR-BDIX
