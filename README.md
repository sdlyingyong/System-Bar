# MenuTemp

macOS 菜单栏实时显示 Apple Silicon CPU 温度，最小开销、免 root。

```
菜单栏: 74°
```

## 特性

- 菜单栏直接显示当前 CPU 温度（取 P-Core/E-Core 传感器最大值，回退 tdie）
- 下拉菜单列出全部温度传感器
- 免 root、免额外驱动，通过 IOHID 事件系统读取 SMC 传感器
- 低开销：空闲 CPU ≈1.5%（单核）、内存 ≈27MB

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
├── Contents/MacOS/MenuTemp   SwiftUI MenuBarExtra 应用（UI + 进程管理）
└── Contents/MacOS/smctemp    C helper（IOHID 温度读取，事件驱动）
```

- App 启动时拉起 `smctemp -i 2`，每 2 秒输出一行 `cpu=74.0;NAME=value;...`
- App 通过管道解析并刷新菜单栏；helper 异常退出自动重启

## CPU 温度定义

M1 无独立 CPU 传感器。取 `pACC`/`eACC`（P 核/E 核）传感器最大值作为 CPU 温度，
无核传感器时回退到 `tdie`（芯片 die）最大值。

## 已知限制

- 仅 Apple Silicon；Intel 不支持
- 菜单栏文字颜色告警（>85° 变红）在部分 macOS 版本可能不生效（系统模板渲染）
