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

| 序号 | 周期 | Synthesis | Implementation | 参数 | 结果 | Utilization |
|------|---------------|--------------------|----------------|------|------|------|
| 1 | 5ns  | Default | extratimeopt | 全卷积 | Pass | LUT61% , task automatic, 一次卷2个 |
| 2 | 5ns  | Default | extratimeopt | 改成非零位置相加 | Fail | LUT31%, WTS -0.212ns, read_w接线过多! |
| 3 | 5ns  | Default | extratimeopt |task, 减少read_w的使用率 | Fail | LUT35%, WTS -0.61ns |
| 4 | 5ns  | Default | extratimeopt | task automatic, read逻辑被修改 | Fail | **实验3增量编译**, LUT35%, WTS -0.41ns |
| 5 | 5ns  | Default | extratimeopt | 相比实验4少了automatic, **2025 Vivado** | Pass | LUT29% |
| 6 | 5ns  | Default | extratimeopt | 多了automatic, **2025 Vivado** | Pass | 和实验5结果一样(可能是增量编译导致的)|

## Hessian Conv
| 周期 | Synthesis          | Implementation | 结果 | Utilization                      |
|------|--------------------|----------------|------|----------------------------------|
| 10ns | Default            | extratimeopt   | 失败 | LUT 180%, 位宽64                 |
| 10ns | Default            | extratimeopt   |    | 位宽 32, xczu7ev-ffvf1517-2LV-e |
