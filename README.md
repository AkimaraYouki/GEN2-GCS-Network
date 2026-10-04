# GEN2 GCS Network

GEN2 로봇의 지상국 노트북과 Jetson을 보다 안정적인 Wi-Fi로 연결하기 위해 구축한 네트워크입니다.

처음 목적은 단순했습니다. 기존 무선 연결 대신 EAP225-Outdoor를 메인 AP로 사용해서 지상국 노트북과 로봇을 하나의 안정적인 무선 LAN에 연결하고자 했습니다.

최종 구성에서는 지상국 노트북과 Jetson이 모두 `GEN2-ROBOT` SSID에 직접 접속합니다.

Raspberry Pi 4는 EAP225에 Ethernet으로 연결되어 `192.168.50.1`을 사용하며, DHCP와 네트워크 관리, 필요할 경우 Android USB 테더링을 통한 인터넷 공유 역할만 담당합니다.

이 문서는 제가 실제로 구축한 구성과 설정 순서, 그리고 구축 과정에서 확인한 문제와 해결 방법을 정리한 것입니다.

> 패키지 버전은 이전 구성에서 검증한 기준입니다: Raspberry Pi OS Lite (Debian 13), kernel 6.18, NetworkManager 1.52.1, dnsmasq 2.91, nftables 1.1.3 (2026-10-04). 현재 구성(EAP 단일 AP)의 실측 결과는 아직 기록하지 않았습니다. [8번](#8-성능-측정) 참고.
>
> 명령어 전체와 단계별 되돌리기는 [docs/full-setup.md](docs/full-setup.md)에 있습니다.

---

## 1. 구축한 구조

EAP225 하나에 노트북과 Jetson을 둘 다 연결했습니다. Pi는 Wi-Fi AP로 쓰지 않고 Ethernet으로 EAP에 연결했습니다.

```mermaid
flowchart TD
    EAP["TP-Link EAP225-Outdoor<br/>192.168.50.2<br/>SSID: GEN2-ROBOT"]

    GCS["Ground Station Laptop<br/>DHCP"]
    JETSON["Jetson Orin Nano<br/>192.168.50.10"]
    PI["Raspberry Pi 4<br/>eth0: 192.168.50.1<br/>DHCP / Management"]

    GCS <-->|Wi-Fi| EAP
    JETSON <-->|Wi-Fi| EAP
    PI <-->|Ethernet| EAP
```

한 줄로 말하면: **EAP225가 메인 AP이고, 노트북과 로봇이 둘 다 `GEN2-ROBOT`에 붙습니다. Pi는 유선으로 연결해서 DHCP와 관리 역할을 합니다.**

## 2. 이렇게 구성한 이유

- 노트북과 Jetson이 같은 EAP에 붙으니 같은 `192.168.50.0/24`에 있습니다.
- ROS 2 트래픽이 Pi의 Wi-Fi–Ethernet 브리지를 거치지 않습니다. `노트북 → EAP → Jetson`으로 바로 갑니다.
- Pi는 Wi-Fi를 제공하지 않습니다. DHCP, 네트워크 관리, 진단, (선택) 인터넷 게이트웨이만 맡습니다.
- **로봇 밸런스 제어 루프는 이 Wi-Fi를 쓰지 않습니다. 그래서 일시적인 Wi-Fi 패킷 손실이 로봇을 직접 불안정하게 만들지는 않습니다.

## 3. 최종 네트워크 설정

| 장비 | 주소 | 역할 |
| --- | --- | --- |
| Raspberry Pi 4 (`eth0`) | `192.168.50.1` | DHCP / 게이트웨이 / 관리 |
| EAP225-Outdoor | `192.168.50.2` | 메인 AP (노트북 + Jetson) |
| Jetson Orin Nano | `192.168.50.10` | 로봇 컴퓨터 |
| 노트북 | DHCP (`.100` – `.200`) | 지상국 |

SSID는 **`GEN2-ROBOT` 하나**입니다. 노트북과 Jetson이 둘 다 여기에 붙습니다.

`.1`, `.2`, `.10`은 DHCP 대역(`.100`–`.200`) 밖에 있습니다. Pi는 `eth0`가 `192.168.50.1/24`를 직접 가집니다. 브리지는 없습니다.

## 4. 사용한 하드웨어

- Raspberry Pi 4
- **TP-Link EAP225-Outdoor** (Omada)
- Jetson Orin Nano
- 지상국 노트북
- Ethernet 케이블 (Pi `eth0` ↔ EAP225)
- 각 장비 전원
- 2020 알루미늄 프로파일 (지지대) + 브라켓

선택:

- Android 폰 (USB 테더링용, [9번](#9-선택사항-usb-테더링) 참고)

### 지지대 & 브라켓

![Pi와 EAP225를 2020 프로파일에 고정한 모습](images/ap-mount-collage.jpg)

Pi 4와 TP-Link EAP225-Outdoor를 2020 프로파일 하나에 같이 세워서 쓴다. 안테나가 위로 올라오게 세우고, Pi는 AP 바로 옆 프로파일에 붙인다.

- 2020 프로파일 지지대와 브라켓 모델은 [Onshape 문서](https://cad.onshape.com/documents/eb8f1ae66d872a8dc34ad04b/w/f149fbaa85f6e4b3bb27186b/e/26e3c731a53e620f67562c44?renderMode=0&uiState=6ac2860149432b68a5bfc669)에서 받아서 쓰면 된다.
- 왼쪽 사진은 전체 모습이다. 프로파일을 세우고 위쪽에 EAP225, 그 옆에 Pi 4를 붙여준다.
- 오른쪽 사진은 옆에서 본 모습이다. EAP225는 브라켓에 끼워서 프로파일에 고정해준다.
- Pi와 EAP225를 잇는 Ethernet 케이블은 남는 길이를 둥글게 말아서 케이블타이로 프로파일에 묶어준다.
- 케이블이 늘어지면 커넥터에 힘이 걸리니까, 묶을 때는 `eth0` 쪽 커넥터에 장력이 안 걸리게 해준다.
- 다 고정했으면 Pi와 EAP225 전원을 넣고, 아래 구축 순서 Step 1부터 입력하자.

## 5. 구축 순서

순서대로 하면 됩니다. 각 단계의 **명령어, 통과 조건, 되돌리기**는 [docs/full-setup.md](docs/full-setup.md)에 있습니다. 여기서는 각 단계에서 뭘 했고 뭘 조심해야 하는지만 적었습니다.

| Step | 한 일 | 핵심 |
| --- | --- | --- |
| 1 | 현재 네트워크 확인 + 백업 | 바꾸기 전에 읽기만 합니다. `scripts/backup-network.sh`로 백업합니다. |
| 2 | Pi `eth0`에 `192.168.50.1/24` 주기 | 수동 IP, 기본 경로 없음. SSH 경고, 3분 자동 롤백. |
| 3 | DHCP 설정 (dnsmasq) | DHCP는 dnsmasq 하나만, `interface=eth0`. NM `shared` 모드는 쓰지 않습니다. |
| 4 | EAP225 설정 | `192.168.50.2` 고정, SSID `GEN2-ROBOT`, Client Isolation / Portal / VLAN 모두 OFF. |
| 5 | Jetson 설정 | `GEN2-ROBOT`에 `192.168.50.10` 고정, Wi-Fi 절전 끔. |
| 6 | 노트북 접속 + 검증 | 노트북도 `GEN2-ROBOT`. `.1`, `.2`, `.10` ping, Jetson SSH, ROS 2. |
| 7 | 점검 스크립트 + 재부팅 테스트 | `gcs-netcheck.sh`가 `ALL OK`. |

### 꼭 기억할 것

1. **백업 먼저.** 기존 프로필은 지우지 말고 `connection.autoconnect no`로 끄세요. 되돌릴 때 다시 켜면 됩니다.
2. **SSH 경고.** 지금 SSH가 `eth0`로 들어와 있다면 Step 2에서 끊깁니다. 로컬 콘솔이나 다른 경로로 접속한 상태에서 하세요.
3. **자동 롤백.** Step 2는 3분 뒤 이전 프로필로 돌아가는 타이머를 걸고 시작합니다. 문제없으면 3분 안에 `sudo systemctl stop eth0-rollback.timer`로 취소합니다.
4. **EAP225 주소가 바뀝니다.** EAP가 공장 기본(DHCP)이면 Pi가 DHCP를 시작하는 순간 `.100–.200` 중 하나를 받아 가서 `192.168.0.254`로는 안 들어가질 수 있습니다. Pi에서 `cat /var/lib/misc/dnsmasq.leases`로 찾으면 됩니다.
5. **비밀번호는 `read -s`로 입력.** 채팅이나 공유 문서에 붙여넣지 마세요.
6. **Pi는 Wi-Fi AP가 아닙니다.** `br0`, `GEN2-GCS`, `wlan0` AP는 만들지 않습니다. (이전 구성이라 [10번](#10-이전-구성-사용하지-않음)에 따로 적었습니다.)

### 점검 스크립트와 재부팅 테스트

Pi에 [scripts/gcs-netcheck.sh](scripts/gcs-netcheck.sh)를 복사해서 돌립니다. 읽기 전용이고 종료 코드가 FAIL 개수입니다. 부팅 후, 폰을 꽂고 뺀 뒤, 현장 투입 전에 한 번씩 돌립니다.

```bash
~/gcs-netcheck.sh
```

마지막 줄이 `ALL OK`면 통과입니다. `WARN`은 실패가 아니라 아직 안 끝난 항목입니다 (예: Jetson 설정 전, 폰 없음).

그다음 `sudo reboot` 하고 1분쯤 뒤에 다시 돌립니다. 손대지 않은 상태에서 `ALL OK`가 나와야 합니다. 안 되면 아래를 확인합니다.

```bash
sudo journalctl -b -u NetworkManager -u dnsmasq --no-pager | tail -80
```

## 6. 실제로 겪은 문제

구축하면서 실제로 겪은 것들입니다. 증상별 확인 방법은 [docs/troubleshooting.md](docs/troubleshooting.md)에 있습니다. 아래 중 처음 세 개는 이전 구성에서 겪었지만 원인이 지금 구성에도 그대로 적용됩니다.

### dnsmasq가 Address already in use로 죽음

- **원인**: NetworkManager shared 모드의 dnsmasq와 별도의 dnsmasq가 DHCP를 같이 잡으려고 했습니다.
- **해결**: DHCP 서버를 하나만 씁니다. `eth0` 프로필을 `ipv4.method manual`로 두고, `pgrep -a dnsmasq`가 `/usr/sbin/dnsmasq -x /run/dnsmasq/…` 한 줄만 나오는지 확인합니다.

### EAP225가 192.168.0.254에서 사라짐

- **원인**: Pi가 `192.168.50.0/24` DHCP를 시작하자 EAP가 새 DHCP 네트워크에서 주소를 받아 갔습니다.
- **해결**: `cat /var/lib/misc/dnsmasq.leases`로 찾고, MAC 예약 + `192.168.50.2` 고정을 합니다. ([full-setup.md](docs/full-setup.md) Step 4)

### 재부팅 후 eth0가 DHCP 클라이언트로 돌아옴

- **원인**: `interface-name`이 비어 있는 다른 프로필(`netplan-eth0`)이 모든 유선 장치에 매칭되면서 `eth0`를 가로챘습니다.
- **해결**: 그 프로필의 `autoconnect`를 끄고(삭제 안 함), `eth0` 프로필의 우선순위를 10으로 둡니다.

  ```bash
  sudo nmcli connection modify netplan-eth0 connection.autoconnect no
  ```

### ping이 갑자기 50-200 ms로 튐

- **원인**: Wi-Fi 절전(power saving).
- **해결**: Jetson/클라이언트 쪽에서 절전을 끕니다. Jetson은 `802-11-wireless.powersave 2`, Linux 노트북도 동일합니다.

## 7. ROS 2 확인

노트북에서 `.1`, `.2`, `.10`이 모두 ping 되고 `ssh <jetson-user>@192.168.50.10`이 되면 ROS 2를 확인합니다. 노트북과 Jetson은 같은 EAP에 붙은 무선 클라이언트라서 ROS 2 트래픽이 Pi를 거치지 않습니다.

양쪽 모두:

```bash
export ROS_DOMAIN_ID=20
unset ROS_LOCALHOST_ONLY
```

Jetson:

```bash
ros2 topic pub /network_test std_msgs/msg/String "{data: 'hello'}" -r 2
```

노트북:

```bash
ros2 topic echo /network_test
```

`data: hello`가 계속 올라오면 됩니다. 폰 테더링을 뽑은 상태에서도 계속 보여야 합니다. 안 보이면 [docs/ros2-test.md](docs/ros2-test.md)를 보세요.

## 8. 성능 측정

**아직 측정값을 채우지 못했습니다.** 측정하지 않은 값은 임의로 채우지 않았습니다.

가장 중요한 측정은 **노트북 ↔ Jetson**입니다. 실제 지상국에서 로봇으로 가는 무선 링크이기 때문입니다.

| 구간 | Avg RTT | Max RTT | Packet Loss |
| --- | ---: | ---: | ---: |
| 노트북 ↔ EAP / Pi | — | — | — |
| 노트북 ↔ Jetson | — | — | — |

측정 방법과 거리별 표(10 m ~ 500 m)는 [docs/performance.md](docs/performance.md)에, 현장 테스트 기록 양식은 [docs/field-test.md](docs/field-test.md)에 있습니다. 무선 클라이언트에서 max RTT가 100 ms를 넘게 튀면 대부분 클라이언트 Wi-Fi 절전 때문이었습니다.

### 지금까지 확인한 것과 비어 있는 것

- 이전 구성(Pi AP + 브리지)에서 2026-10-04에 `gcs-netcheck.sh`를 돌려 LAN 항목 전부 PASS와 폰 테더링 인터넷 PASS를 확인했습니다. 그 구성은 더 이상 쓰지 않아서 **현재 구성의 검증 기록은 아닙니다.**
- 현재 구성(노트북과 Jetson이 `GEN2-ROBOT`에 직접 접속)에서 새 `gcs-netcheck.sh`의 실행 결과, ROS 2 테스트 결과, 성능 측정값, 거리별 테스트는 아직 기록이 없습니다.

## 9. 선택사항: USB 테더링

**이건 선택사항입니다. 로봇 네트워크 자체는 인터넷 없이 동작합니다.** 폰이 없으면 인터넷만 안 되고, 노트북 ↔ Jetson, 노트북 ↔ Pi, 노트북 ↔ EAP 통신과 ROS 2는 그대로입니다. 이 시스템의 목적은 인터넷 공유가 아닙니다.

```mermaid
flowchart LR
    PHONE["Android Phone<br/>LTE / 5G"]
    PI["Raspberry Pi 4"]
    EAP["EAP225"]
    CLIENTS["Laptop + Jetson"]

    PHONE -->|USB tether - optional| PI
    PI -->|Ethernet| EAP
    EAP -->|Wi-Fi| CLIENTS
```

- 안드로이드 폰을 Pi에 USB로 꽂고 USB 테더링을 켭니다. Pi에서는 `usb0` 또는 `enx...`로 보입니다.
- `wan-tether` 프로필이 `usb* enx*`에만 붙어서 폰에게서 DHCP로 주소를 받습니다 (`route-metric 100`).
- `eth0`(LAN)에서 테더링으로 나가는 트래픽만 NAT(masquerade) 합니다. 폰 쪽에서 LAN으로 새로 들어오는 연결은 막습니다.
- 테더링 인터페이스를 `eth0`와 브리지하지 않습니다. 라우팅/NAT만 씁니다.
- dnsmasq가 게이트웨이로 Pi(`.1`)를 줘서 노트북과 Jetson이 Pi를 통해 인터넷에 나갑니다.

`wan-tether` 프로필, NAT/포워딩 설정, 되돌리기 명령은 [docs/full-setup.md](docs/full-setup.md)의 Step 8–9에 있습니다. 설정 파일 예시는 [config/examples/](config/examples/)에 있습니다. 인터넷 공유를 안 쓸 거라면 Step 3의 dnsmasq 설정에서 게이트웨이/DNS 줄을 `dhcp-option=option:router` 한 줄로 줄이고 Step 8–9는 건너뜁니다.

## 10. 이전 구성 (사용하지 않음)

> **Deprecated / Not used in the final system.** 아래는 참고용입니다. 이 방식으로 구축하지 마세요.

처음에는 Pi가 지상국 쪽 Wi-Fi AP(`GEN2-GCS`)를 만들고, `wlan0`와 `eth0`를 `br0`로 브리지해서 `노트북 → Pi Wi-Fi → EAP → Jetson`으로 연결했습니다. 지상국 쪽과 로봇 쪽에 무선 네트워크를 따로 만든 셈인데, 필요 이상으로 복잡해서 지금의 EAP225 단일 AP 구성으로 바꿨습니다.

그때의 런북과 디버깅 기록은 [docs/archive/legacy-bridge-runbook.md](docs/archive/legacy-bridge-runbook.md)에 보관만 해 뒀습니다. 그 Pi를 그대로 쓴다면, 이전 프로필(`GEN2-GCS`, `robot-br`, `robot-eth`)은 지우지 말고 `connection.autoconnect no`로만 끄세요. ([full-setup.md](docs/full-setup.md) Step 2)

---

## 처음부터 전부 되돌리기

Step 1 백업으로 돌립니다. **로컬 콘솔에서 실행하세요** (네트워크 경로가 끊길 수 있습니다). 명령어는 [docs/full-setup.md](docs/full-setup.md) 맨 아래 "전체 되돌리기"에 있습니다.

## 저장소 구성

```
GEN2-GCS-Network/
├── README.md
├── docs/
│   ├── full-setup.md           # 명령어 전체 + 통과 조건 + 되돌리기 + 인터넷 공유
│   ├── troubleshooting.md      # 증상별 확인 + 겪은 문제
│   ├── ros2-test.md            # ROS 2 확인
│   ├── performance.md          # 성능 측정 방법 + 기록표
│   ├── field-test.md           # 현장 테스트 기록 양식
│   └── archive/
│       └── legacy-bridge-runbook.md   # 사용하지 않는 이전 구성
├── scripts/
│   ├── gcs-netcheck.sh         # Pi에서 돌리는 상태 점검
│   └── backup-network.sh       # 바꾸기 전에 Pi 설정 백업
├── config/
│   └── examples/               # dnsmasq / nftables / eth0 프로필 예시
└── images/                     # 장비 설치 사진
```

이 저장소에는 실제 Wi-Fi 비밀번호(PSK)나 `.nmconnection` 파일을 올리지 않습니다. 예시의 MAC 주소도 가짜 값입니다.
