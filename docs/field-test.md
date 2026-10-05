# Field Test

거리·환경별로 테스트한 결과를 쌓는 문서입니다. **측정하지 않은 값은 비워 두고, 임의로 채우지 않습니다.**

아직 기록된 테스트가 없습니다. 테스트할 때마다 아래 양식을 복사해서 `Test 1`, `Test 2`, … 로 아래에 추가하세요. 측정 방법은 [performance.md](performance.md), ROS 2 확인은 [ros2-test.md](ros2-test.md)에 있습니다.

기본 측정 대상은 **노트북 ↔ Jetson** (둘 다 `GEN2-ROBOT`에 붙은 상태)입니다.

## 양식

```markdown
## Test N

Date:
Location:
Distance (Laptop-EAP / Jetson-EAP):
Weather:
Laptop:
Jetson:
EAP settings (channel / power / mount height):

RSSI:
Ping avg:
Ping max:
Packet loss:
iperf TCP:
UDP jitter:
ROS 2 test:
Camera stream:
Result:
```

## 요약표

| Test | 날짜 | 거리 | RSSI | Ping avg / max | Loss | iperf TCP | ROS 2 | 비고 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| — | — | — | — | — | — | — | — | — |

## 현장 투입 전 체크리스트

체크한 항목은 날짜와 결과를 위의 Test 기록에 같이 남깁니다. 아직 아무것도 확인하지 않은 상태입니다.

**부팅/복구**

- [ ] Pi cold boot 후 DHCP 자동 시작
- [ ] EAP225 cold boot 후 SSID 복구
- [ ] Jetson 자동 Wi-Fi 연결
- [ ] Laptop DHCP 정상 할당
- [ ] Pi/EAP 재부팅 후 자동 복구 (손대지 않고 `gcs-netcheck.sh`가 `ALL OK`)

**연결**

- [ ] Laptop → Pi ping
- [ ] Laptop → EAP ping
- [ ] Laptop → Jetson ping
- [ ] Jetson SSH

**ROS 2**

- [ ] ROS 2 discovery (`ros2 node list`, `ros2 topic list`)
- [ ] ROS 2 topic 송수신 (`ros2 topic hz`까지)

**측정**

- [ ] 10분 이상 latency / packet-loss 측정
- [ ] 거리별 RSSI / RTT / packet loss 기록

**USB 테더링 (선택)**

- [ ] USB tether 연결 후 인터넷 확인
- [ ] USB tether 제거 후 로봇 LAN 유지

**실제 운용**

- [ ] 실제 로봇 주행 중 통신 시험
