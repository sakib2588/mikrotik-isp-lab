# 2026-08-13 11:30:09 by RouterOS 7.23.3
# system id = 1AAnjblFZFN
#
/interface bridge
add name=loopback0
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
set [ find default-name=ether3 ] disable-running-check=no
set [ find default-name=ether4 ] disable-running-check=no
/interface vlan
add comment="access VLAN for PPPoE" interface=ether3 name=vlan100-access \
    vlan-id=100
/ip pool
add name=pppoe-pool ranges=10.20.0.10-10.20.0.250
/ppp profile
add comment="5 Mbps residential" dns-server=10.20.0.1 local-address=10.20.0.1 \
    name=plan-5m rate-limit=5M/5M remote-address=pppoe-pool
add comment="10 Mbps residential" dns-server=10.20.0.1 local-address=\
    10.20.0.1 name=plan-10m rate-limit=10M/10M remote-address=pppoe-pool
/queue type
add kind=pcq name=pcq-download pcq-classifier=dst-address pcq-rate=2M
add kind=pcq name=pcq-upload pcq-classifier=src-address pcq-rate=2M
/queue simple
add comment="shared access capacity" max-limit=20M/20M name=\
    subscriber-aggregate queue=pcq-upload/pcq-download target=10.20.0.0/24
/snmp community
set [ find default=yes ] addresses=192.168.56.0/24 name=lab-ro
/system logging action
add name=syslogNOC remote=10.0.2.2 remote-log-format=syslog src-address=\
    10.0.2.15 syslog-facility=local0 syslog-time-format=iso8601 target=remote
/interface pppoe-server server
add authentication=pap,chap default-profile=plan-5m disabled=no interface=\
    vlan100-access one-session-per-host=yes service-name=SakibNet
/ip address
add address=192.168.56.10/24 comment="Host only management" interface=ether2 \
    network=192.168.56.0
add address=10.255.0.1/30 interface=ether4 network=10.255.0.0
add address=10.255.255.1 interface=loopback0 network=10.255.255.1
/ip dhcp-client
add interface=ether1 name=client1
/ip dns
set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8
/ip firewall address-list
add address=192.168.56.0/24 comment="host-only admin net" list=mgmt
/ip firewall filter
add action=accept chain=input comment="accept return traffic" \
    connection-state=established,related
add action=drop chain=input comment="drop invalid" connection-state=invalid
add action=accept chain=input comment="allow ping for troubleshooting" \
    protocol=icmp
add action=accept chain=input comment="management access" src-address-list=\
    mgmt
add action=drop chain=input comment="drop everything else from WAN" \
    in-interface=ether1
add action=accept chain=forward comment="accept return traffic" \
    connection-state=established,related
add action=drop chain=forward comment="drop invalid" connection-state=invalid
add action=drop chain=forward comment=\
    "drop unsolicited inbound to subscribers" connection-state=new \
    in-interface=ether1
add action=drop chain=input in-interface=ether1 src-address=100.64.0.0/10
add action=drop chain=output dst-address=100.64.0.0/10 out-interface=ether1
add action=drop chain=forward in-interface=ether1 src-address=100.64.0.0/10
add action=drop chain=forward dst-address=100.64.0.0/10 out-interface=ether1
/ip firewall nat
add action=jump chain=srcnat jump-target=clients src-address=\
    100.64.0.51-100.64.0.54
add action=masquerade chain=srcnat comment="NAT subscribers to internet" \
    out-interface=ether1
add action=jump chain=clients jump-target=client-1 src-address=100.64.0.51
add action=src-nat chain=client-1 protocol=tcp src-address=100.64.0.51 \
    to-addresses=192.0.2.1 to-ports=5000-5199
add action=src-nat chain=client-1 protocol=udp src-address=100.64.0.51 \
    to-addresses=192.0.2.1 to-ports=5000-5199
add action=jump chain=clients jump-target=client-2 src-address=100.64.0.52
add action=src-nat chain=client-2 protocol=tcp src-address=100.64.0.52 \
    to-addresses=192.0.2.1 to-ports=5200-5399
add action=src-nat chain=client-2 protocol=udp src-address=100.64.0.52 \
    to-addresses=192.0.2.1 to-ports=5200-5399
add action=jump chain=clients jump-target=client-3 src-address=100.64.0.53
add action=src-nat chain=client-3 protocol=tcp src-address=100.64.0.53 \
    to-addresses=192.0.2.1 to-ports=5400-5599
add action=src-nat chain=client-3 protocol=udp src-address=100.64.0.53 \
    to-addresses=192.0.2.1 to-ports=5400-5599
add action=jump chain=clients jump-target=client-4 src-address=100.64.0.54
add action=src-nat chain=client-4 protocol=tcp src-address=100.64.0.54 \
    to-addresses=192.0.2.1 to-ports=5600-5799
add action=src-nat chain=client-4 protocol=udp src-address=100.64.0.54 \
    to-addresses=192.0.2.1 to-ports=5600-5799
/ip service
set ftp disabled=yes
set telnet disabled=yes
set api disabled=yes
set api-ssl disabled=yes
/ppp aaa
set interim-update=5m use-radius=yes
/ppp secret
add comment="Residential customer 1" disabled=yes name=cust001 profile=\
    plan-5m service=pppoe
add comment="Residential customer 2" name=cust002 profile=plan-10m service=\
    pppoe
/radius
add address=192.168.56.1 comment="FreeRADIUS on popos-mainpc" service=ppp \
    src-address=192.168.56.10 timeout=2s
/snmp
set contact="Nazmus Sakib" enabled=yes location="Home lab, Dhaka"
/system identity
set name=CHR-PE
/system logging
add action=syslogNOC topics=ppp
add action=syslogNOC topics=pppoe
add action=syslogNOC topics=radius
add action=syslogNOC topics=account
add action=syslogNOC topics=firewall
add action=syslogNOC topics=ospf
add action=syslogNOC topics=bgp
add action=syslogNOC topics=mpls
add action=syslogNOC topics=ldp
add action=syslogNOC topics=route
add action=syslogNOC topics=dhcp
add action=syslogNOC topics=interface
add action=syslogNOC topics=system
add action=syslogNOC topics=error
add action=syslogNOC topics=warning
add action=syslogNOC topics=critical
/tool netwatch
add comment="uplink watchdog" down-script=":log error \"UPLINK DOWN\"" host=\
    1.1.1.1 interval=30s type=simple up-script=\
    ":log info \"UPLINK RESTORED\""
