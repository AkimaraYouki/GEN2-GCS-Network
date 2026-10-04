# 성능 측정

**아직 측정값을 채우지 못했습니다.** 측정하지 않은 값은 임의로 채우지 않습니다. 이전 구성에서 Pi ↔ EAP(유선) ping이 0.2–0.6 ms였다는 기록만 있습니다.

## 어디를 재나

가장 중요한 건 **노트북 ↔ Jetson**입니다. 실제 지상국에서 로봇으로 가는 무선 링크이기 때문입니다.

```
Laptop <-> EAP / Pi
Laptop <-> Jetson      <- 가장 중요
```

기록할 항목: RSSI, 거리, min/avg/max RTT, packet loss, UDP jitter, TCP throughput.

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

| 구간 | min RTT | avg RTT | max RTT | 손실 | 지터 (UDP) | TCP ↑ / ↓ |
| --- | --- | --- | --- | --- | --- | --- |
| 노트북 ↔ EAP / Pi | — | — | — | — | — | — |
| 노트북 ↔ Jetson | — | — | — | — | — | — |

거리별 (노트북 ↔ Jetson):

| Distance | RSSI | Avg RTT | Max RTT | Loss | TCP | UDP Jitter |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 m | | | | | | |
| 50 m | | | | | | |
| 100 m | | | | | | |
| 300 m | | | | | | |
| 500 m | | | | | | |

현장에서 실제로 테스트할 때는 [field-test.md](field-test.md)의 양식으로 한 건씩 남깁니다.
