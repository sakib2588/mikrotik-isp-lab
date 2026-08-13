# 2026-08-13 11:32:20 by RouterOS 7.23.3
# system id = 3ATNkTmtEHF
#
/interface bridge
add name=loopback0
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
set [ find default-name=ether3 ] disable-running-check=no
set [ find default-name=ether4 ] disable-running-check=no
/routing ospf instance
add disabled=no name=ospf-core router-id=10.255.255.2
/routing ospf area
add instance=ospf-core name=backbone
/ip address
add address=192.168.56.12/24 interface=ether4 network=192.168.56.0
add address=10.99.0.1/30 interface=ether3 network=10.99.0.0
add address=10.255.255.2 interface=loopback0 network=10.255.255.2
add address=172.16.0.1/30 interface=ether2 network=172.16.0.0
add address=10.255.0.2/30 interface=ether1 network=10.255.0.0
/ip dhcp-client
add interface=ether1 name=client1
/routing ospf interface-template
add area=backbone networks=10.255.0.0/30
add area=backbone networks=10.255.255.2/32 passive
/system identity
set name=CHR-CORE
