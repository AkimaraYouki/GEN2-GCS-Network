#!/bin/bash
# GEN2 ground-station network self-check (EAP225 single-AP topology).
# Run on the Raspberry Pi after boot: ~/gcs-netcheck.sh
# Read-only: prints PASS/FAIL/WARN per item; exit code = number of FAILs.

# 예시 값임. 본인 구성(SSID/IP/인터페이스)에 맞게 바꿀 것. 문서의 값을 그대로 쓰지 말 것.
LAN_IF=eth0
PI_IP=192.168.50.1
EAP_IP=192.168.50.2
JETSON_IP=192.168.50.10

fails=0
pass() { printf '  \e[32mPASS\e[0m %s\n' "$1"; }
fail() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fails=$((fails+1)); }
warn() { printf '  \e[33mWARN\e[0m %s\n' "$1"; }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }

echo "== GEN2 LAN (must always work)"
check "$LAN_IF owns $PI_IP/24"              'ip -4 -br addr show "$LAN_IF" | grep -q "$PI_IP/24"'
check "dnsmasq active"                      'systemctl is-active -q dnsmasq'
check "single DHCP server"                  '[ "$(ss -lunp | grep -c ":67 ")" = 1 ]'
check "NM shared-mode DHCP not running"     '! pgrep -f nm-dnsmasq'
if ping -c2 -W1 "$EAP_IP" >/dev/null 2>&1; then
  pass "EAP225 reachable at $EAP_IP"
else
  eap=$(grep -i eap /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $3; exit}')
  if [ -n "$eap" ] && ping -c2 -W1 "$eap" >/dev/null 2>&1; then
    warn "EAP225 is at $eap, not $EAP_IP (set static IP in EAP UI / DHCP reservation)"
  else
    fail "EAP225 not reachable ($EAP_IP, not in dnsmasq leases either)"
  fi
fi
if ping -c2 -W1 "$JETSON_IP" >/dev/null 2>&1; then pass "Jetson reachable at $JETSON_IP"
else warn "Jetson $JETSON_IP not reachable (off, not on GEN2-ROBOT, or not configured yet)"; fi
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
