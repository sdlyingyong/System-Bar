# MenuTemp

macOS 菜单栏实时系统指标显示（Apple Silicon），最小开销、免 root。

```
菜单栏: 74° 25% 62% 4.2W   （可开关配置显示项）
```

## 特性

- 菜单栏直接显示数字，实时刷新（2s）
- 可开关配置的指标：**CPU 温度 / 电池温度 / CPU 占用 / 内存占用 / GPU 占用 / 实时功耗**（开关持久化）
- 下拉菜单：指标开关 + 退出
- 免 root、免额外驱动
- 低开销：空闲 CPU ≈1%（单核）、内存 ≈34MB

## 系统要求

- macOS 13+（`MenuBarExtra`）
- Apple Silicon（M1 实测；M2–M5 传感器命名可能略有差异，已做回退）

## 构建

```bash
./scripts/build.sh
# 产物: build/MenuTemp.app
```

## 运行

```bash
open build/MenuTemp.app
# 或复制到 /Applications 并作为登录项启动
```

## 测试

```bash
./tests/test_smctemp.sh
```

## 架构

```
MenuTemp.app
├── Contents/MacOS/MenuTemp   SwiftUI MenuBarExtra 应用（UI + 进程管理 + 配置）
└── Contents/MacOS/smctemp    C helper（指标读取，IOHID + mach + IOReport）
```

- App 启动时拉起 `smctemp -i 2`，每 2 秒输出一行 `key=value;...`，App 解析后刷新菜单栏
- helper 异常退出自动重启

## 指标来源（全部免 root）

| 指标 | 来源 |
|---|---|
| CPU 温度 | IOHID 事件系统（`pACC`/`eACC` 核传感器最大值，回退 `tdie`） |
| 电池温度 | IOHID `gas gauge battery` 传感器 |
| CPU 占用 | `host_processor_info` 两次采样差值 |
| 内存占用 | `host_statistics64`（active+wired+compressed）/ total |
| GPU 占用 | `AGXAccelerator` 的 `PerformanceStatistics`（活动监视器同源） |
| 实时功耗 | IOReport `Energy Model` 能量差值换算瓦特 |

## 已知限制

- 仅 Apple Silicon；Intel 不支持
- 首次采样后（≤2s）CPU 占用与功耗才有有效值（预热）
- 菜单栏文字颜色告警在部分 macOS 版本可能不生效（系统模板渲染）
