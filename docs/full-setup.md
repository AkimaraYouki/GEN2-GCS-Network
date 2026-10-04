# Full setup notes

README의 Step 1–9 순서를 그대로 따라가되, 각 단계에서 **통과 조건 / 기대 출력 / 되돌리기**와 인터넷 공유(Step 10–11)를 여기에 모았습니다. 명령어는 README에 있고, 원본 런북에서 바꾼 것은 없습니다.

> 되돌리기를 하기 전에는 Step 1 백업(`scripts/backup-network.sh`)이 있어야 합니다.

## Step 1. 상태 확인 & 백업

- 통과 조건: 각 인터페이스의 역할(어느 것이 SSH 경로인지, 폰이 `usb0`인지 `enx…`인지)을 파악했고, 백업 폴더 `~/netbackup-YYYYMMDD-pre`가 생겼습니다.
- 메모할 것: `ipv4.method shared`인 프로필, 같은 장치에 자동연결이 켜진 프로필 여러 개, `interface-name`이 빈 ethernet 프로필(예: `netplan-eth0`).

## Step 2. br0

기대 결과:

```
manual
no
br0              DOWN           192.168.50.1/24     # 포트가 없어서 DOWN, 정상
dnsmasq 없음
                                                    # nft 출력 비어 있음 (nm-shared 테이블 없음)
```

- 통과 조건: 192.168.50.1을 가진 인터페이스가 `br0` 하나뿐이고, NM이 띄운 dnsmasq와 `nm-shared-br0` nft 테이블이 없습니다.
- 되돌리기: 새로 만들었다면 `sudo nmcli connection delete robot-br`. 수정했다면 백업의 `robot-br.nmconnection`을 복사한 뒤 `sudo nmcli connection reload`.

## Step 3. DHCP (dnsmasq)

기대 결과:

```
active
dnsmasq[...]: started, version 2.91 DNS disabled
dnsmasq-dhcp[...]: DHCP, IP range 192.168.50.100 -- 192.168.50.200, lease time 12h
dnsmasq-dhcp[...]: DHCP, sockets bound exclusively to interface br0
UNCONN 0 0 0.0.0.0:67 0.0.0.0:* users:(("dnsmasq",pid=...))      # 딱 한 줄
```

- 통과 조건: 67번 포트를 듣는 프로세스가 dnsmasq 하나뿐입니다.
- 되돌리기: `sudo systemctl disable --now dnsmasq; sudo rm /etc/dnsmasq.d/gcs-lan.conf`

## Step 4. Wi-Fi 국가코드 + GEN2-GCS

국가코드 기대 결과:

```
global
country KR: DFS-JP
...
 1 wlan      phy0   unblocked unblocked
```

AP 기대 결과:

```
3: wlan0: <...> master br0 state forwarding priority 32 cost 100
	ssid GEN2-GCS
	type AP
	channel 6 (2437 MHz), width: 20 MHz
br0              UP             192.168.50.1/24
```

- 통과 조건: `country KR`, wlan `unblocked`. 노트북이 192.168.50.100–200 주소를 받고 ping/SSH가 됩니다. `/var/lib/misc/dnsmasq.leases`에 노트북이 보입니다.
- 되돌리기: `sudo nmcli connection down GEN2-GCS`

## Step 5. eth0 브리지 편입

기대 결과:

```
2: eth0: <...> master br0 state forwarding priority 32 cost 100
3: wlan0: <...> master br0 state forwarding priority 32 cost 100
eth0           ethernet  connected   robot-eth
wlan0          wifi      connected   GEN2-GCS
```

- 통과 조건: 두 포트 모두 `forwarding`이고 노트북에서 192.168.50.1 ping이 계속 됩니다. 확인되면 3분 안에 `sudo systemctl stop eth0-rollback.timer`.
- 되돌리기: 타이머를 취소하지 않으면 3분 뒤 이전 프로필로 자동 복귀합니다.

## Step 6. EAP225

기대 결과 (leases 예시):

```
1791167945 ec:b9:31:5f:3b:d6 192.168.50.200 EAP225-Outdoor-EC-B9-31-5F-3B-D6 01:ec:b9:31:5f:3b:d6
           └ MAC 주소          └ 지금 주소
```

- 통과 조건: Pi와 노트북 둘 다에서 192.168.50.2가 응답하고, EAP UI에서 `GEN2-ROBOT`이 송출 중입니다.
- 되돌리기: EAP 리셋 버튼으로 공장 초기화.

## Step 7. Jetson

