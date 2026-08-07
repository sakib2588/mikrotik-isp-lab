# 2026-08-07 18:36:09 by RouterOS 7.23.3
# system id = 1AAnjblFZFN
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
set [ find default-name=ether3 ] disable-running-check=no
/ip address
add address=192.168.56.10/24 comment="Host only management" interface=ether2 network=192.168.56.0
/ip dhcp-client
add interface=ether1 name=client1
/ip dns
set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8
/ip service
set ftp disabled=yes
set telnet disabled=yes
set api disabled=yes
set api-ssl disabled=yes
/system identity
set name=CHR-PE
