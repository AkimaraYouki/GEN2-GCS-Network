# GEN2 GCS Network

GEN2 로봇의 지상국 노트북과 Jetson을 안정적으로 연결하기 위해 구축한 네트워크 구성입니다.

처음에는 단순히 노트북과 로봇 사이의 Wi-Fi 연결을 개선하려고 시작했고, 최종적으로는 Raspberry Pi 4를 지상국 측 AP로, EAP225-Outdoor를 로봇 측 AP로 사용했습니다.

Raspberry Pi의 `wlan0`와 `eth0`를 `br0`로 묶어서 노트북, Pi, EAP225, Jetson이 모두 `192.168.50.0/24` 하나의 LAN에 있도록 구성했습니다.

이 문서는 제가 실제로 구축하면서 사용한 설정과, 중간에 발생했던 문제 및 해결 방법을 정리한 것입니다. 동일하게 구축하려면 아래 순서대로 진행하면 됩니다.

> 검증 환경: Raspberry Pi OS Lite (Debian 13), kernel 6.18, NetworkManager 1.52.1, dnsmasq 2.91, nftables 1.1.3 / 2026-10-04
>
> 기술적인 원본은 [docs/original-runbook.md](docs/original-runbook.md)입니다. README는 그걸 인수인계용으로 다시 정리한 것이고, 명령어는 바꾸지 않았습니다.

---

## 1. What I built

지상국 노트북과 로봇 사이의 Wi-Fi를 좀 더 안정적으로 만들 필요가 있었습니다. 최종 구조는 이렇습니다.

```
Laptop
 -> Raspberry Pi 4
 -> EAP225-Outdoor
 -> Jetson Orin Nano
```

Pi가 지상국 쪽 Wi-Fi(`GEN2-GCS`)를 만들고, EAP225가 로봇 쪽 Wi-Fi(`GEN2-ROBOT`)를 만듭니다. 두 Wi-Fi는 Pi 안의 브리지로 이어져서 전체가 `192.168.50.0/24` LAN 하나입니다.

