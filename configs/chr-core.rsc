# 2026-08-15 10:23:59 by RouterOS 7.23.3
# system id = 3ATNkTmtEHF
#
/interface bridge
add name=loopback0
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
set [ find default-name=ether3 ] disable-running-check=no
set [ find default-name=ether4 ] disable-running-check=no
/routing bgp instance
add as=65001 name=as65001 router-id=10.255.255.2
/routing ospf instance
add disabled=no name=ospf-core router-id=10.255.255.2
/routing ospf area
add instance=ospf-core name=backbone
/snmp community
set [ find default=yes ] addresses=192.168.56.0/24 name=lab-ro
/ip address
add address=192.168.56.12/24 interface=ether4 network=192.168.56.0
add address=10.99.0.1/30 interface=ether3 network=10.99.0.0
add address=10.255.255.2 interface=loopback0 network=10.255.255.2
add address=172.16.0.1/30 interface=ether2 network=172.16.0.0
add address=10.255.0.2/30 interface=ether1 network=10.255.0.0
/ip dhcp-client
add interface=ether1 name=client1
/ip firewall address-list
add address=192.0.2.0/24 list=MY-NETWORKS
/ip route
add blackhole dst-address=192.0.2.0/24
/routing bgp connection
add disabled=no instance=as65001 local.address=172.16.0.1 .role=ebgp name=\
    upstream-link output.filter-chain=upstream-out .network=MY-NETWORKS \
    remote.address=172.16.0.2 .as=65002
add instance=as65001 local.address=10.255.255.2 .role=ibgp name=pe-link \
    nexthop-choice=force-self remote.address=10.255.255.1 .as=65001
add input.filter=bdix-in instance=as65001 local.address=10.99.0.1 .role=ebgp \
    name=bdix-link nexthop-choice=force-self output.filter-chain=bdix-out \
    .network=MY-NETWORKS remote.address=10.99.0.2 .as=65100
/routing filter rule
add chain=bdix-in rule="if (dst in 198.51.100.0/24 && dst-len in 24-24) { set \
    bgp-local-pref 200; accept; }"
add chain=bdix-in rule="reject;"
add chain=bdix-out rule="if (dst == 192.0.2.0/24) { accept; }"
add chain=bdix-out rule="reject;"
add chain=upstream-out rule="if (dst == 192.0.2.0/24) { accept; }"
add chain=upstream-out rule="reject;"
/routing ospf interface-template
add area=backbone networks=10.255.0.0/30
add area=backbone networks=10.255.255.2/32 passive
/snmp
set contact="Nazmus Sakib" enabled=yes location="Home lab, Dhaka"
/system identity
set name=CHR-CORE
