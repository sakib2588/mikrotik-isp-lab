# 2026-08-07 19:27:14 by RouterOS 7.23.3
# system id = C0/HVnWogkN
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
set [ find default-name=ether3 ] disable-running-check=no
/interface pppoe-client
add add-default-route=yes disabled=no interface=ether1 name=pppoe-wan use-peer-dns=\
    yes user=cust001
/ip pool
add name=lan-pool ranges=192.168.88.100-192.168.88.200
/ip address
add address=192.168.56.11/24 comment="Temp management" interface=ether3 network=\
    192.168.56.0
add address=192.168.88.1/24 comment="customer LAN" interface=ether2 network=\
    192.168.88.0
/ip dhcp-client
add interface=ether1 name=client1
/ip dhcp-server
add address-pool=lan-pool interface=ether2 name=lan-dhcp
/ip dhcp-server network
add address=192.168.88.0/24 dns-server=192.168.88.1 gateway=192.168.88.1
/ip dns
set allow-remote-requests=yes servers=10.20.0.1
/ip firewall nat
add action=masquerade chain=srcnat comment="NAT customer LAN" out-interface=\
    pppoe-wan
/system identity
set name=CHR-CPE
