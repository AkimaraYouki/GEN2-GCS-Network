# Troubleshooting

구축하면서 실제로 겪은 증상들입니다. 안 되면 먼저 이걸 돌려보세요.

```bash
~/gcs-netcheck.sh
sudo journalctl -b -u NetworkManager -u dnsmasq --no-pager | tail -80
```

## 증상 표

| Symptom | What caused it for me | What I did |
| --- | --- | --- |
| `GEN2-GCS`가 안 뜸. 로그에 `secrets are required` / `no-secrets` | 프로필에 `psk=`가 저장되지 않음 | README Step 4의 `read -s` 명령으로 비밀번호와 `psk-flags 0` 저장. `sudo grep -c '^psk=' /etc/NetworkManager/system-connections/GEN2-GCS.nmconnection`이 1인지 확인 |
| `dnsmasq failed to start`, `Address already in use` | NM shared 모드 dnsmasq와 다른 dnsmasq가 같은 포트를 잡음, 또는 shared 프로필 두 개가 192.168.50.1을 가짐 | `robot-br`를 `ipv4.method manual`로. `pgrep -a dnsmasq`가 `/usr/sbin/dnsmasq -x /run/dnsmasq/…` 한 줄이어야 함 |
| `eth0`를 브리지에 넣자 EAP가 192.168.0.254에서 사라짐 | EAP가 DHCP 모드라 dnsmasq에서 .100–.200 주소를 받아 감 | `cat /var/lib/misc/dnsmasq.leases`에서 찾기. README Step 6의 MAC 예약 + 고정 IP |
| 재부팅 후 `eth0`가 브리지가 아니라 DHCP 클라이언트로 뜸 | `interface-name`이 빈 `netplan-eth0`가 `eth0`를 잡음 | `netplan-eth0` 자동연결 끄기, `robot-eth` 우선순위 10 확인 |
| Wi-Fi 클라이언트 ping이 50–200 ms로 튐 | 클라이언트(Jetson, 노트북) Wi-Fi 절전 | Jetson: `802-11-wireless.powersave 2`. Linux 노트북도 동일. Pi AP 쪽은 해당 없음 |
| 노트북이 "인터넷 연결 없음" | 폰 테더링이 없거나, 게이트웨이 없이 받은 예전 DHCP 임대 | LAN은 정상. 폰 연결 후 노트북 Wi-Fi를 껐다 켜기 |
| 노트북 인터넷 안 됨 (폰 연결됨) | forward/NAT 미적용 | `sysctl net.ipv4.ip_forward`가 1인지, `sudo nft list tables`에 `gcs_nat`가 있는지, `ip route show default`가 `usb*/enx*`인지 |
| ROS 2 토픽이 안 보임 | 도메인 ID 불일치, `ROS_LOCALHOST_ONLY=1`, 노트북 방화벽, EAP Client Isolation | [ros2-test.md](ros2-test.md) 체크 항목 확인. 둘 다 같은 192.168.50.0/24에 있는지 `ip addr`로 확인 |

## GEN2-GCS가 안 보일 때 먼저 볼 것

1. `rfkill`에서 wlan이 `unblocked`인지, `iw reg get`이 `country KR`인지
2. `sudo grep -c '^psk=' /etc/NetworkManager/system-connections/GEN2-GCS.nmconnection`이 1인지
3. `nmcli device status`에서 `wlan0`가 `GEN2-GCS`로 connected인지
4. `iw dev wlan0 info`에 `type AP`가 있는지

## 부팅하면 다시 꼬일 때

- `nmcli -f NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show`로 `eth0`에 자동연결이 켜진 프로필이 둘 이상인지 봅니다.
- `bridge link`에서 `eth0`, `wlan0` 둘 다 `master br0 state forwarding`이어야 합니다.
- `sudo ss -lunp | grep ':67 '`가 딱 한 줄이어야 합니다.

## EAP225에 접속이 안 될 때

- 먼저 `cat /var/lib/misc/dnsmasq.leases | grep -i eap`로 지금 주소를 확인합니다.
- 그래도 `192.168.0.254`에 남아 있다면 README Step 6의 임시 주소 + SSH 터널 방법을 씁니다.
- 최후의 수단은 EAP 리셋 버튼입니다. 공장 초기화되면 DHCP 모드로 돌아가고, MAC 예약이 있으면 `.2`를 받습니다.
