# 성능 측정

**아직 측정값을 채우지 못했습니다.** 측정하지 않은 값은 임의로 채우지 않습니다. 이전 구성에서 Pi ↔ EAP(유선) ping이 0.2–0.6 ms였다는 기록만 있습니다.

## 어디를 재나

가장 중요한 건 **노트북 ↔ Jetson**입니다. 실제 지상국에서 로봇으로 가는 무선 링크이기 때문입니다.

```
Laptop <-> EAP / Pi
Laptop <-> Jetson      <- 가장 중요
```

기록할 항목: RSSI, 거리, min/avg/max RTT, **RTT 95 percentile**, packet loss, UDP jitter, TCP throughput, **ROS 2 topic loss**. 평균 latency보다 순간적인 jitter와 packet loss가 더 중요합니다.

## 준비

Pi와 Jetson에 iperf3를 설치합니다. 인터넷이 필요하니 폰 테더링이 연결된 상태에서 합니다.

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3
```

## 지연 · 손실 (보내는 쪽에서)

```bash
ping -c 200 -i 0.2 192.168.50.1      # 노트북 → Pi (EAP까지의 Wi-Fi 구간 + 유선)
ping -c 200 -i 0.2 192.168.50.2      # 노트북 → EAP
ping -c 200 -i 0.2 192.168.50.10     # 노트북 → Jetson
```

RTT 95 percentile은 ping 결과를 저장해서 계산합니다.

```bash
ping -c 200 -i 0.2 192.168.50.10 | tee ping.log
grep -oE 'time=[0-9.]+' ping.log | cut -d= -f2 | sort -n | awk '{a[NR]=$1} END{print "p95 =", a[int(NR*0.95)], "ms"}'
```

## ROS 2 topic loss (간이)

Jetson에서 일정 주기로 발행하고, 노트북에서 받은 주기를 비교합니다.

```bash
ros2 topic pub /network_test std_msgs/msg/String "{data: 'hello'}" -r 50    # Jetson
ros2 topic hz /network_test                                                   # 노트북. 평균 rate가 50 Hz에서 얼마나 빠지는지
```

받은 rate가 발행 rate보다 낮은 비율이 대략적인 손실입니다. 정확한 손실 계산이 필요하면 메시지에 카운터를 넣어 누락 개수를 세야 합니다.

## 처리량 · 지터

받는 쪽에서 `iperf3 -s`, 보내는 쪽에서 아래를 실행합니다. 노트북 ↔ Jetson으로 재세요.

```bash
iperf3 -s                                   # 받는 쪽
iperf3 -c 192.168.50.10 -t 10              # TCP 업로드
iperf3 -c 192.168.50.10 -t 10 -R           # TCP 다운로드
iperf3 -c 192.168.50.10 -u -b 20M -t 10    # UDP: Jitter, Lost/Total 확인
```

무선 클라이언트에서 max RTT가 100 ms를 넘게 튀면 대부분 클라이언트 Wi-Fi 절전 때문이었습니다 (Jetson 설정 [full-setup.md](full-setup.md) Step 5).

## 기록표

구간별:

| 구간 | min RTT | avg RTT | p95 RTT | max RTT | 손실 | 지터 (UDP) | TCP ↑ / ↓ | ROS 2 topic loss |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 노트북 ↔ EAP / Pi | — | — | — | — | — | — | — | — |
| 노트북 ↔ Jetson | — | — | — | — | — | — | — | — |

거리별 (노트북 ↔ Jetson):

| Distance | RSSI | Avg RTT | p95 RTT | Max RTT | Loss | TCP | UDP Jitter | ROS 2 loss |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 m | | | | | | | | |
| 50 m | | | | | | | | |
| 100 m | | | | | | | | |
| 300 m | | | | | | | | |
| 500 m | | | | | | | | |

현장에서 실제로 테스트할 때는 [field-test.md](field-test.md)의 양식으로 한 건씩 남깁니다.

## PASS 기준

**기준 숫자는 아직 정하지 않았습니다.** 실제 실험(거리별 측정, 주행 중 통신 시험)을 해 보고 정한 값을 여기에 적습니다. 지금 임의로 정하지 않습니다.

| 항목 | PASS 기준 | 근거 실험 |
| --- | --- | --- |
| RTT 평균 | — | — |
| RTT 95 percentile | — | — |
| 지터 | — | — |
| Packet loss | — | — |
| ROS 2 topic loss | — | — |
| 거리별 RSSI (사용 가능 최소 거리/RSSI) | — | — |