- 통과 조건: 노트북에서 .1, .2, .10 모두 응답하고, `iw dev $IF get power_save`가 `off`입니다. 폰 테더링이 꽂혀 있으면 Jetson에서 `ping 8.8.8.8`도 됩니다.
- 되돌리기: `sudo nmcli connection delete GEN2-ROBOT` (Jetson에서 새로 만든 프로필일 때)

## Step 8. 검증

[ros2-test.md](ros2-test.md) 참고.

## Step 9. 점검 스크립트 & 재부팅

2026-10-04 실측 출력 (Jetson 설정 전):

```
== LAN (must always work)
  PASS br0 active with robot-br
  PASS wlan0 = GEN2-GCS AP
  PASS eth0 = robot-eth (bridge port)
  PASS wlan0 in br0, forwarding
  PASS eth0 in br0, forwarding
  PASS br0 owns 192.168.50.1/24
  PASS wlan0/eth0 have no IPv4
  PASS dnsmasq active (single DHCP)
  PASS NM shared-mode DHCP not running
  WARN EAP225 still at 192.168.50.200 (moves to .2 on next DHCP renew / EAP reboot)
  WARN Jetson 192.168.50.10 not reachable (off, or not configured yet)
   GCS Wi-Fi clients: 2
== Internet sharing (only when phone tether is plugged in)
  PASS nftables active, NAT loaded
  PASS ip_forward = 1
  PASS default route via tether (usb0)
  PASS Internet ping 8.8.8.8

ALL OK
```

- 통과 조건: 마지막 줄이 `ALL OK`. WARN은 실패가 아니라 아직 안 끝난 항목입니다. 재부팅 후 손대지 않은 상태에서도 `ALL OK`여야 합니다.

---

# Internet sharing (optional)

**선택사항입니다.** 로봇 네트워크는 이 부분 없이 동작합니다. 인터넷 공유를 안 쓸 팀이라면 README Step 3의 dnsmasq 설정을 `dhcp-option=option:router` 한 줄 버전으로 쓰고 Step 10–11은 건너뜁니다.

## Step 10. USB 테더링 WAN 프로필

Raspberry Pi OS가 만든 `netplan-eth0`는 이름과 달리 `interface-name`이 비어 있어서 **모든 유선 장치**에 매칭됩니다. 폰을 잡아 주기는 하지만 부팅 순서에 따라 `eth0`를 가로채 DHCP 클라이언트로 만들 수 있습니다. 그래서 `usb*`/`enx*`에만 붙는 전용 프로필로 바꿨습니다.

Pi — 폰 꽂고 USB 테더링 켠 뒤 이름 확인:

```bash
nmcli device status
ip -br link | grep -E '^(usb|enx)'
nmcli -g connection.interface-name connection show netplan-eth0   # 비어 있으면 와일드카드
```

전용 프로필 만들고 와일드카드 프로필 끄기:

```bash
sudo nmcli connection add type ethernet con-name wan-tether \
  match.interface-name "usb* enx*" ipv4.method auto ipv4.route-metric 100 ipv6.method auto \
  connection.autoconnect yes connection.autoconnect-priority 5
sudo nmcli connection modify netplan-eth0 connection.autoconnect no    # 삭제하지 않음
sudo nmcli connection up wan-tether ifname usb0                      # 위에서 확인한 이름
```

확인:

```bash
nmcli device status | grep -E 'usb|enx'
ip route show default
ping -c 3 8.8.8.8
```

기대 결과:

```
usb0           ethernet  connected               wan-tether
default via 192.168.139.55 dev usb0 proto dhcp src 192.168.139.166 metric 100
3 packets transmitted, 3 received, 0% packet loss
```

- 통과 조건: 기본 경로가 테더링 인터페이스 하나뿐이고 `br0`에는 기본 경로가 없습니다. 폰을 뽑았다 다시 꽂으면 `wan-tether`로 자동 연결됩니다.
- 되돌리기: `sudo nmcli connection modify netplan-eth0 connection.autoconnect yes; sudo nmcli connection delete wan-tether`

## Step 11. NAT & IPv4 포워딩

`br0`에서 테더링으로 나가는 트래픽만 마스커레이드합니다. 응답 트래픽은 허용하고 폰 쪽에서 LAN으로 새로 들어오는 연결은 막습니다. 브리지 안의 L2 트래픽(ROS 2 멀티캐스트 포함)은 이 규칙을 거치지 않습니다.

