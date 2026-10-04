# 전체 구축 절차

README의 구축 순서(Step 1–9)를 명령어까지 포함해서 풀어 쓴 문서입니다. 각 단계 끝에 **통과 조건 / 기대 출력 / 되돌리기**를 붙여 놨고, 맨 뒤에 선택사항인 인터넷 공유(Step 10–11)와 전체 되돌리기가 있습니다. 명령어는 원본 런북에서 바꾼 것이 없습니다.

명령어 앞에 `Pi:`, `노트북:`, `Jetson:`이 붙어 있으면 그 장비에서 실행하는 겁니다. 안 붙어 있으면 Pi입니다.

> 되돌리기를 하려면 Step 1 백업(`scripts/backup-network.sh`)이 있어야 합니다.

## Step 1. 현재 네트워크 확인 & 백업

바꾸기 전에 먼저 읽습니다. 이 단계에서는 아무것도 바꾸지 않습니다.

Pi:

```bash
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

저는 **어떤 프로필이 `wlan0`와 `eth0`를 잡고 있는지** 먼저 확인했습니다. 특히 `ipv4.method shared`인 프로필, 같은 장치에 자동연결이 켜진 프로필이 여러 개인 경우, `interface-name`이 비어 있는 ethernet 프로필(예: `netplan-eth0`)을 메모해 뒀습니다. 이 프로필들이 나중에 문제를 일으킵니다.

그다음 백업합니다. 같은 내용이 [scripts/backup-network.sh](../scripts/backup-network.sh)에 있습니다.

```bash
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

**기존 프로필은 지우지 않았습니다.** 삭제하지 말고 `connection.autoconnect no`로 끄세요. 되돌릴 때 다시 켜면 됩니다.

#### 통과 조건 · 기대 출력 · 되돌리기

- 통과 조건: 각 인터페이스의 역할(어느 것이 SSH 경로인지, 폰이 `usb0`인지 `enx…`인지)을 파악했고, 백업 폴더 `~/netbackup-YYYYMMDD-pre`가 생겼습니다.
- 메모할 것: `ipv4.method shared`인 프로필, 같은 장치에 자동연결이 켜진 프로필 여러 개, `interface-name`이 빈 ethernet 프로필(예: `netplan-eth0`).

## Step 2. br0 만들기

저는 `br0`를 `192.168.50.1`을 가지는 유일한 인터페이스로 만들었습니다. 수동 IP, 기본 경로 없음, STP 끔(포트가 붙을 때 30초 지연을 없애려고).

Pi — `robot-br` 프로필이 없을 때:

```bash
sudo nmcli connection add type bridge con-name robot-br ifname br0 \
  ipv4.method manual ipv4.addresses 192.168.50.1/24 ipv4.never-default yes \
  ipv6.method disabled bridge.stp no connection.autoconnect yes
```

이미 있을 때 (특히 `ipv4.method`가 `shared`였다면):

```bash
sudo nmcli connection modify robot-br ipv4.method manual \
  ipv4.addresses 192.168.50.1/24 ipv4.never-default yes bridge.stp no
```

적용하고 확인:

```bash
sudo nmcli connection up robot-br
nmcli -g ipv4.method,bridge.stp connection show robot-br    # manual / no
ip -br addr | grep 192.168.50.1
pgrep -a dnsmasq || echo "dnsmasq 없음"
sudo nft list ruleset                                        # 비어 있어야 함
```

`br0`가 `DOWN`으로 보이는 건 아직 포트가 없어서이고 정상입니다.

#### 통과 조건 · 기대 출력 · 되돌리기

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

## Step 3. DHCP 설정 (dnsmasq)

처음에는 NetworkManager의 shared 모드로 구성했는데, dnsmasq와 충돌하면서 `Address already in use`가 발생했습니다. 그래서 최종 구성에서는 `br0`에는 수동 IP만 주고 **DHCP는 dnsmasq 하나만** 사용했습니다. NM의 `ipv4.method shared`는 쓰지 않습니다.

DHCP만 켜고 DNS는 끕니다(`port=0`). `bind-dynamic` 덕분에 부팅 때 `br0`가 늦게 올라와도 dnsmasq가 실패하지 않습니다.

패키지 설치에 인터넷이 필요합니다. 폰을 USB로 꽂고 테더링을 켜면 Pi 자신은 바로 인터넷이 됩니다. 설정 파일을 **먼저 쓰고** 설치해야 기본 설정으로 잠깐 떴다가 포트 충돌이 나는 일이 없습니다.

Pi:

```bash
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

확인:

```bash
systemctl is-active dnsmasq
sudo journalctl -u dnsmasq -n 6 --no-pager
sudo ss -lunp | grep ':67 '     # 딱 한 줄
```

인터넷 공유를 안 쓸 거라면 마지막 두 줄(`router`, `dns-server`)을 `dhcp-option=option:router` 한 줄로 바꾸세요. 게이트웨이를 안 주니까 노트북 기본 경로가 Pi로 잡히지 않습니다.

#### 통과 조건 · 기대 출력 · 되돌리기

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

## Step 4. GEN2-GCS 만들기 (Wi-Fi 국가코드 포함)

Pi `wlan0`를 지상국 AP로 씁니다. AP 프로필에는 IP 설정이 없고 `br0`의 포트로 붙습니다.

먼저 Wi-Fi 국가코드를 한 번 설정합니다. 이게 없으면 Raspberry Pi OS가 Wi-Fi를 rfkill로 막아 둡니다.

```bash
sudo raspi-config nonint do_wifi_country KR
sudo rfkill unblock wlan
iw reg get | head -3     # country KR
rfkill                   # wlan unblocked
```

프로필 생성 (WPA2 전용, RSN/CCMP):

```bash
sudo nmcli connection add type wifi con-name GEN2-GCS ifname wlan0 ssid GEN2-GCS \
  connection.controller br0 connection.port-type bridge connection.autoconnect yes \
  802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 6 \
  wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp
```

비밀번호는 **프로필에 영구 저장**해야(`psk-flags 0`) 재부팅 후 자동으로 AP가 뜹니다. 저장이 안 되면 로그에 `secrets are required`가 찍히고 AP가 안 뜹니다. 아래 방식은 화면과 셸 기록에 비밀번호가 남지 않습니다.

```bash
read -rsp 'GEN2-GCS 비밀번호 (8~63자): ' P; echo
sudo nmcli connection modify GEN2-GCS wifi-sec.psk "$P" wifi-sec.psk-flags 0 \
  wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp; unset P
sudo grep -c '^psk=' /etc/NetworkManager/system-connections/GEN2-GCS.nmconnection   # 1 이어야 함
```

AP 켜기:

```bash
sudo nmcli connection up GEN2-GCS
bridge link                                   # wlan0 ... master br0 state forwarding
iw dev wlan0 info | grep -E 'ssid|type|channel'
ip -br addr show br0
```

노트북에서 `GEN2-GCS`에 접속한 뒤:

```bash
ipconfig getifaddr en0        # macOS. Linux는 ip -br addr
ping -c 5 192.168.50.1
ssh <pi-user>@192.168.50.1
```

비밀번호는 채팅이나 공유 문서에 붙여넣지 마세요. macOS는 이 단계에서 "인터넷 연결 없음"으로 보일 수 있는데 정상입니다.

#### 통과 조건 · 기대 출력 · 되돌리기

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

## Step 5. eth0를 br0에 넣기

`GEN2-GCS`가 정상 동작하는 걸 확인한 다음에 `eth0`를 브리지에 넣었습니다. EAP225가 `eth0`에 물려 있습니다.

> **SSH 경고.** 지금 SSH가 `eth0`로 들어와 있다면 이 단계에서 끊길 수 있습니다. 로컬 콘솔이나 `GEN2-GCS`(wlan0) 경로로 접속한 상태에서 하세요. `wlan0`와 `eth0`를 동시에 내리지 마세요.

같은 `eth0`에 자동연결이 켜진 다른 프로필이 있으면 부팅 때 서로 다투기 때문에, 기존 프로필은 자동연결을 끄고 브리지 포트 프로필의 우선순위를 높입니다.

현재 `eth0`를 잡고 있는 프로필 확인:

```bash
nmcli -f NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show
nmcli -g GENERAL.CONNECTION device show eth0
```

브리지 포트 프로필 (없을 때만):

```bash
sudo nmcli connection add type ethernet con-name robot-eth ifname eth0 \
  connection.controller br0 connection.port-type bridge \
  connection.autoconnect yes connection.autoconnect-priority 10
```

**3분 자동 롤백을 걸고** 전환합니다. 제 경우 `eth0`를 잡고 있던 프로필은 `eap-mgmt`였습니다. 본인 Pi의 이름으로 바꾸세요.

```bash
OLD='eap-mgmt'   # 위에서 확인한 프로필 이름
sudo systemd-run --on-active=180 --unit=eth0-rollback /bin/sh -c \
  "nmcli con mod '$OLD' connection.autoconnect yes; nmcli con up '$OLD'"
