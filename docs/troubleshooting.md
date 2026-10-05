# Troubleshooting

안 되면 먼저 Pi에서 이걸 돌려보세요.

```bash
~/gcs-netcheck.sh
sudo journalctl -b -u NetworkManager -u dnsmasq --no-pager | tail -80
```

구성은 EAP225 하나에 노트북과 Jetson이 `GEN2-ROBOT`으로 붙고, Pi는 `eth0`(`192.168.50.1`)로 EAP에 연결된 구조입니다. 증상이 어느 구간인지부터 나누면 편합니다.

```
노트북 ⟷(Wi-Fi)⟷ EAP225 ⟷(Wi-Fi)⟷ Jetson
                   |
                Ethernet
                   |
               Raspberry Pi (.1)
```

## 구축하면서 실제로 겪은 문제

| Symptom | What caused it for me | What I did |
| --- | --- | --- |
| `dnsmasq failed to start`, `Address already in use` | NM shared 모드 dnsmasq와 다른 dnsmasq가 같은 포트를 잡음. 이전 구성에서 shared 프로필 두 개가 192.168.50.1을 같이 가진 경우도 같은 증상 | `eth0` 프로필을 `ipv4.method manual`로. `pgrep -a dnsmasq`가 `/usr/sbin/dnsmasq -x /run/dnsmasq/…` 한 줄이어야 함 |
| EAP가 `192.168.0.254`에서 사라짐 | EAP가 DHCP 모드라 Pi가 `192.168.50.0/24` DHCP를 시작하자 dnsmasq에서 `.100–.200` 주소를 받아 감 | `cat /var/lib/misc/dnsmasq.leases`에서 찾기. [full-setup.md](full-setup.md) Step 4의 MAC 예약 + 고정 IP |
| 재부팅 후 `eth0`가 `192.168.50.1`이 아니라 DHCP 클라이언트로 뜸 | `interface-name`이 빈 `netplan-eth0`가 `eth0`를 잡음 (이전 구성에서 겪음. 같은 원인이 지금 구성에도 적용됨) | `netplan-eth0` 자동연결 끄기, `gcs-lan` 우선순위 10 확인 |
| Wi-Fi 클라이언트 ping이 50–200 ms로 튐 | 클라이언트(Jetson, 노트북) Wi-Fi 절전 | Jetson: `802-11-wireless.powersave 2`. Linux 노트북도 동일 |

## 증상별 확인

### EAP cannot be reached

```bash
ping 192.168.50.2
ip neigh
cat /var/lib/misc/dnsmasq.leases
```

- leases에 EAP가 `192.168.50.2`가 아닌 주소로 있으면 그 주소로 UI에 들어가서 고정 IP를 설정하고, MAC 예약을 겁니다 (Step 4).
- 그래도 `192.168.0.254`에 남아 있다면 Step 4의 임시 주소 + SSH 터널 방법을 씁니다.
- 최후의 수단은 EAP 리셋 버튼입니다. 공장 초기화되면 DHCP 모드로 돌아가고, MAC 예약이 있으면 `.2`를 받습니다.

### Laptop receives no DHCP address

```bash
systemctl status dnsmasq
sudo ss -lunp | grep ':67 '
ip -br addr show eth0
```

- `eth0`가 `192.168.50.1/24`를 가지고 있어야 합니다.
- `:67`을 듣는 프로세스가 dnsmasq 하나여야 합니다.
- 노트북이 `GEN2-ROBOT`에 붙어 있는지 확인합니다.

### Pi의 DHCP가 죽었을 때

Jetson과 EAP225는 고정 IP라서 Pi의 DHCP가 죽어도 그 주소 자체는 유지됩니다. 반대로 DHCP로 주소를 받는 노트북 같은 새 클라이언트는 주소를 받지 못합니다.

현장에서 바로 복구할 수 있게 노트북에 static fallback 설정을 미리 만들어 둡니다. DHCP 대역(`.100`–`.200`) 밖의 주소를 씁니다.

```
IP:      192.168.50.20
Netmask: 255.255.255.0
```

이 주소로 `GEN2-ROBOT`에 붙으면 Jetson(`.10`), EAP(`.2`), Pi(`.1`)와 통신할 수 있습니다. 평소에는 DHCP로 두고, DHCP가 안 될 때만 이 설정으로 바꿉니다. (`.20`은 예시이고, 본인 대역에서 고정 장비와 겹치지 않는 주소를 쓰세요.)

### Laptop and Jetson cannot communicate

- 둘 다 `GEN2-ROBOT`에 붙어 있는지
- 같은 `192.168.50.0/24`인지 (`ip addr` / `ipconfig getifaddr en0`)
- EAP **Client Isolation OFF**
- **VLAN OFF**
- 노트북/Jetson 로컬 방화벽
- EAP 멀티캐스트 필터

### ROS 2 nodes/topics cannot be discovered

- `ROS_DOMAIN_ID`가 양쪽 같은지
- `ROS_LOCALHOST_ONLY`가 unset인지
- Client Isolation
- 방화벽 (macOS 방화벽, ufw — UDP 7400번대)
- EAP 멀티캐스트 설정
- 같은 서브넷인지

### High latency / ping spikes

- Jetson Wi-Fi 절전 (`iw dev <if> get power_save`가 `off`인지)
- 노트북 Wi-Fi 절전
- RSSI (EAP와 거리)
- 채널 혼잡

### 노트북이 "인터넷 연결 없음"

폰 테더링이 없거나, 게이트웨이 없이 받은 예전 DHCP 임대일 수 있습니다. LAN은 정상입니다. 폰 연결 후 노트북 Wi-Fi를 껐다 켭니다. (인터넷은 선택사항입니다.)

### 노트북 인터넷 안 됨 (폰 연결됨)

- `sysctl net.ipv4.ip_forward`가 1인지
- `sudo nft list tables`에 `gcs_nat`가 있는지
- `ip route show default`가 `usb*/enx*`인지

## 이전 구성에서만 있던 문제 (Deprecated)

Pi가 `GEN2-GCS` Wi-Fi AP를 만들고 `wlan0`와 `eth0`를 `br0`로 브리지하던 **이전 구성**에서 겪은 문제입니다. 최종 구성에서는 해당 없습니다. 기록용으로만 남깁니다.

| Symptom | Cause | Fix |
| --- | --- | --- |
| `GEN2-GCS`가 안 뜸. 로그에 `secrets are required` / `no-secrets` | 프로필에 `psk=`가 저장되지 않음 | `read -s`로 비밀번호와 `psk-flags 0` 저장 |
| `br0`가 `DOWN` | 포트가 없을 때는 정상 | 브리지 포트가 붙으면 UP |

이전 구성의 런북은 git 히스토리에만 남아 있습니다. 확인 방법은 [archive/runbook.md](archive/runbook.md) 맨 아래에 있습니다.