포워딩 영구 설정 (예시 파일: [config/examples/90-gcs-forward.conf](../config/examples/90-gcs-forward.conf)):

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/90-gcs-forward.conf
sudo sysctl -p /etc/sysctl.d/90-gcs-forward.conf
```

`/etc/nftables.conf` (기존 파일은 Step 1에서 백업됨). 내용은 [config/examples/nftables.conf](../config/examples/nftables.conf)와 같습니다:

```bash
sudo tee /etc/nftables.conf >/dev/null <<'EOT'
#!/usr/sbin/nft -f
# GEN2 ground station: share Android USB tether (usb*/enx*) with robot LAN br0.
# Bridged LAN traffic (wlan0<->eth0, ROS 2 multicast) is L2 and never hits these hooks.

flush ruleset

table inet gcs_filter {
	chain forward {
		type filter hook forward priority filter; policy drop;
		ct state established,related accept
		iifname "br0" oifname "usb*" accept
		iifname "br0" oifname "enx*" accept
		iifname "br0" oifname "br0" accept
	}
}

table ip gcs_nat {
	chain postrouting {
		type nat hook postrouting priority srcnat; policy accept;
		oifname "usb*" ip saddr 192.168.50.0/24 masquerade
		oifname "enx*" ip saddr 192.168.50.0/24 masquerade
	}
}
EOT
sudo nft -c -f /etc/nftables.conf && echo SYNTAX_OK
sudo systemctl enable --now nftables
```

(원본은 heredoc 종료 문자가 `EOF`인데, 이 문서에서는 그대로 복붙해도 겹치지 않도록 `EOT`로만 바꿨습니다. 내용은 동일합니다.)

확인:

```bash
systemctl is-active nftables
sudo nft list tables
sysctl net.ipv4.ip_forward
```

기대 결과:

```
active
table inet gcs_filter
table ip gcs_nat
net.ipv4.ip_forward = 1
```

노트북에서 Wi-Fi를 껐다 켜서 게이트웨이를 새로 받은 뒤:

```bash
ping -c 5 8.8.8.8
curl -sI https://www.google.com | head -1
```

- 통과 조건: 노트북에서 인터넷이 되고, 폰을 뽑아도 192.168.50.x끼리는 계속 통신됩니다.
- 되돌리기: `sudo systemctl disable --now nftables; sudo rm /etc/sysctl.d/90-gcs-forward.conf; sudo sysctl -w net.ipv4.ip_forward=0`

---

# 전체 되돌리기

Step 1 백업으로 원래 상태로 돌립니다. 새로 만든 프로필은 이름으로 지웁니다. **로컬 콘솔에서 실행하세요** (Wi-Fi 경로가 끊길 수 있음).

```bash
B=~/netbackup-YYYYMMDD-pre
sudo systemctl disable --now nftables dnsmasq
sudo rm -f /etc/sysctl.d/90-gcs-forward.conf /etc/dnsmasq.d/gcs-lan.conf
[ -f $B/nftables.conf.orig ] && sudo cp $B/nftables.conf.orig /etc/nftables.conf
sudo nmcli connection delete wan-tether robot-eth 2>/dev/null      # 이 런북에서 새로 만든 것만
sudo cp -a $B/etc-NetworkManager/system-connections/. /etc/NetworkManager/system-connections/
sudo nmcli connection reload
sudo nmcli connection modify netplan-eth0 connection.autoconnect yes
sudo sysctl -w net.ipv4.ip_forward=0
sudo reboot
```

# 최종 파일 목록 (Pi)

| 파일 | 역할 |
| --- | --- |
| `/etc/NetworkManager/system-connections/robot-br.nmconnection` | br0, 192.168.50.1/24, STP off |
| `/etc/NetworkManager/system-connections/GEN2-GCS.nmconnection` | wlan0 AP, WPA2, br0 포트, PSK 저장 |
| `/etc/NetworkManager/system-connections/robot-eth.nmconnection` | eth0 → br0 포트, 우선순위 10 |
| `/etc/NetworkManager/system-connections/wan-tether.nmconnection` | usb\*/enx\* DHCP WAN, metric 100 |
| `/etc/dnsmasq.d/gcs-lan.conf` | 유일한 DHCP 서버, EAP MAC 예약 |
| `/etc/nftables.conf` | br0 → 테더링 NAT, 인바운드 차단 |
| `/etc/sysctl.d/90-gcs-forward.conf` | IPv4 포워딩 영구 설정 |
| `~/gcs-netcheck.sh` | 상태 점검 스크립트 |

자동연결만 꺼 두고 남겨 둔 프로필: `eap-mgmt`(예전 eth0 192.168.0.10), `netplan-eth0`(와일드카드 유선 DHCP).
