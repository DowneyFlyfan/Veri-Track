# Intro

- This project implements the **Sobel Conv -> Hessian Conv**, part of a **Drone Tracking** Task

# Record

| 周期 | Synthesis          | Implementation | 结果 | Utilization |
|------|--------------------|----------------|------|------|
| 6ns  | AreaMultThresHoldDSP | High Net-Delay | 失败| |
| 8ns  | AreaMultThresHoldDSP | extratimeopt | 失败| LUT 96% |
| 6ns  | routes avalability | extratimeopt   | 失败 | LUT 96% |
| 8ns  | routes avalability | extratimeopt   |  WTS=-0.536ns  | LUT > 100% |
| 7.5ns  | Default | extratimeopt   | 失败 | LUT 96% |
| 7.5ns(AdderTree更大)  | Default | extratimeopt   | 失败 | LUT 96% |
| 8ns  | Default | extratimeopt   | WTS=0.001ns | LUT 23% |
| 8ns  | Default | High Net-Delay | 失败 | LUT 96% |