sudo nmcli connection modify "$OLD" connection.autoconnect no
sudo nmcli connection modify robot-eth connection.autoconnect-priority 10
sudo nmcli connection up robot-eth
```

확인:

```bash
bridge link                   # eth0, wlan0 둘 다 master br0 state forwarding
ip -4 addr show eth0          # 출력 없어야 함
nmcli device status           # eth0 = robot-eth, wlan0 = GEN2-GCS
```

두 포트 모두 `forwarding`이고 노트북에서 `192.168.50.1` ping이 계속 되면 **3분 안에 타이머를 취소**합니다. 안 하면 3분 뒤 이전 프로필로 돌아갑니다.

```bash
sudo systemctl stop eth0-rollback.timer
```

**EAP225 주소가 바뀝니다.** EAP225가 공장 기본(DHCP) 모드라면 `eth0`가 브리지에 붙는 순간 dnsmasq에서 `.100–.200` 중 하나를 받아 갑니다. 원래 주소 `192.168.0.254`로는 더 이상 안 들어가집니다. 다음 단계에서 찾습니다.

#### 통과 조건 · 기대 출력 · 되돌리기

기대 결과:

```
2: eth0: <...> master br0 state forwarding priority 32 cost 100
3: wlan0: <...> master br0 state forwarding priority 32 cost 100
eth0           ethernet  connected   robot-eth
wlan0          wifi      connected   GEN2-GCS
```

- 통과 조건: 두 포트 모두 `forwarding`이고 노트북에서 192.168.50.1 ping이 계속 됩니다. 확인되면 3분 안에 `sudo systemctl stop eth0-rollback.timer`.
- 되돌리기: 타이머를 취소하지 않으면 3분 뒤 이전 프로필로 자동 복귀합니다.

## Step 6. EAP225 설정

EAP225는 AP 역할만 합니다 (DHCP, NAT 없음).

먼저 Pi에서 EAP가 받아 간 주소를 찾습니다.

```bash
cat /var/lib/misc/dnsmasq.leases | grep -i eap
# 예: 1791167945 aa:bb:cc:dd:ee:ff 192.168.50.200 EAP225-Outdoor-AA-BB-CC-DD-EE-FF 01:aa:bb:cc:dd:ee:ff
```

설정이 풀려도 같은 주소를 받도록 dnsmasq에 MAC 예약을 겁니다. MAC은 위 출력의 값으로 바꾸세요.

```bash
EAP_MAC='aa:bb:cc:dd:ee:ff'
printf '%s\n' '# Reserved: EAP225-Outdoor management' "dhcp-host=$EAP_MAC,192.168.50.2,eap225" \
  | sudo tee -a /etc/dnsmasq.d/gcs-lan.conf
sudo dnsmasq --test -C /dev/null -7 /etc/dnsmasq.d && sudo systemctl restart dnsmasq
```

그다음 노트북 브라우저에서 `https://<leases에 보인 주소>`로 EAP 웹 UI에 들어가서 이렇게 설정했습니다.

| 항목 | 값 |
| --- | --- |
| IP 설정 | Static, `192.168.50.2` / `255.255.255.0` |
| Gateway / DNS | `192.168.50.1` / `8.8.8.8` (Pi는 DNS를 제공하지 않음) |
| SSID | `GEN2-ROBOT`, WPA2-PSK (AES) |
| Client Isolation | **OFF** |
| Portal | **OFF** |
| VLAN / Management VLAN | **OFF** |
| 멀티캐스트 필터 계열 옵션 | 있다면 OFF (ROS 2 디스커버리가 멀티캐스트를 씀) |

EAP가 아직 `192.168.0.254`에 남아 있는 경우(고정 IP였던 경우)는 Pi에 임시 주소를 붙여서 들어갑니다. 재부팅하면 사라지는 주소입니다.

```bash
sudo ip addr add 192.168.0.10/24 dev br0                           # Pi
ssh -L 8443:192.168.0.254:443 <pi-user>@192.168.50.1               # 노트북, 이후 브라우저 https://localhost:8443
sudo ip addr del 192.168.0.10/24 dev br0                           # 설정 끝나고 Pi에서
```

EAP 리셋 버튼으로 공장 초기화하면 DHCP 모드로 돌아가 dnsmasq에서 다시 주소를 받습니다(예약이 있으니 `.2`).

#### 통과 조건 · 기대 출력 · 되돌리기

기대 결과 (leases 예시):

```
1791167945 aa:bb:cc:dd:ee:ff 192.168.50.200 EAP225-Outdoor-AA-BB-CC-DD-EE-FF 01:aa:bb:cc:dd:ee:ff
           └ MAC 주소          └ 지금 주소
```

