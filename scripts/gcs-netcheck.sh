#!/bin/bash
# GEN2 ground-station network self-check. Run after boot: ~/gcs-netcheck.sh
# Read-only: prints PASS/FAIL/WARN per item; exit code = number of FAILs.

fails=0
pass() { printf '  \e[32mPASS\e[0m %s\n' "$1"; }
fail() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fails=$((fails+1)); }
warn() { printf '  \e[33mWARN\e[0m %s\n' "$1"; }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }

active_on() { nmcli -g GENERAL.CONNECTION device show "$1" 2>/dev/null; }

echo "== LAN (must always work)"
check "br0 active with robot-br"            '[ "$(active_on br0)" = robot-br ]'
check "wlan0 = GEN2-GCS AP"                 '[ "$(active_on wlan0)" = GEN2-GCS ] && iw dev wlan0 info | grep -q "type AP"'
check "eth0 = robot-eth (bridge port)"      '[ "$(active_on eth0)" = robot-eth ]'
check "wlan0 in br0, forwarding"            'bridge link | grep -q "wlan0.*master br0 state forwarding"'
check "eth0 in br0, forwarding"             'bridge link | grep -q "eth0.*master br0 state forwarding"'
check "br0 owns 192.168.50.1/24"            'ip -4 -br addr show br0 | grep -q "192.168.50.1/24"'
check "wlan0/eth0 have no IPv4"             '[ -z "$(ip -4 -o addr show wlan0; ip -4 -o addr show eth0)" ]'
check "dnsmasq active (single DHCP)"        'systemctl is-active -q dnsmasq && [ "$(ss -lunp | grep -c ":67 ")" = 1 ]'
check "NM shared-mode DHCP not running"     '! pgrep -f nm-dnsmasq'
if ping -c2 -W1 192.168.50.2 >/dev/null 2>&1; then pass "EAP225 reachable at 192.168.50.2"
elif ping -c2 -W1 192.168.50.200 >/dev/null 2>&1; then warn "EAP225 still at 192.168.50.200 (moves to .2 on next DHCP renew / EAP reboot)"
else fail "EAP225 not reachable (.2 / .200)"; fi
if ping -c2 -W1 192.168.50.10 >/dev/null 2>&1; then pass "Jetson reachable at 192.168.50.10"
else warn "Jetson 192.168.50.10 not reachable (off, or not configured yet)"; fi
echo "   GCS Wi-Fi clients: $(iw dev wlan0 station dump 2>/dev/null | grep -c ^Station)"

echo "== Internet sharing (only when phone tether is plugged in)"
check "nftables active, NAT loaded"         'systemctl is-active -q nftables && sudo -n nft list table ip gcs_nat'
check "ip_forward = 1"                      '[ "$(sysctl -n net.ipv4.ip_forward)" = 1 ]'
wan=$(ip route show default | awk '{print $5; exit}')
if [ -z "$wan" ]; then
  warn "no default route (phone not tethered) - LAN-only mode, this is OK"
else
  case "$wan" in usb*|enx*) pass "default route via tether ($wan)";; *) fail "default route via $wan (expected usb*/enx*)";; esac
  check "Internet ping 8.8.8.8"             'ping -c2 -W2 8.8.8.8'
fi

echo
[ $fails -eq 0 ] && echo "ALL OK" || echo "$fails FAIL(s)"
exit $fails
