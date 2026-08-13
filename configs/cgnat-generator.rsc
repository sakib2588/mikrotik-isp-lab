{
######## Adjustable values #########
:local StartingAddress 100.64.0.51
:local ClientCount 4
:local AddressesPerClient 1
:local PublicAddress 192.0.2.1
:local StartingPort 5000
:local PortsPerAddress 200
####################################

# All client chain jump
/ip firewall nat add chain=srcnat action=jump jump-target=clients \
    src-address="$StartingAddress-$($StartingAddress + ($ClientCount * $AddressesPerClient) - 1)"

:local currentPort $StartingPort

:for c from=1 to=$ClientCount do={
    # Specific client chain jumps
    :if ($AddressesPerClient > 1) do={
      /ip firewall nat add chain=clients action=jump jump-target="client-$c" \
      src-address="$($StartingAddress + ($AddressesPerClient * ($c - 1)))-$($StartingAddress + ($AddressesPerClient * $c -1))"
    } else={
      /ip firewall nat add chain=clients action=jump jump-target="client-$c" \
      src-address="$($StartingAddress + ($AddressesPerClient * ($c - 1)))"
    }

    # Translation rules
    :for a from=1 to=$AddressesPerClient do={
      /ip firewall nat add chain="client-$c" action=src-nat protocol=tcp \
      src-address="$($StartingAddress + (($c -1) * $AddressesPerClient) + $a - 1)" to-addresses=$PublicAddress to-ports="$currentPort-$($currentPort + $PortsPerAddress - 1)"
      /ip firewall nat add chain="client-$c" action=src-nat protocol=udp \
      src-address="$($StartingAddress + (($c -1) * $AddressesPerClient) + $a - 1)" to-addresses=$PublicAddress to-ports="$currentPort-$($currentPort + $PortsPerAddress - 1)"
      :set currentPort ($currentPort + $PortsPerAddress)
    }
}
}