```
  Android phone (LTE/5G)                    <- 선택사항. 없어도 로봇 망은 동작
        |  USB tethering
        v
  +--------------------------------------------------------------+
  |  Raspberry Pi 4                                              |
  |    br0 = 192.168.50.1/24      dnsmasq = 유일한 DHCP 서버     |
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

## 2. Why I built it this way

- Pi가 `GEN2-GCS`를 만들고, EAP225가 `GEN2-ROBOT`을 만듭니다.
- Pi의 `wlan0`와 `eth0`를 `br0`로 브리지했습니다. 라우팅하지 않고 L2로 이었습니다.
- 그래서 노트북과 Jetson이 같은 서브넷에 있습니다.
- ROS 2 DDS 멀티캐스트가 그냥 통과합니다. 피어 주소를 수동으로 넣을 필요가 없습니다.
- 로봇 밸런스 제어 루프는 이 Wi-Fi를 쓰지 않습니다. Jetson 로컬 IMU + CAN으로 돕니다.
- 이 망은 ROS 2 토픽, SSH, 텔레옵, SLAM 시각화, 진단, 카메라 미리보기용입니다.

## 3. Final network configuration

| Device | Address | Role |
| --- | --- | --- |
| Raspberry Pi `br0` | `192.168.50.1` | GCS AP / bridge / DHCP |
| EAP225-Outdoor | `192.168.50.2` | Robot-side AP |
| Jetson Orin Nano | `192.168.50.10` | Robot computer |
| Laptop | DHCP (`.100` – `.200`) | Ground station |

```
GEN2-GCS     Pi wlan0, 2.4 GHz ch 6, WPA2     <- 노트북이 붙음
GEN2-ROBOT   EAP225, WPA2-PSK (AES)           <- Jetson이 붙음
```

주소는 `br0`만 가집니다. `wlan0`와 `eth0`는 주소 없는 브리지 포트입니다. **같은 IP를 `wlan0`나 `eth0`에 주지 마세요.**

## 4. Hardware used

- Raspberry Pi 4
- **TP-Link EAP225-Outdoor** (Omada)
- Jetson Orin Nano
- 지상국 노트북
- Ethernet 케이블 (Pi `eth0` ↔ EAP225)
- 각 장비 전원
- 2020 알루미늄 프로파일 (지지대) + 브라켓

선택:

- Android 폰 (USB 테더링용, [아래](#optional-internet-through-android-usb-tethering) 참고)

### 지지대 & 브라켓

![Pi와 EAP225를 2020 프로파일에 고정한 모습](docs/images/ap-mount-collage.jpg)

Pi 4와 TP-Link EAP225-Outdoor를 2020 프로파일 하나에 같이 세워서 쓴다. 안테나가 위로 올라오게 세우고, Pi는 AP 바로 옆 프로파일에 붙인다.

- 2020 프로파일 지지대와 브라켓 모델은 [Onshape 문서](https://cad.onshape.com/documents/eb8f1ae66d872a8dc34ad04b/w/f149fbaa85f6e4b3bb27186b/e/26e3c731a53e620f67562c44?renderMode=0&uiState=6ac2860149432b68a5bfc669)에서 받아서 쓰면 된다.
- 왼쪽 사진은 전체 모습이다. 프로파일을 세우고 위쪽에 EAP225, 그 옆에 Pi 4를 붙여준다.
- 오른쪽 사진은 옆에서 본 모습이다. EAP225는 브라켓에 끼워서 프로파일에 고정해준다.
- Pi와 EAP225를 잇는 Ethernet 케이블은 남는 길이를 둥글게 말아서 케이블타이로 프로파일에 묶어준다.
- 케이블이 늘어지면 커넥터에 힘이 걸리니까, 묶을 때는 `eth0` 쪽 커넥터에 장력이 안 걸리게 해준다.
- 다 고정했으면 Pi와 EAP225 전원을 넣고, 아래 Step 1부터 입력하자.

## 5. How I built it

순서대로 하면 됩니다. 각 단계마다 통과 조건이 있으니 확인하고 다음으로 넘어가세요. 각 단계의 되돌리기, 기대 출력, 인터넷 공유(Step 10–11)는 [docs/full-setup.md](docs/full-setup.md)에 있습니다.

명령어 앞에 `Pi:`, `노트북:`, `Jetson:`이 붙어 있으면 그 장비에서 실행하는 겁니다. 안 붙어 있으면 Pi입니다.

### Step 1. Check the current network

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

그다음 백업합니다. 같은 내용이 [scripts/backup-network.sh](scripts/backup-network.sh)에 있습니다.

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

### Step 2. Create br0

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

통과 조건: 192.168.50.1을 가진 인터페이스가 `br0` 하나뿐이고, NM이 띄운 dnsmasq나 `nm-shared-br0` nft 테이블이 없습니다.

### Step 3. Configure DHCP

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

통과 조건: 67번 포트를 듣는 프로세스가 dnsmasq 하나뿐입니다.

인터넷 공유를 안 쓸 거라면 마지막 두 줄(`router`, `dns-server`)을 `dhcp-option=option:router` 한 줄로 바꾸세요. 게이트웨이를 안 주니까 노트북 기본 경로가 Pi로 잡히지 않습니다.

### Step 4. Create GEN2-GCS

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

통과 조건: 노트북이 `192.168.50.100–200` 주소를 받고 ping과 SSH가 됩니다. Pi에서 `cat /var/lib/misc/dnsmasq.leases`에 노트북이 보입니다.

비밀번호는 채팅이나 공유 문서에 붙여넣지 마세요. macOS는 이 단계에서 "인터넷 연결 없음"으로 보일 수 있는데 정상입니다.

### Step 5. Put eth0 into br0

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

### Step 6. Configure EAP225

EAP225는 AP 역할만 합니다 (DHCP, NAT 없음).

먼저 Pi에서 EAP가 받아 간 주소를 찾습니다.

```bash
cat /var/lib/misc/dnsmasq.leases | grep -i eap
# 예: 1791167945 ec:b9:31:5f:3b:d6 192.168.50.200 EAP225-Outdoor-EC-B9-31-5F-3B-D6 01:ec:b9:31:5f:3b:d6
```

설정이 풀려도 같은 주소를 받도록 dnsmasq에 MAC 예약을 겁니다. MAC은 위 출력의 값으로 바꾸세요.

```bash
EAP_MAC='ec:b9:31:5f:3b:d6'
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

