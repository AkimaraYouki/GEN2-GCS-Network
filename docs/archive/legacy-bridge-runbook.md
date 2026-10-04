> [!WARNING]
> This document describes an earlier GEN2 network architecture where the Raspberry Pi provided the GEN2-GCS Wi-Fi AP and bridged wlan0 to eth0.
>
> This architecture is no longer used.
>
> See the current README and `docs/full-setup.md` for the final EAP225-centered design.
>
> 아래 내용은 **사용하지 않는 이전 구성**입니다. 디버깅 경험(문제 해결 표 등)을 남기려고 보관만 합니다. 이 문서의 명령어를 따라 하지 마세요.

GEN2 · Ground Station · Raspberry Pi 4

> 공개 저장소용으로 EAP225의 실제 MAC 주소만 `aa:bb:cc:dd:ee:ff` 예시 값으로 바꿨습니다. 그 외에는 원본 그대로입니다.

# GEN2 GCS 네트워크 구축 런북

라즈베리파이 4 한 대로 지상국 Wi-Fi(GEN2-GCS), EAP225 로봇 AP, Jetson을 하나의 192.168.50.0/24 LAN으로 묶고, 안드로이드 USB 테더링이 꽂혀 있을 때만 인터넷을 공유하는 구성입니다. 위에서부터 순서대로 실행하면 됩니다. 각 단계의 통과 조건을 확인한 뒤 다음 단계로 넘어가세요.

Raspberry Pi OS Lite (Debian 13) kernel 6.18 rpt NetworkManager 1.52.1 dnsmasq 2.91 nftables 1.1.3 검증일 2026-10-04

단계 목차

