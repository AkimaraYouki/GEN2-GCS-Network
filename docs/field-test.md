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