통과 조건: Pi와 노트북 둘 다에서 `ping -c 3 192.168.50.2`가 되고, EAP UI에서 `GEN2-ROBOT`이 송출 중입니다.

EAP 리셋 버튼으로 공장 초기화하면 DHCP 모드로 돌아가 dnsmasq에서 다시 주소를 받습니다(예약이 있으니 `.2`).

### Step 7. Configure Jetson

Jetson을 `GEN2-ROBOT`에 연결하고 `192.168.50.10`을 고정으로 줬습니다. Orin Nano의 Wi-Fi 이름은 `wlan0`가 아니라 `wlP1p1s0` 같은 형태일 수 있으니 먼저 확인합니다.

```bash
nmcli device status | grep wifi
```

프로필 생성 (이미 있으면 `add` 대신 `modify`). 여기서 `802-11-wireless.powersave 2`가 Wi-Fi 절전을 끄는 설정입니다. 빼먹으면 ping이 튑니다 (아래 문제 목록 참고).

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

### Step 8. Verify

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

`data: hello`가 계속 올라오면 됩니다. 폰 테더링을 뽑은 상태에서도 계속 보여야 합니다. 안 보이면 [docs/ros2-test.md](docs/ros2-test.md)를 보세요.

### Step 9. Self-check script and reboot test

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

---

## Problems I actually ran into

구축하면서 실제로 겪은 것들입니다.

### GEN2-GCS did not come back after restart

- **원인**: Wi-Fi PSK가 프로필에 저장되지 않았습니다.
- **로그**: `secrets are required` / `no-secrets`
- **해결**: Step 4의 `read -s` 명령으로 비밀번호와 `psk-flags 0`을 저장했습니다. `sudo grep -c '^psk=' /etc/NetworkManager/system-connections/GEN2-GCS.nmconnection`이 `1`인지 확인합니다.

### dnsmasq failed with Address already in use

- **원인**: NetworkManager shared 모드의 dnsmasq와 별도의 dnsmasq가 DHCP를 같이 잡으려고 했습니다. shared 프로필 두 개가 `192.168.50.1`을 같이 가진 경우도 같은 증상입니다.
- **해결**: DHCP 서버를 하나만 씁니다. `robot-br`를 `ipv4.method manual`로 바꾸고, `pgrep -a dnsmasq`가 `/usr/sbin/dnsmasq -x /run/dnsmasq/…` 한 줄만 나오는지 확인합니다.

### EAP225 disappeared from 192.168.0.254

- **원인**: `eth0`가 `br0`에 들어가자 EAP가 새 DHCP 네트워크에서 주소를 받아 갔습니다.
- **해결**: Pi에서 `cat /var/lib/misc/dnsmasq.leases`로 찾고, Step 6대로 MAC 예약 + `192.168.50.2` 고정을 합니다.

### eth0 came back as a DHCP client after reboot

- **원인**: `interface-name`이 비어 있는 다른 프로필(`netplan-eth0`)이 모든 유선 장치에 매칭되면서 `eth0`를 가로챘습니다.
- **해결**: 그 프로필의 `autoconnect`를 끄고(삭제 안 함), `robot-eth`를 브리지 포트로 두고 우선순위 10을 확인했습니다.

  ```bash
  sudo nmcli connection modify netplan-eth0 connection.autoconnect no
  ```

### Ping suddenly became 50-200 ms

