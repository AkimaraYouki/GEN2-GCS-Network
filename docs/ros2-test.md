# ROS 2 확인 & 성능 측정

## 멀티캐스트 디스커버리 확인

유니캐스트 피어를 수동으로 지정하지 않고도 토픽이 보여야 합니다. 양쪽 모두 `ROS_LOCALHOST_ONLY`가 꺼져 있어야 합니다.

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

기대 결과:

```
data: hello
---
data: hello
---
```

통과 조건: 폰을 뽑은 상태에서도 메시지가 계속 보입니다.

### 안 보일 때

- 노트북 방화벽(macOS 방화벽, ufw)이 UDP 7400번대를 막는지
- EAP의 Client Isolation과 멀티캐스트 필터가 꺼져 있는지
- 두 장비의 `ROS_DOMAIN_ID`가 같은지, `ROS_LOCALHOST_ONLY`가 unset인지
- 둘 다 같은 `192.168.50.0/24`에 있는지 (`ip addr`)

## 성능 측정

세 구간을 측정해서 기록합니다. Pi에는 iperf3가 기본으로 없으니 폰 테더링이 연결된 상태에서 설치합니다 (Pi, Jetson 각각).

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3
```

지연 · 손실 (보내는 쪽에서):

```bash
ping -c 200 -i 0.2 192.168.50.1      # 노트북 → Pi
ping -c 200 -i 0.2 192.168.50.10     # Pi → Jetson, 노트북 → Jetson
```

처리량 · 지터 (받는 쪽에서 `iperf3 -s`, 보내는 쪽에서 아래):

```bash
iperf3 -s                                   # 받는 쪽
iperf3 -c 192.168.50.10 -t 10              # TCP 업로드
iperf3 -c 192.168.50.10 -t 10 -R           # TCP 다운로드
iperf3 -c 192.168.50.10 -u -b 20M -t 10    # UDP: Jitter, Lost/Total 확인
```

### 기록표

아직 측정값을 채우지 못했습니다. 구축 당시 기록은 Pi ↔ EAP(유선) 0.2–0.6 ms뿐입니다. 무선 클라이언트에서 max RTT가 100 ms를 넘게 튀면 대부분 클라이언트 Wi-Fi 절전 때문이었습니다.

| 구간 | min RTT | avg RTT | max RTT | 손실 | 지터 (UDP) | TCP ↑ / ↓ |
| --- | --- | --- | --- | --- | --- | --- |
| 노트북 ↔ Pi | — | — | — | — | — | — |
| Pi ↔ Jetson | — | — | — | — | — | — |
| 노트북 ↔ Jetson | — | — | — | — | — | — |
