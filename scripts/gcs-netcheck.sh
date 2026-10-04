#!/bin/bash
# GEN2 ground-station network self-check (EAP225 single-AP topology).
# Run on the Raspberry Pi after boot: ~/gcs-netcheck.sh
# Read-only: prints PASS/FAIL/WARN per item; exit code = number of FAILs.

fails=0
pass() { printf '  \e[32mPASS\e[0m %s\n' "$1"; }
fail() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fails=$((fails+1)); }
warn() { printf '  \e[33mWARN\e[0m %s\n' "$1"; }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }

echo "== GEN2 LAN (must always work)"
check "eth0 owns 192.168.50.1/24"           'ip -4 -br addr show eth0 | grep -q "192.168.50.1/24"'
check "dnsmasq active"                      'systemctl is-active -q dnsmasq'
check "single DHCP server"                  '[ "$(ss -lunp | grep -c ":67 ")" = 1 ]'
check "NM shared-mode DHCP not running"     '! pgrep -f nm-dnsmasq'
if ping -c2 -W1 192.168.50.2 >/dev/null 2>&1; then
  pass "EAP225 reachable at 192.168.50.2"
else
  eap=$(grep -i eap /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $3; exit}')
  if [ -n "$eap" ] && ping -c2 -W1 "$eap" >/dev/null 2>&1; then
    warn "EAP225 is at $eap, not 192.168.50.2 (set static IP in EAP UI / DHCP reservation)"
  else
    fail "EAP225 not reachable (192.168.50.2, not in dnsmasq leases either)"
  fi
fi
if ping -c2 -W1 192.168.50.10 >/dev/null 2>&1; then pass "Jetson reachable at 192.168.50.10"
else warn "Jetson 192.168.50.10 not reachable (off, not on GEN2-ROBOT, or not configured yet)"; fi
n=$(grep -c . /var/lib/misc/dnsmasq.leases 2>/dev/null)
echo "   DHCP leases: ${n:-0}"

echo
echo "== Optional Internet (only when phone tether is plugged in)"
wan=$(ip route show default | awk '{print $5; exit}')
if [ -z "$wan" ]; then
  warn "phone tether not connected - LAN-only mode, this is OK"
else
  case "$wan" in
    usb*|enx*) pass "default route via $wan";;
    *) warn "default route via $wan (not a USB tether; NAT in nftables only covers usb*/enx*)";;
  esac
  check "ip_forward = 1"                    '[ "$(sysctl -n net.ipv4.ip_forward)" = 1 ]'
  check "nftables active, NAT loaded"       'systemctl is-active -q nftables && sudo -n nft list table ip gcs_nat'
  check "Internet connectivity"             'ping -c2 -W2 8.8.8.8'
fi

echo
[ $fails -eq 0 ] && echo "ALL OK" || echo "$fails FAIL(s)"
exit $fails