- **원인**: Wi-Fi 절전(power saving).
- **해결**: Jetson/클라이언트 쪽에서 절전을 끕니다. Jetson은 `802-11-wireless.powersave 2`(Step 7), Linux 노트북도 동일합니다. Pi AP 쪽은 해당 없습니다.

더 있는 증상(노트북 "인터넷 연결 없음", ROS 2 토픽 안 보임 등)은 [docs/troubleshooting.md](docs/troubleshooting.md)에 표로 정리했습니다.

---

## Optional: Internet through Android USB tethering

**이건 선택사항입니다. 로봇 네트워크 자체는 인터넷 없이 동작합니다.** 폰이 없으면 인터넷만 안 되고, 노트북 ↔ Pi ↔ EAP ↔ Jetson 통신과 ROS 2는 그대로입니다. 이 시스템의 목적은 인터넷 공유가 아닙니다.

제가 구성하고 확인한 방식만 적습니다.

- 안드로이드 폰을 Pi에 USB로 꽂고 USB 테더링을 켭니다. Pi에서는 `usb0` 또는 `enx...`로 보입니다.
- `wan-tether` 프로필이 `usb* enx*`에만 붙어서 폰에게서 DHCP로 주소를 받습니다 (`route-metric 100`).
- `br0`에서 테더링으로 나가는 트래픽만 NAT(masquerade) 합니다. 폰 쪽에서 LAN으로 새로 들어오는 연결은 막습니다.
- 브리지 안의 L2 트래픽(ROS 2 멀티캐스트 포함)은 이 규칙을 거치지 않습니다.
- dnsmasq가 게이트웨이로 Pi(`.1`)를 줘서 노트북과 Jetson이 Pi를 통해 인터넷에 나갑니다.

`wan-tether` 프로필, NAT/포워딩 설정, 되돌리기 명령은 [docs/full-setup.md](docs/full-setup.md)의 Step 10–11에 있습니다. 설정 파일 예시는 [config/examples/](config/examples/)에 있습니다.

---

## 처음부터 전부 되돌리기

Step 1 백업으로 돌립니다. 새로 만든 프로필은 이름으로 지웁니다. **로컬 콘솔에서 실행하세요** (Wi-Fi 경로가 끊길 수 있습니다). 명령어는 [docs/full-setup.md](docs/full-setup.md) 맨 아래 "전체 되돌리기"에 있습니다.

## 지금까지 확인한 것과 비어 있는 것

솔직하게 적어 둡니다.

- 확인함: 2026-10-04 `gcs-netcheck.sh` 실측에서 LAN 항목 전부 PASS, 폰 테더링 인터넷 PASS, 노트북 2대가 `GEN2-GCS`에 접속. 이때는 **Jetson 설정 전**이라 EAP225는 `.200`에 있었고(WARN), Jetson `.10`은 응답 없음(WARN)이었습니다. Pi ↔ EAP(유선) ping은 0.2–0.6 ms였습니다.
- 런북에 결과가 기록돼 있지 않음: Jetson 연결 이후의 ROS 2 멀티캐스트 테스트 결과, [성능 측정표](docs/ros2-test.md#성능-측정)의 값. 절차만 있고 숫자는 비어 있습니다. 다시 구축하면 직접 채워 주세요.

## Repository layout

```
GEN2-GCS-Network/
├── README.md
├── docs/
│   ├── images/                 # 장비 설치 사진
│   ├── full-setup.md           # 전체 절차 (통과 조건, 되돌리기, 인터넷 공유 포함)
│   ├── troubleshooting.md      # 증상 표 + 로그 확인 명령
│   ├── ros2-test.md            # ROS 2 확인 + 성능 측정
│   └── original-runbook.md     # 원본 런북 (기술적 기준)
├── scripts/
│   ├── gcs-netcheck.sh         # Pi에서 돌리는 상태 점검
│   └── backup-network.sh       # 바꾸기 전에 Pi 설정 백업
└── config/
    └── examples/               # dnsmasq / nftables / sysctl 예시
```
