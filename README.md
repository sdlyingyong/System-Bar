# System-Bar

macOS 菜单栏实时系统指标显示（Apple Silicon），最小开销、免 root、可开关配置。

```
菜单栏: 74°  25% M75%  6.1W  ↓ 12K ↑ 955B
```

## 特性

- 菜单栏直接显示数字，每 2s 实时刷新，**固定宽度不跳动**
- 可开关配置的指标（开关持久化，重启保留）：
  **CPU 温度 / 电池温度 / CPU 占用 / 内存占用 / GPU 占用 / 实时功耗 / 上传下载**
- **电池温度提醒**：> 40°C 显示 `🔥`（老化风险提醒；菜单栏文字颜色不可靠，用符号替代）
- 功耗口径与 **macmon / powermetrics Combined Power 一致**（实测偏差 <10%）
- 下拉菜单：指标开关 + 退出
- 免 root、免额外驱动、无 Dock 图标
- 低开销：空闲 CPU ≈1%（单核）、内存 ≈34MB

## 系统要求

- macOS 13+
- Apple Silicon（M1 实测；M2–M5 传感器命名可能略有差异，已做回退）

## 安装（一条命令）

```bash
./scripts/install.sh
```

安装到 `/Applications/System-Bar.app` 并注册登录自启（LaunchAgent）。

手动方式：

```bash
./scripts/build.sh          # 产物: build/System-Bar.app
open build/System-Bar.app
```

## 卸载

```bash
launchctl unload ~/Library/LaunchAgents/com.menutemp.app.plist
rm -rf /Applications/System-Bar.app
```

## 测试

```bash
./tests/test_smctemp.sh     # helper 输出格式/取值范围/稳定性（18 项）
./tests/test_format.sh      # 菜单栏格式化：定宽/边界值（22 项）
```

## 架构

```
System-Bar.app
├── Contents/MacOS/System-Bar   SwiftUI MenuBarExtra 应用（UI + 进程管理 + 配置）
└── Contents/MacOS/smctemp    C helper（指标读取，IOHID + mach + IOReport + sysctl）
```

- App 启动时拉起 `smctemp -i 2`，每 2 秒输出一行 `key=value;...`，App 解析后刷新菜单栏
- helper 异常退出自动重启；指标读取均为低频采样，空闲时 helper 几乎零 CPU

```
app/  System-BarApp.swift   菜单栏 UI + 开关配置（UserDefaults）
      TempMonitor.swift   helper 进程管理 + 输出解析
      Format.swift        定宽/格式化（可单测）
helper/smctemp.c          全部指标读取（单文件 C）
scripts/                  build.sh / install.sh / make-icon.sh
tests/                    测试脚本
icons/gen_icon.swift      应用图标生成器
```

## 指标来源（全部免 root）

| 指标 | 来源 |
|---|---|
| CPU 温度 | IOHID 事件系统（`pACC`/`eACC` 核传感器最大值，回退 `tdie`） |
| 电池温度 | IOHID `gas gauge battery` 传感器 |
| CPU 占用 | `host_processor_info` 两次采样差值 |
| 内存占用 | `host_statistics64`（active+wired+compressed）/ total |
| GPU 占用 | `AGXAccelerator` 的 `PerformanceStatistics`（活动监视器同源） |
| 实时功耗 | IOReport Energy Model，macmon/powermetrics 同口径（CPU+GPU+ANE） |
| 上传/下载速度 | sysctl 网卡字节计数差值（en* 接口） |

> 注：整机功耗（SMC `PSTR`）在本机 M1 上即使 root 也无法读取（驱动层限制），
> 因此采用与 macmon / powermetrics `Combined Power` 一致的 SoC 口径（实测与 powermetrics 偏差 <10%）。

## 图标

应用图标与菜单栏小图标由 `icons/gen_icon.swift` 程序化生成（蓝色水银温度计）。

```bash
./scripts/make-icon.sh      # 重新生成 AppIcon.icns
```

## 已知限制

- 仅 Apple Silicon；Intel 不支持
- 首次采样后（≤2s）CPU 占用 / 功耗 / 网速才有有效值（预热）
- 电池温度提醒使用符号（`🔥`），菜单栏文字颜色在部分版本不生效
- 功耗为 SoC 口径（CPU+GPU+ANE），不含屏幕与外设

## License

MIT
