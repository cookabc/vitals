# Vitals — 菜单栏系统监控

Vitals 是一个只驻留在 macOS 菜单栏的系统监控工具。菜单栏图标实时显示 CPU 迷你曲线与占用百分比，点击展开 Liquid Glass 浮窗查看 CPU、内存、网络、磁盘、电池和进程明细。无 Dock 图标、无主窗口。

系统要求：macOS 26.0 及以上（Liquid Glass API）。开发环境为 Xcode 27 / macOS 27 SDK。

## 功能

- 应用图标与菜单栏使用统一的 V 形脉冲标记；菜单栏为自适应浅深色的单色矢量图标
- 菜单栏四种显示模式：图形、数字、图形+数字、图标；曲线颜色随负载变化（绿 / 橙 / 红），暂停时叠加暂停符号
- CPU：总占用、逐核心柱状图、最近 120 次采样的历史曲线（Swift Charts 面积图），通过展开按钮查看大图、峰值与用户态 / 系统态 / 空闲占比；系统页提供逐核数值明细
- 内存：已用 / 总量、不可分页-应用-压缩-可用分段条、系统内存压力、交换空间；展开查看文件缓存、空闲页和交换总量
- 网络：上下行速率与历史曲线，速率超过 512 B/s 时箭头符号出现 variableColor 动效
- 磁盘：系统盘容量进度条；系统页显示所有可读取块设备（含磁盘映像）的读写速率、读写次数和历史曲线，可在设置中关闭读写采样
- 系统：1 / 5 / 15 分钟平均负载、逻辑核心数、热状态、运行时间与低电量模式
- 电池：头部显示电量、悬停查看充电状态、剩余时间估算（IOPowerSources）；低电量模式标识
- 进程：按 CPU 排序的前 5 个进程，显示占用率与常驻内存（sysctl + libproc 差值采样）
- 热状态：fair / serious / critical 时浮窗头部出现温度符号，serious 以上带 pulse 动效
- 告警：CPU 持续高占用（默认连续 30 秒 ≥ 90%）、磁盘占用、热状态升级时发送系统通知，同一告警 5 分钟冷却
- 设置窗口：菜单栏模式、采样间隔（0.5 / 1 / 2 秒）、卡片开关、告警阈值、登录时启动

## 系统特性使用清单

| 类别 | API |
| --- | --- |
| 视觉 | Liquid Glass：`glassEffect`、`GlassEffectContainer`、`glassEffectID`（卡片展开时的玻璃形变）、`.buttonStyle(.glass)` |
| 视觉 | SF Symbols 效果：`variableColor`、`pulse`、`bounce`；`contentTransition(.numericText(value:))` 数字滚动 |
| 视觉 | Swift Charts 面积图与折线图、Canvas 逐核心柱图、`Text(_:style:)` |
| 逻辑 | `@Observable`（Observation 框架）驱动全部 UI；Swift 6 语言模式严格并发 |
| 逻辑 | `MenuBarExtra(.window)` 自定义标签与浮窗内容；`SettingsLink` |
| 逻辑 | 采样：mach `host_processor_info` / `host_statistics64`、`getifaddrs`、`sysctl`（vm.swapusage、KERN_PROC_ALL）、`proc_pid_rusage`、`getloadavg`、IOKit 块设备统计、IOPowerSources、`ProcessInfo.thermalState` |
| 逻辑 | `SMAppService` 登录项、AppIntents（快捷指令「暂停或继续 Vitals 监控」）、UserNotifications 告警 |
| 逻辑 | 结构化并发采样循环（`Task` + `Task.sleep`）、Swift Testing 单元测试 |

## 构建与安装

```bash
xcodegen generate
xcodebuild -project Vitals.xcodeproj -scheme Vitals -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData build
cp -R .build/DerivedData/Build/Products/Release/Vitals.app /Applications/
open /Applications/Vitals.app
```

测试：

```bash
xcodebuild test -project Vitals.xcodeproj -scheme Vitals -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData
```

App 图标由 `Tools/make_icon.swift` 生成（CoreGraphics 绘制，输出到资产目录后用 sips 缩出全套尺寸）：

```bash
swift Tools/make_icon.swift Sources/Vitals/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
```

## 架构

```
Sources/Vitals/
  VitalsApp.swift            App 入口：MenuBarExtra(.window) + Settings 场景
  Core/
    SensorHub.swift          @MainActor @Observable 状态机；采样循环与告警调度
    Samplers.swift           mach / getifaddrs / sysctl / IOKit 底层采样
    ProcessSampler.swift     sysctl(KERN_PROC_ALL) + proc_pid_rusage 进程采样
    BatteryKit.swift         IOPowerSources 电池读取
    AlertEngine.swift        纯逻辑告警引擎（阈值 + 持续时长 + 冷却）
    Models.swift             CPUTicks / CPUMath / DiskMath 等数据模型与纯函数
    LaunchAtLogin.swift      SMAppService 封装
    Units.swift, Ring.swift
  UI/
    PopoverView.swift        概览与系统详情、指标卡片与头部电池徽章
    MenuBarLabelView.swift   菜单栏标签（四种模式）
    SparklineRenderer.swift  CoreGraphics 迷你曲线与 V 形矢量标记
    SettingsView.swift       设置表单
    Theme.swift
  Intents/
    ToggleMonitoringIntent.swift
```

采样节奏：CPU / 内存 / 网络 / 系统负载 / 磁盘读写每个采样间隔刷新一次；电池每 5 个周期、磁盘容量每 30 个周期、进程每 5 秒刷新一次，降低常驻开销。

## 已知限制

- 进程名取自 `kinfo_proc.kp_proc.p_comm`，最长 16 字符，长进程名会被截断
- 进程 CPU 占用依赖 `proc_pid_rusage`，其他用户的进程可能取不到数据而跳过
- GPU 占用、具体温度、风扇转速与功耗未实现；后续需按机型验证数据源和权限，当前不显示估算值或模拟值
- 内存占用为内核页面计数估算，不承诺与活动监视器完全一致；内存压力读取失败时显示「不可用」
- 磁盘读写为可读取设备合计，包含磁盘映像，不代表单个启动卷；新接入、计数重置和恢复采样时先建立基线，避免假尖峰
- CPU、内存和网络卡片的展开按钮使用 `glassEffectID` 玻璃形变，在「减少动态效果」开启时退化为直接切换

## 视觉走查

Debug 构建可用 `--debug-panel` 将浮窗内容显示在普通窗口中；附加 `--debug-dark` 检查深色外观。这些入口不包含在 Release 构建中。

浮窗尺寸为 400 × 650，顶部固定显示采样状态、暂停和设置按钮。通过「概览 / 系统」切换页面。CPU、内存和网络支持展开；内容超出高度时可滚动。内存图例采用两列布局，网络和磁盘卡片等高。数字采用等宽字形，动态效果遵循系统「减少动态效果」设置。

## 数据口径

- `vm.swapusage` 按 `xsw_usage` 二进制结构读取，字段单位为字节。
- 进程 CPU 时间先按 `mach_timebase_info` 转为纳秒，再按时间差计算；单个逻辑核心满载为 100%，多线程进程可超过 100%。换算依据见 [Apple XNU task.c](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c)。
- 内存压力 sysctl 返回 dispatch 标志（1 / 2 / 4），不同于内核内部枚举。依据见 [Apple XNU kern_memorystatus_notify.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c)。
- 磁盘吞吐基于设备累计计数差值，按稳定的设备 ID 匹配后汇总。[Apple 对读取字节计数的说明](https://developer.apple.com/documentation/iokit/kioblockstoragedriverstatisticsbytesreadkey)。