1. [··구성 개요](#overview)
2. [01상태 확인 & 백업](#s1)
3. [02Wi-Fi 국가코드](#s2)
4. [03br0 브리지](#s3)
5. [04DHCP (dnsmasq)](#s4)
6. [05GEN2-GCS AP](#s5)
7. [06eth0 브리지 편입](#s6)
8. [07EAP225 설정](#s7)
9. [08USB 테더링 WAN](#s8)
10. [09NAT & 포워딩](#s9)
11. [10Jetson 설정](#s10)
12. [11점검 스크립트](#s11)
13. [12재부팅 검증](#s12)
14. [13ROS 2 확인](#s13)
15. [14성능 측정](#s14)
16. [··문제 해결](#trouble)
17. [··전체 되돌리기](#rollback)
18. [··최종 파일 목록](#files)

## 구성 개요

```
  Android phone (LTE/5G)
        |  USB tethering
        v
  usb0 / enx...      WAN: DHCP from phone, NAT out (only when plugged in)
  +--------------------------------------------------------------+
  |  Raspberry Pi 4                                              |
  |    br0 = 192.168.50.1/24      dnsmasq = only DHCP server     |
  |     +-- wlan0   Wi-Fi AP "GEN2-GCS"  (2.4 GHz ch 6, WPA2)    |
  |     +-- eth0    -------------------------+                   |
  +------------------------------------------|-------------------+
        | Wi-Fi                              | Ethernet
        v                                    v
  GCS laptop                       TP-Link EAP225-Outdoor  192.168.50.2
  DHCP 192.168.50.100-200                    | Wi-Fi "GEN2-ROBOT"
                                             v
                                   Jetson Orin Nano        192.168.50.10
```

### 주소 계획

| 장비 | 주소 | 방식 |
| --- | --- | --- |
| Raspberry Pi `br0` | 192.168.50.1/24 | NM 수동 설정 (브리지에만 IP) |
| EAP225-Outdoor | 192.168.50.2 | EAP 고정 IP + dnsmasq MAC 예약 |
| Jetson Orin Nano | 192.168.50.10 | Jetson 고정 IP |
| GCS 노트북 등 | 192.168.50.100 – .200 | dnsmasq DHCP, 임대 12시간 |

### 설계 원칙

- LAN은 L2 브리지 하나입니다. ROS 2 DDS 멀티캐스트가 wlan0와 eth0 사이를 그대로 오가고, 방화벽을 거치지 않습니다.
- DHCP 서버는 dnsmasq 하나뿐입니다. NetworkManager의 `ipv4.method shared`는 쓰지 않습니다. 둘을 같이 쓰면 `Address already in use`로 dnsmasq가 죽습니다.
- IPv4 주소는 `br0`만 가집니다. `wlan0`와 `eth0`는 주소 없는 브리지 포트입니다.
- 폰이 없으면 인터넷만 끊기고, 노트북 ↔ Pi ↔ EAP ↔ Jetson 통신과 ROS 2는 그대로 동작합니다.
- 로봇 밸런스 제어 루프는 이 네트워크를 쓰지 않습니다(Jetson 로컬 IMU + CAN). 이 망은 텔레옵, ROS 2 토픽, SLAM 시각화, SSH, 카메라 미리보기용입니다.

**기존 프로필은 지우지 않습니다.** 이미 설정이 일부 되어 있는 Pi라면 프로필을 삭제하지 말고 `connection.autoconnect no`로 끄세요. 되돌릴 때 그대로 다시 켜면 됩니다.

Part A · Raspberry Pi 기본 LAN

## 01현재 상태 확인 & 백업

인터페이스 이름과 프로필 이름은 Pi마다 다릅니다. 짐작하지 말고 먼저 읽어보세요. 이 단계에서는 아무것도 바꾸지 않습니다.

Pi · 상태 확인

```
nmcli device status
nmcli connection show
ip -br addr
ip route
bridge link
sysctl net.ipv4.ip_forward
systemctl status dnsmasq --no-pager
sudo nft list ruleset
pgrep -a dnsmasq
who    # 내 SSH가 어느 IP로 들어와 있는지 확인
```

Pi · 백업

```
B=~/netbackup-$(date +%Y%m%d)-pre; mkdir -p $B
sudo cp -a /etc/NetworkManager $B/etc-NetworkManager
sudo cp -a /run/NetworkManager/system-connections $B/run-nm-system-connections 2>/dev/null
sudo cp -a /etc/netplan $B/etc-netplan
sudo cp -a /etc/sysctl.d $B/sysctl.d
sudo cp -a /etc/nftables.conf $B/nftables.conf.orig 2>/dev/null
sudo nft list ruleset > $B/nft-ruleset.txt
{ nmcli connection show; nmcli device status; ip -br addr; ip route; } > $B/state.txt
sudo chown -R $USER: $B; chmod -R go-rwx $B; ls $B
```

통과 조건

각 인터페이스의 역할(어느 것이 SSH 경로인지, 폰이 `usb0`인지 `enx…`인지)을 파악했고, 백업 폴더가 생겼습니다.

**살펴볼 것.** `ipv4.method shared`인 프로필, 같은 장치(eth0 등)에 자동연결이 켜진 프로필 여러 개, `interface-name`이 비어 있는 ethernet 프로필(예: `netplan-eth0`, 모든 유선 장치에 매칭됨)이 있으면 메모해 두세요. 뒤 단계에서 정리합니다.

## 02Wi-Fi 국가코드

국가코드가 없으면 라즈베리파이 OS가 Wi-Fi를 rfkill로 막아 둡니다. AP를 띄우기 전에 한 번만 설정합니다.

Pi

```
sudo raspi-config nonint do_wifi_country KR
sudo rfkill unblock wlan
iw reg get | head -3
rfkill
```

기대 결과

```
global
country KR: DFS-JP
...
 1 wlan      phy0   unblocked unblocked
```

통과 조건

`country KR`이고 wlan이 `unblocked`입니다.

## 03br0 브리지 만들기

LAN 주소 192.168.50.1은 브리지 `br0`만 가집니다. 수동 IP, 기본 경로 없음, STP 끔(포트가 붙을 때 30초 지연을 없앰).

Pi · robot-br 프로필이 없을 때

```
sudo nmcli connection add type bridge con-name robot-br ifname br0 \
  ipv4.method manual ipv4.addresses 192.168.50.1/24 ipv4.never-default yes \
  ipv6.method disabled bridge.stp no connection.autoconnect yes
```

Pi · 이미 있을 때 (특히 ipv4.method가 shared였다면)

```
sudo nmcli connection modify robot-br ipv4.method manual \
  ipv4.addresses 192.168.50.1/24 ipv4.never-default yes bridge.stp no
```

Pi · 적용 & 확인

```
sudo nmcli connection up robot-br
nmcli -g ipv4.method,bridge.stp connection show robot-br
ip -br addr | grep 192.168.50.1
pgrep -a dnsmasq || echo "dnsmasq 없음"
sudo nft list ruleset
```

기대 결과

```
manual
no
br0              DOWN           192.168.50.1/24     # 포트가 없어서 DOWN, 정상
dnsmasq 없음
                                                    # nft 출력 비어 있음 (nm-shared 테이블 없음)
```

통과 조건

192.168.50.1을 가진 인터페이스가 `br0` 하나뿐이고, NM이 띄운 dnsmasq와 `nm-shared-br0` nft 테이블이 없습니다.

되돌리기

새로 만들었다면 `sudo nmcli connection delete robot-br`, 수정했다면 백업의 `robot-br.nmconnection`을 복사한 뒤 `sudo nmcli connection reload`.

## 04DHCP 서버 (dnsmasq)

DHCP만 켜고 DNS는 끕니다(`port=0`). 클라이언트에게 게이트웨이로 Pi(.1)를, DNS로 공용 DNS를 줍니다. `bind-dynamic` 덕분에 부팅 때 br0가 늦게 올라와도 dnsmasq가 실패하지 않습니다.

**인터넷 필요.** 패키지 설치 때만 필요합니다. 폰을 USB로 꽂고 USB 테더링을 켜면 Pi의 기본 프로필로 Pi 자신은 바로 인터넷이 됩니다. 설정 파일을 먼저 쓰고 설치해야 기본 설정으로 잠깐 떴다가 포트 충돌이 나는 일이 없습니다.

Pi · 설정 파일 작성 후 설치

```
sudo mkdir -p /etc/dnsmasq.d
sudo tee /etc/dnsmasq.d/gcs-lan.conf >/dev/null <<'EOF'
# GEN2 ground-station LAN: DHCP only on br0 (Pi is gateway; NAT via USB tether in nftables)
interface=br0
bind-dynamic
port=0
dhcp-authoritative
dhcp-range=192.168.50.100,192.168.50.200,255.255.255.0,12h
dhcp-option=option:router,192.168.50.1
dhcp-option=option:dns-server,1.1.1.1,8.8.8.8
EOF
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq
sudo systemctl enable --now dnsmasq
```

Pi · 확인

```
systemctl is-active dnsmasq
sudo journalctl -u dnsmasq -n 6 --no-pager
sudo ss -lunp | grep ':67 '
```

기대 결과

```
active
dnsmasq[...]: started, version 2.91 DNS disabled
dnsmasq-dhcp[...]: DHCP, IP range 192.168.50.100 -- 192.168.50.200, lease time 12h
dnsmasq-dhcp[...]: DHCP, sockets bound exclusively to interface br0
UNCONN 0 0 0.0.0.0:67 0.0.0.0:* users:(("dnsmasq",pid=...))      # 딱 한 줄
```

통과 조건

67번 포트(DHCP)를 듣는 프로세스가 dnsmasq 하나뿐입니다.

되돌리기

`sudo systemctl disable --now dnsmasq; sudo rm /etc/dnsmasq.d/gcs-lan.conf`

**인터넷 공유를 안 할 팀이라면** 마지막 두 줄을 `dhcp-option=option:router` 한 줄로 바꾸세요. 게이트웨이를 주지 않으므로 노트북의 기본 경로가 Pi로 잡히지 않습니다. 이 경우 Step 08–09는 건너뜁니다.

## 05GEN2-GCS Wi-Fi AP

AP 프로필은 IP 설정 없이 `br0`의 포트로 붙습니다. WPA2 전용(RSN/CCMP)이며 비밀번호를 프로필에 영구 저장해야(`psk-flags 0`) 재부팅 후 자동으로 뜹니다. 저장이 안 되면 로그에 `secrets are required`가 찍히고 AP가 안 뜹니다.

Pi · GEN2-GCS 프로필이 없을 때

```
sudo nmcli connection add type wifi con-name GEN2-GCS ifname wlan0 ssid GEN2-GCS \
  connection.controller br0 connection.port-type bridge connection.autoconnect yes \
  802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 6 \
  wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp
```

Pi · 비밀번호 저장 (화면과 셸 기록에 남지 않음)

```
read -rsp 'GEN2-GCS 비밀번호 (8~63자): ' P; echo
sudo nmcli connection modify GEN2-GCS wifi-sec.psk "$P" wifi-sec.psk-flags 0 \
  wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp; unset P
sudo grep -c '^psk=' /etc/NetworkManager/system-connections/GEN2-GCS.nmconnection   # 1 이어야 함
```

Pi · AP 켜기 & 확인

```
sudo nmcli connection up GEN2-GCS
bridge link
iw dev wlan0 info | grep -E 'ssid|type|channel'
ip -br addr show br0
```

기대 결과

```
3: wlan0: <...> master br0 state forwarding priority 32 cost 100
	ssid GEN2-GCS
	type AP
	channel 6 (2437 MHz), width: 20 MHz
br0              UP             192.168.50.1/24
```

노트북 (GEN2-GCS 접속 후)

```
ipconfig getifaddr en0        # macOS. Linux는 ip -br addr
ping -c 5 192.168.50.1
ssh <pi-user>@192.168.50.1
```

통과 조건

노트북이 192.168.50.100–200 주소를 받고, ping과 SSH가 됩니다. Pi에서 `cat /var/lib/misc/dnsmasq.leases`에 노트북이 보입니다.

되돌리기

`sudo nmcli connection down GEN2-GCS`

**비밀번호는 채팅이나 공유 문서에 붙여넣지 마세요.** 위의 `read -s` 방식으로 Pi 터미널에서 직접 입력합니다. macOS는 이 단계에서 "인터넷 연결 없음"으로 보일 수 있으며 정상입니다(Step 09 이후 해결).

## 06eth0를 브리지에 넣기

EAP225가 연결된 `eth0`를 `br0`의 두 번째 포트로 붙입니다. 같은 eth0에 자동연결이 켜진 다른 프로필이 있으면 부팅 때 서로 다투므로, 기존 것은 자동연결을 끄고 브리지 포트 프로필의 우선순위를 높입니다.

**SSH 경로 확인.** 지금 SSH가 eth0로 들어와 있다면 이 단계에서 끊길 수 있습니다. 로컬 콘솔이나 GEN2-GCS(wlan0) 경로로 접속한 상태에서 진행하세요. wlan0와 eth0를 동시에 내리지 마세요.

Pi · eth0에 걸린 프로필 확인

```
nmcli -f NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show
nmcli -g GENERAL.CONNECTION device show eth0     # 지금 eth0를 잡고 있는 프로필 이름
```

Pi · 브리지 포트 프로필 (없을 때만)

```
sudo nmcli connection add type ethernet con-name robot-eth ifname eth0 \
  connection.controller br0 connection.port-type bridge \
  connection.autoconnect yes connection.autoconnect-priority 10
```

Pi · 3분 자동 롤백 걸고 전환

```
OLD='eap-mgmt'   # 위에서 확인한, 현재 eth0를 잡고 있던 프로필 이름
sudo systemd-run --on-active=180 --unit=eth0-rollback /bin/sh -c \
  "nmcli con mod '$OLD' connection.autoconnect yes; nmcli con up '$OLD'"
sudo nmcli connection modify "$OLD" connection.autoconnect no
sudo nmcli connection modify robot-eth connection.autoconnect-priority 10
sudo nmcli connection up robot-eth
```

Pi · 확인

```
bridge link
ip -4 addr show eth0          # 출력 없어야 함
nmcli device status
```

기대 결과

```
2: eth0: <...> master br0 state forwarding priority 32 cost 100
3: wlan0: <...> master br0 state forwarding priority 32 cost 100
eth0           ethernet  connected   robot-eth
wlan0          wifi      connected   GEN2-GCS
```

통과 조건

두 포트 모두 `forwarding`이고, 노트북에서 192.168.50.1 ping이 계속 됩니다. 확인되면 3분 안에 타이머를 취소합니다: `sudo systemctl stop eth0-rollback.timer`

되돌리기

타이머를 취소하지 않으면 3분 뒤 이전 프로필로 자동 복귀합니다.

**EAP의 주소가 바뀝니다.** EAP225가 DHCP 모드(공장 기본)라면 eth0가 브리지에 붙는 순간 dnsmasq에서 .100–.200 중 하나를 받아 갑니다. 이전 기본 주소 192.168.0.254로는 더 이상 접속되지 않습니다. 다음 단계에서 찾습니다.

## 07EAP225-Outdoor 설정

EAP는 AP 역할만 합니다(DHCP, NAT 없음). 관리 주소를 192.168.50.2로 고정하고, 혹시 고정 설정이 풀려도 같은 주소를 받도록 dnsmasq에 MAC 예약을 겁니다.

Pi · EAP 찾기

```
cat /var/lib/misc/dnsmasq.leases | grep -i eap
```

기대 결과 (예시)

```
1791167945 aa:bb:cc:dd:ee:ff 192.168.50.200 EAP225-Outdoor-AA-BB-CC-DD-EE-FF 01:aa:bb:cc:dd:ee:ff
           └ MAC 주소          └ 지금 주소
```

Pi · 192.168.50.2 예약

```
EAP_MAC='aa:bb:cc:dd:ee:ff'   # 위 leases 출력의 MAC으로 바꾸기
printf '%s\n' '# Reserved: EAP225-Outdoor management' "dhcp-host=$EAP_MAC,192.168.50.2,eap225" \
  | sudo tee -a /etc/dnsmasq.d/gcs-lan.conf
sudo dnsmasq --test -C /dev/null -7 /etc/dnsmasq.d && sudo systemctl restart dnsmasq
```

### EAP 웹 UI

노트북 브라우저에서 `https://<leases에 보인 주소>`로 접속합니다(같은 서브넷이라 바로 됩니다).

| 항목 | 값 |
| --- | --- |
| IP 설정 | Static · `192.168.50.2` · `255.255.255.0` |
| Gateway / DNS | `192.168.50.1` / `8.8.8.8` (Pi는 DNS를 제공하지 않음) |
| SSID | `GEN2-ROBOT`, WPA2-PSK (AES) |
| Client Isolation | OFF |
| Portal | OFF |
| VLAN / Management VLAN | OFF |
| 멀티캐스트 필터 계열 옵션 | 있다면 OFF (ROS 2 디스커버리가 멀티캐스트를 씀) |

**EAP가 192.168.0.254에 남아 있다면** (고정 IP로 설정돼 있던 경우) Pi에 임시 주소를 붙여 접속합니다. 이 주소는 재부팅하면 사라집니다. \
`sudo ip addr add 192.168.0.10/24 dev br0` → 노트북에서 `ssh -L 8443:192.168.0.254:443 <pi-user>@192.168.50.1` → 브라우저 `https://localhost:8443` → 설정 후 `sudo ip addr del 192.168.0.10/24 dev br0`

Pi / 노트북 · 확인

```
ping -c 3 192.168.50.2
```

통과 조건

Pi와 노트북 둘 다에서 192.168.50.2가 응답하고, EAP UI에서 GEN2-ROBOT이 송출 중입니다.

되돌리기

EAP 리셋 버튼으로 공장 초기화하면 DHCP 모드로 돌아가 dnsmasq에서 다시 주소를 받습니다(예약이 있으면 .2).

Part B · 인터넷 공유 (폰 USB 테더링)

## 08USB 테더링 WAN 프로필

라즈베리파이 OS가 만든 `netplan-eth0`는 이름과 달리 `interface-name`이 비어 있어 **모든 유선 장치**에 매칭됩니다. 폰을 잡아 주기는 하지만, 부팅 순서에 따라 eth0를 가로채 DHCP 클라이언트로 만들 수 있습니다. `usb*`/`enx*`에만 붙는 전용 프로필로 바꿉니다.

Pi · 폰 꽂고 USB 테더링 켠 뒤 이름 확인

```
nmcli device status
ip -br link | grep -E '^(usb|enx)'
nmcli -g connection.interface-name connection show netplan-eth0   # 비어 있으면 와일드카드
```

Pi · 전용 프로필 만들고 와일드카드 프로필 끄기

```
sudo nmcli connection add type ethernet con-name wan-tether \
  match.interface-name "usb* enx*" ipv4.method auto ipv4.route-metric 100 ipv6.method auto \
  connection.autoconnect yes connection.autoconnect-priority 5
sudo nmcli connection modify netplan-eth0 connection.autoconnect no    # 삭제하지 않음
sudo nmcli connection up wan-tether ifname usb0                      # 위에서 확인한 이름
```

Pi · 확인

```
nmcli device status | grep -E 'usb|enx'
ip route show default
ping -c 3 8.8.8.8
```

기대 결과

```
usb0           ethernet  connected               wan-tether
default via 192.168.139.55 dev usb0 proto dhcp src 192.168.139.166 metric 100
3 packets transmitted, 3 received, 0% packet loss
```

통과 조건

기본 경로가 테더링 인터페이스 하나뿐이고 `br0`에는 기본 경로가 없습니다. 폰을 뽑았다 다시 꽂으면 `wan-tether`로 자동 연결됩니다.

되돌리기

`sudo nmcli connection modify netplan-eth0 connection.autoconnect yes; sudo nmcli connection delete wan-tether`

## 09NAT & IPv4 포워딩

br0에서 테더링으로 나가는 트래픽만 마스커레이드합니다. 응답 트래픽은 허용하고, 폰 쪽에서 LAN으로 새로 들어오는 연결은 막습니다. 브리지 안의 L2 트래픽(ROS 2 멀티캐스트 포함)은 이 규칙을 거치지 않습니다.

Pi · 포워딩 영구 설정

```
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/90-gcs-forward.conf
sudo sysctl -p /etc/sysctl.d/90-gcs-forward.conf
```

Pi · /etc/nftables.conf 작성 (기존 파일은 Step 01에서 백업됨)

```
sudo tee /etc/nftables.conf >/dev/null <<'EOF'
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
EOF
sudo nft -c -f /etc/nftables.conf && echo SYNTAX_OK
sudo systemctl enable --now nftables
```

Pi · 확인

```
systemctl is-active nftables
sudo nft list tables
sysctl net.ipv4.ip_forward
```

기대 결과

```
active
table inet gcs_filter
table ip gcs_nat
net.ipv4.ip_forward = 1
```

노트북 · Wi-Fi를 껐다 켜서 게이트웨이를 새로 받은 뒤

```
ping -c 5 8.8.8.8
curl -sI https://www.google.com | head -1
```

통과 조건

노트북에서 인터넷이 되고, 폰을 뽑아도 192.168.50.x끼리는 계속 통신됩니다.

되돌리기

`sudo systemctl disable --now nftables; sudo rm /etc/sysctl.d/90-gcs-forward.conf; sudo sysctl -w net.ipv4.ip_forward=0`

Part C · 로봇 & 검증

## 10Jetson Orin Nano 설정

Jetson은 GEN2-ROBOT에 고정 IP로 붙습니다. Wi-Fi 절전을 끄면 RTT가 수십\~수백 ms씩 튀는 현상(절전 모드 특유의 지터)이 사라집니다. Orin Nano의 Wi-Fi 이름은 `wlan0`가 아니라 `wlP1p1s0` 같은 형태일 수 있으니 먼저 확인합니다.

Jetson · 인터페이스 확인

```
nmcli device status | grep wifi
```

Jetson · 프로필 생성 (이미 있으면 add 대신 modify)

```
IF=wlan0    # 위에서 확인한 Wi-Fi 인터페이스 이름
sudo nmcli connection add type wifi con-name GEN2-ROBOT ifname $IF ssid GEN2-ROBOT \
  wifi-sec.key-mgmt wpa-psk \
  ipv4.method manual ipv4.addresses 192.168.50.10/24 ipv4.gateway 192.168.50.1 ipv4.dns 8.8.8.8 \
  ipv6.method disabled 802-11-wireless.powersave 2 connection.autoconnect yes
read -rsp 'GEN2-ROBOT 비밀번호: ' P; echo
sudo nmcli connection modify GEN2-ROBOT wifi-sec.psk "$P" wifi-sec.psk-flags 0; unset P
sudo nmcli connection up GEN2-ROBOT
iw dev $IF get power_save      # Power save: off
```

노트북 · 확인

```
ping -c 5 192.168.50.1
ping -c 5 192.168.50.2
ping -c 5 192.168.50.10
ssh <jetson-user>@192.168.50.10
```

통과 조건

노트북에서 .1, .2, .10 모두 응답하고, 폰 테더링이 꽂혀 있으면 Jetson에서 `ping 8.8.8.8`도 됩니다.

되돌리기

`sudo nmcli connection delete GEN2-ROBOT` (Jetson에서 새로 만든 프로필일 때)

## 11점검 스크립트 설치

읽기 전용 점검 스크립트입니다. 부팅 후, 폰을 꽂고 뺀 뒤, 현장 투입 전에 한 번씩 돌립니다. 종료 코드가 FAIL 개수입니다.

Pi · \~/gcs-netcheck.sh 설치

```
tee ~/gcs-netcheck.sh >/dev/null <<'EOF'
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
EOF
chmod +x ~/gcs-netcheck.sh
~/gcs-netcheck.sh
```

기대 결과 (2026-10-04 실측, Jetson 설정 전)

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

통과 조건

마지막 줄이 `ALL OK`입니다. WARN은 실패가 아니라 아직 안 끝난 항목입니다.

## 12재부팅 & 핫플러그 검증

부팅 순서는 br0 → GEN2-GCS AP → eth0 포트 → dnsmasq → (폰이 있으면) wan-tether DHCP → 기본 경로 → NAT 순으로 자동 복구되어야 합니다.

Pi

```
sudo reboot
# 1분쯤 기다린 뒤 다시 접속
~/gcs-netcheck.sh
```

### 추가 시나리오

- **폰 없이 부팅**: LAN 항목 모두 PASS, 인터넷 항목은 "LAN-only mode" WARN만 나와야 합니다.
- **부팅 후 폰 연결**: USB 테더링을 켜고 10초 뒤 다시 실행하면 `default route via tether`가 PASS여야 합니다.
- **폰 분리**: 노트북 ↔ Jetson ping과 ROS 2 토픽이 끊기지 않아야 합니다.

통과 조건

재부팅 후 손대지 않은 상태에서 `ALL OK`가 나옵니다.

안 될 때

아래 [문제 해결](#trouble) 표에서 해당 증상을 찾고, `sudo journalctl -b -u NetworkManager -u dnsmasq --no-pager | tail -80`을 확인합니다.

## 13ROS 2 멀티캐스트 디스커버리

유니캐스트 피어를 수동으로 지정하지 않고도 토픽이 보여야 합니다. 양쪽 모두 `ROS_LOCALHOST_ONLY`가 꺼져 있어야 합니다.

Jetson

```
export ROS_DOMAIN_ID=20
unset ROS_LOCALHOST_ONLY
ros2 topic pub /network_test std_msgs/msg/String "{data: 'hello'}" -r 2
```

GCS 노트북

```
export ROS_DOMAIN_ID=20
unset ROS_LOCALHOST_ONLY
ros2 topic echo /network_test
```

기대 결과

```
data: hello
---
data: hello
---
```

통과 조건

폰을 뽑은 상태에서도 메시지가 계속 보입니다.

안 될 때

노트북 방화벽(macOS 방화벽, ufw)이 UDP 7400번대를 막는지, EAP의 Client Isolation과 멀티캐스트 필터가 꺼져 있는지 확인합니다.

## 14성능 측정

세 구간을 측정해 기록합니다. Pi에는 iperf3가 기본으로 없으니 폰 테더링이 연결된 상태에서 설치합니다.

설치 (Pi, Jetson 각각)

```
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3
```

지연 · 손실 (보내는 쪽에서)

```
ping -c 200 -i 0.2 192.168.50.1      # 노트북 → Pi
ping -c 200 -i 0.2 192.168.50.10     # Pi → Jetson, 노트북 → Jetson
```

처리량 · 지터 (받는 쪽에서 iperf3 -s, 보내는 쪽에서 아래)

```
iperf3 -s                                   # 받는 쪽
iperf3 -c 192.168.50.10 -t 10              # TCP 업로드
iperf3 -c 192.168.50.10 -t 10 -R           # TCP 다운로드
iperf3 -c 192.168.50.10 -u -b 20M -t 10    # UDP: Jitter, Lost/Total 확인
```

### 기록표

| 구간 | min RTT | avg RTT | max RTT | 손실 | 지터 (UDP) | TCP ↑ / ↓ |
| --- | --- | --- | --- | --- | --- | --- |
| 노트북 ↔ Pi | — | — | — | — | — | — |
| Pi ↔ Jetson | — | — | — | — | — | — |
| 노트북 ↔ Jetson | — | — | — | — | — | — |

참고로 구축 당시 Pi ↔ EAP(유선)는 0.2–0.6 ms였습니다. 무선 클라이언트에서 max RTT가 100 ms를 넘게 튀면 대부분 클라이언트 Wi-Fi 절전 때문입니다.

## 문제 해결

이번 구축 중 실제로 겪은 증상들입니다.

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| GEN2-GCS가 안 뜸. 로그에 `secrets are required` / `no-secrets` | 프로필에 `psk=`가 저장되지 않음 | Step 05의 `read -s` 명령으로 비밀번호와 `psk-flags 0` 저장. `sudo grep -c '^psk=' …GEN2-GCS.nmconnection`이 1인지 확인 |
| `dnsmasq failed to start`, `Address already in use` | NM shared 모드 dnsmasq와 다른 dnsmasq가 같은 포트를 잡음, 또는 shared 프로필 두 개가 192.168.50.1을 가짐 | `robot-br`를 `ipv4.method manual`로. `pgrep -a dnsmasq`가 `/usr/sbin/dnsmasq -x /run/dnsmasq/…` 한 줄이어야 함 |
| eth0를 브리지에 넣자 EAP가 192.168.0.254에서 사라짐 | EAP가 DHCP 모드라 dnsmasq에서 .100–.200 주소를 받아 감 | `cat /var/lib/misc/dnsmasq.leases`에서 찾기. Step 07의 MAC 예약 + 고정 IP |
| 재부팅 후 eth0가 브리지가 아니라 DHCP 클라이언트로 뜸 | interface-name이 빈 `netplan-eth0`가 eth0를 잡음 | Step 08: `netplan-eth0` 자동연결 끄기, `robot-eth` 우선순위 10 확인 |
| Wi-Fi 클라이언트 ping이 50–200 ms로 튐 | 클라이언트(Jetson, 노트북) Wi-Fi 절전 | Jetson: `802-11-wireless.powersave 2`. Linux 노트북도 동일. Pi AP 쪽은 해당 없음 |
| 노트북이 "인터넷 연결 없음" | 폰 테더링이 없거나, 게이트웨이 없이 받은 예전 DHCP 임대 | LAN은 정상. 폰 연결 후 노트북 Wi-Fi를 껐다 켜기 |
| 노트북 인터넷 안 됨 (폰 연결됨) | forward/NAT 미적용 | `sysctl net.ipv4.ip_forward`가 1인지, `sudo nft list tables`에 `gcs_nat`가 있는지, `ip route show default`가 `usb*/enx*`인지 |
| ROS 2 토픽이 안 보임 | 도메인 ID 불일치, `ROS_LOCALHOST_ONLY=1`, 노트북 방화벽, EAP Client Isolation | Step 13의 체크 항목 확인. 둘 다 같은 192.168.50.0/24에 있는지 `ip addr`로 확인 |

## 전체 되돌리기

Step 01 백업으로 원래 상태로 돌립니다. 새로 만든 프로필은 이름으로 지웁니다. 로컬 콘솔에서 실행하세요(Wi-Fi 경로가 끊길 수 있음).

Pi

```
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

## 최종 파일 목록

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