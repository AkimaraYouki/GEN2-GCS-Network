#!/bin/bash
# GEN2 GCS: 네트워크 설정을 바꾸기 전에 Pi에서 한 번 실행하는 백업.

B=~/netbackup-$(date +%Y%m%d)-pre; mkdir -p $B
sudo cp -a /etc/NetworkManager $B/etc-NetworkManager
sudo cp -a /run/NetworkManager/system-connections $B/run-nm-system-connections 2>/dev/null
sudo cp -a /etc/netplan $B/etc-netplan
sudo cp -a /etc/dnsmasq.d $B/etc-dnsmasq.d 2>/dev/null
sudo cp -a /etc/sysctl.d $B/sysctl.d
sudo cp -a /etc/nftables.conf $B/nftables.conf.orig 2>/dev/null
sudo nft list ruleset > $B/nft-ruleset.txt
{ nmcli connection show; nmcli device status; ip -br addr; ip route; } > $B/state.txt
sudo chown -R $USER: $B; chmod -R go-rwx $B; ls $B
