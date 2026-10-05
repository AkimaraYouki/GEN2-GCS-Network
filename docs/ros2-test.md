# ROS 2 확인

노트북과 Jetson은 같은 EAP225에 붙은 무선 클라이언트입니다. ROS 2 트래픽이 Pi를 거치지 않고 EAP를 통해 바로 오갑니다.

```
Laptop --Wi-Fi--> EAP225 --Wi-Fi--> Jetson
```

둘 다 `192.168.50.0/24`에 있고, ROS 2 DDS 멀티캐스트가 그대로 통과해야 합니다. 유니캐스트 피어를 수동으로 지정하지 않고도 토픽이 보여야 합니다.

## 확인

양쪽 모두:

```bash
export ROS_DOMAIN_ID=20
unset ROS_LOCALHOST_ONLY
```

Jetson:

```bash
ros2 topic pub /network_test std_msgs/msg/String "{data: 'hello'}" -r 2
```

GCS 노트북:

```bash
ros2 topic echo /network_test
```

기대 결과:

```
data: hello
---
data: hello
---
```

**통과 조건:** 메시지가 계속 보입니다. 폰 테더링을 뽑은 상태에서도 계속 보여야 합니다.

### ping만으로 끝내지 않습니다

같은 subnet이고 `ping`이 된다고 ROS 2 discovery가 검증된 것은 아닙니다. 위 `pub`/`echo`가 되는 상태에서 노트북에서 아래까지 확인합니다.

```bash
ros2 node list
ros2 topic list           # /network_test 가 보여야 함
ros2 topic hz /network_test   # 발행 주기(-r 2 이면 약 2 Hz)와 비교
```

`node list`와 `topic list`에 Jetson 쪽 노드/토픽이 보이고, `topic hz`가 발행 주기와 맞아야 통과로 봅니다.

## 안 보일 때

- 양쪽 `ROS_DOMAIN_ID`가 같은지, `ROS_LOCALHOST_ONLY`가 unset인지
- 둘 다 `GEN2-ROBOT`에 붙어 있고 같은 `192.168.50.0/24`인지 (`ip addr`)
- 노트북 방화벽(macOS 방화벽, ufw)이 UDP 7400번대를 막는지
- EAP의 **Client Isolation**, **Guest Network / Portal**, **VLAN isolation**, 멀티캐스트 필터가 모두 꺼져 있는지

## 참고: 제어 루프는 이 망을 쓰지 않습니다

로봇 밸런스 제어는 Jetson 로컬(IMU + 모터 CAN 피드백 + 로컬 컨트롤러)에서 돕니다. Wi-Fi는 ROS 2, 텔레옵, SSH, SLAM 시각화, 진단, 카메라 미리보기, 로깅, 모니터링에만 씁니다. 그래서 일시적인 Wi-Fi 패킷 손실이 로봇을 직접 불안정하게 만들지는 않습니다.

역할 분리는 아래처럼 유지하는 것을 권장합니다.

```text
Wi-Fi
├─ teleoperation command
├─ RViz / monitoring
├─ SLAM map
├─ camera
└─ logging/status

Jetson local
├─ balance controller
├─ motor CAN
├─ IMU feedback
├─ safety state machine
└─ communication-loss handling
```

권장 사항: Wi-Fi가 순간적으로 끊겨도 balance loop는 영향을 받지 않아야 하고, 일정 시간 이상 명령이 끊기면 Jetson이 로컬에서 안전 정지하도록 합니다. **이 안전 정지(통신 두절 처리)가 현재 구현돼 있는지는 이 저장소에서 확인한 바 없습니다.** 구현 후 여기에 시간 기준과 동작을 기록하세요.

지연·처리량 측정은 [performance.md](performance.md)에 있습니다.
