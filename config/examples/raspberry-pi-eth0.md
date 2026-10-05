# Raspberry Pi eth0 프로필 예시

브리지 없이 `eth0`가 LAN 주소 `192.168.50.1/24`를 직접 가집니다. 프로필 이름은 Pi마다 다를 수 있어서, 이 저장소에서는 새로 만드는 프로필에 `gcs-lan`이라는 이름을 씁니다.

> **`192.168.50.1/24`는 예시 값임.** 각자 다른 주소/대역을 정해서 쓰고, EAP·dnsmasq·nftables·Jetson 설정도 같은 대역으로 맞출 것.

```bash
sudo nmcli connection add type ethernet con-name gcs-lan ifname eth0 \
  ipv4.method manual ipv4.addresses 192.168.50.1/24 ipv4.never-default yes \
  ipv6.method disabled connection.autoconnect yes connection.autoconnect-priority 10
```

| 설정 | 값 | 이유 |
| --- | --- | --- |
| `ifname` | `eth0` | `interface-name`이 빈 와일드카드 프로필과 구분 |
| `ipv4.method` | `manual` | `shared`는 쓰지 않음 (dnsmasq와 충돌) |
| `ipv4.addresses` | `192.168.50.1/24` | Pi = `.1` |
| `ipv4.never-default` | `yes` | 기본 경로는 USB 테더링(`wan-tether`)이 가짐 |
| `autoconnect-priority` | `10` | 같은 `eth0`를 노리는 다른 프로필보다 우선 |

기대 상태:

```
eth0    192.168.50.1/24
```

`br0`, `wlan0` AP, 브리지 포트는 만들지 않습니다.
