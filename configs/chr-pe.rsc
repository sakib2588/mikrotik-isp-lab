# 2026-08-07 19:37:59 by RouterOS 7.23.3
# system id = 1AAnjblFZFN
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
set [ find default-name=ether3 ] disable-running-check=no
/interface vlan
add comment="access VLAN for PPPoE" interface=ether3 \
    name=vlan100-access vlan-id=100
/ip pool
add name=pppoe-pool ranges=10.20.0.10-10.20.0.250
/ppp profile
add comment="5 Mbps residential" dns-server=10.20.0.1 \
    local-address=10.20.0.1 name=plan-5m rate-limit=5M/5M \
    remote-address=pppoe-pool
add comment="10 Mbps residential" dns-server=10.20.0.1 \
    local-address=10.20.0.1 name=plan-10m rate-limit=\
    10M/10M remote-address=pppoe-pool
/interface pppoe-server server
add authentication=pap,chap default-profile=plan-5m \
    disabled=no interface=vlan100-access \
    one-session-per-host=yes service-name=SakibNet
/ip address
add address=192.168.56.10/24 comment=\
    "Host only management" interface=ether2 network=\
    192.168.56.0
/ip dhcp-client
add interface=ether1 name=client1
/ip dns
set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8
/ip firewall address-list
add address=192.168.56.0/24 comment="host-only admin net" \
    list=mgmt
/ip firewall filter
add action=accept chain=input comment=\
    "accept return traffic" connection-state=\
    established,related
add action=drop chain=input comment="drop invalid" \
    connection-state=invalid
add action=accept chain=input comment=\
    "allow ping for troubleshooting" protocol=icmp
add action=accept chain=input comment="management access" \
    src-address-list=mgmt
add action=drop chain=input comment=\
    "drop everything else from WAN" in-interface=ether1
add action=accept chain=forward comment=\
    "accept return traffic" connection-state=\
    established,related
add action=drop chain=forward comment="drop invalid" \
    connection-state=invalid
add action=drop chain=forward comment=\
    "drop unsolicited inbound to subscribers" \
    connection-state=new in-interface=ether1
/ip firewall nat
add action=masquerade chain=srcnat comment=\
    "NAT subscribers to internet" out-interface=ether1
/ip service
set ftp disabled=yes
set telnet disabled=yes
set api disabled=yes
set api-ssl disabled=yes
/ppp secret
add comment="Residential customer 1" name=cust001 \
    profile=plan-5m service=pppoe
add comment="Residential customer 2" name=cust002 \
    profile=plan-10m service=pppoe
/system identity
set name=CHR-PE