- 통과 조건: Pi와 노트북 둘 다에서 192.168.50.2가 응답하고, EAP UI에서 `GEN2-ROBOT`이 송출 중입니다.
- 되돌리기: EAP 리셋 버튼으로 공장 초기화.

## Step 7. Jetson 설정

Jetson을 `GEN2-ROBOT`에 연결하고 `192.168.50.10`을 고정으로 줬습니다. Orin Nano의 Wi-Fi 이름은 `wlan0`가 아니라 `wlP1p1s0` 같은 형태일 수 있으니 먼저 확인합니다.

```bash
nmcli device status | grep wifi
```

프로필 생성 (이미 있으면 `add` 대신 `modify`). 여기서 `802-11-wireless.powersave 2`가 Wi-Fi 절전을 끄는 설정입니다. 빼먹으면 ping이 튑니다 (README의 '실제로 겪은 문제' 참고).

```bash
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

#### 통과 조건 · 기대 출력 · 되돌리기

- 통과 조건: 노트북에서 .1, .2, .10 모두 응답하고, `iw dev $IF get power_save`가 `off`입니다. 폰 테더링이 꽂혀 있으면 Jetson에서 `ping 8.8.8.8`도 됩니다.
- 되돌리기: `sudo nmcli connection delete GEN2-ROBOT` (Jetson에서 새로 만든 프로필일 때)

## Step 8. 검증 (ping, ROS 2)

노트북에서:

```bash
ping -c 5 192.168.50.1     # Pi
ping -c 5 192.168.50.2     # EAP225
ping -c 5 192.168.50.10    # Jetson
ssh <jetson-user>@192.168.50.10
```

그다음 ROS 2 확인입니다. 유니캐스트 피어를 수동 지정하지 않아도 토픽이 보여야 합니다. 양쪽 모두 `ROS_LOCALHOST_ONLY`가 꺼져 있어야 합니다.

Jetson:

```bash
export ROS_DOMAIN_ID=20
unset ROS_LOCALHOST_ONLY
ros2 topic pub /network_test std_msgs/msg/String "{data: 'hello'}" -r 2
```

GCS 노트북:

```bash
export ROS_DOMAIN_ID=20
unset ROS_LOCALHOST_ONLY
ros2 topic echo /network_test
```

`data: hello`가 계속 올라오면 됩니다. 폰 테더링을 뽑은 상태에서도 계속 보여야 합니다. 안 보이면 [docs/ros2-test.md](ros2-test.md)를 보세요.

#### 통과 조건 · 기대 출력 · 되돌리기

[ros2-test.md](ros2-test.md) 참고.

## Step 9. 점검 스크립트 & 재부팅 테스트

Pi에 점검 스크립트를 넣고 돌립니다. 읽기 전용이고, 종료 코드가 FAIL 개수입니다. 부팅 후, 폰을 꽂고 뺀 뒤, 현장 투입 전에 한 번씩 돌립니다.

```bash
# 노트북에서 Pi로 복사
scp scripts/gcs-netcheck.sh <pi-user>@192.168.50.1:~/
# Pi에서
~/gcs-netcheck.sh
```

마지막 줄이 `ALL OK`면 통과입니다. `WARN`은 실패가 아니라 아직 안 끝난 항목입니다 (예: Jetson 설정 전).

> 이 스크립트의 nftables 항목은 `sudo -n`을 씁니다. Pi에서 sudo가 비밀번호를 물으면 그 항목이 FAIL로 나옵니다. 인터넷 공유를 안 쓰는 구성이면 그 항목은 무시해도 됩니다.

그다음 **재부팅 테스트**를 합니다. 부팅 순서는 `br0` → `GEN2-GCS` AP → `eth0` 포트 → dnsmasq → (폰이 있으면) `wan-tether` DHCP → 기본 경로 → NAT 순으로 자동 복구되어야 합니다.

```bash
sudo reboot
# 1분쯤 기다린 뒤 다시 접속
~/gcs-netcheck.sh
```

손대지 않은 상태에서 `ALL OK`가 나와야 합니다. 안 되면 아래를 보세요.

```bash
sudo journalctl -b -u NetworkManager -u dnsmasq --no-pager | tail -80
```

추가로 한 시나리오: 폰 없이 부팅 (LAN 항목 전부 PASS, 인터넷 항목은 `LAN-only mode` WARN만), 부팅 후 폰 연결 (10초 뒤 `default route via tether` PASS), 폰 분리 (노트북 ↔ Jetson ping과 ROS 2 토픽이 안 끊겨야 함).

#### 통과 조건 · 기대 출력 · 되돌리기

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

# 선택사항: 인터넷 공유 (USB 테더링)

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
