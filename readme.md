# Intro

- This project implements the **Sobel Conv -> Hessian Conv**, part of a **Drone Tracking** Task

# Record

## Sobel Conv(Conv, READ同步)

| 周期 | Synthesis          | Implementation | 结果 | Utilization |
|------|--------------------|----------------|------|------|
| 6ns  | AreaMultThresHoldDSP | High Net-Delay | 失败| |
| 8ns  | AreaMultThresHoldDSP | extratimeopt | 失败| LUT 96% |
| 6ns  | routes avalability | extratimeopt   | 失败 | LUT 96% |
| 8ns  | routes avalability | extratimeopt   |  WTS=-0.536ns  | LUT > 100% |
| 7.5ns  | Default | extratimeopt   | 失败 | LUT 96% |
| 7.5ns(AdderTree更大)  | Default | extratimeopt   | 失败 | LUT 96% |
| 8ns  | Default | extratimeopt   | WTS=0.001ns | LUT 23% (23是错的，是ZCU104基础上增量编译的)|
| 8ns  | Default | High Net-Delay | 失败 | LUT 96% |


## Sobel Conv(Conv, READ不同步)

| 周期 | Synthesis          | Implementation | 结果 | Utilization |
|------|--------------------|----------------|------|------|
| 10ns  | Default | extratimeopt | 失败| LUT 148% |
| 5ns  | Default | extratimeopt | 失败| LUT 178%, buffer改成3元赋值|
| 5ns  | Default | extratimeopt | 失败 | LUT 153%, task automatic|
| 5ns  | Default | extratimeopt | 失败 | LUT , task automatic, 一次卷2个 |


## Sobel Conv(Conv, READ不同步, ZCU104)

| 周期 | Synthesis          | Implementation | 结果 | Utilization |
|------|--------------------|----------------|------|------|
| 5ns  | Default | extratimeopt | ok| LUT61% , task automatic, 一次卷2个 |

## Hessian Conv
| 周期 | Synthesis          | Implementation | 结果 | Utilization                      |
|------|--------------------|----------------|------|----------------------------------|
| 10ns | Default            | extratimeopt   | 失败 | LUT 180%, 位宽64                 |
| 10ns | Default            | extratimeopt   |    | 位宽 32, xczu7ev-ffvf1517-2LV-e |
