# Vitals — 菜单栏系统监控

Vitals 是一个只驻留在 macOS 菜单栏的系统监控工具。菜单栏图标实时显示 CPU 迷你曲线与占用百分比，点击展开 Liquid Glass 浮窗查看 CPU、内存、网络、磁盘、电池和进程明细。无 Dock 图标、无主窗口。

系统要求：macOS 26.0 及以上（Liquid Glass API）。开发环境为 Xcode 27 / macOS 27 SDK。

## 功能

- 菜单栏四种显示模式：图形、数字、图形+数字、图标；曲线颜色随负载变化（绿 / 黄 / 红），暂停时叠加暂停符号
- CPU：总占用、逐核心柱状图、2 分钟历史曲线（Swift Charts 面积图），点击卡片展开大图与峰值统计
- 内存：已用 / 总量、系统-应用-压缩-可用分段条、交换内存用量
- 网络：上下行速率与历史曲线，速率超过 512 B/s 时箭头符号出现 variableColor 动效
- 磁盘：系统盘容量进度条，随占用率变色
- 电池：电量、充电状态、剩余时间估算（IOPowerSources）；低电量模式标识
- 进程：按 CPU 排序的前 6 个进程，显示占用率与常驻内存（sysctl + libproc 差值采样）
- 热状态：fair / serious / critical 时浮窗头部出现温度符号，serious 以上带 pulse 动效
- 告警：CPU 持续高占用（默认连续 30 秒 ≥ 90%）、磁盘占用、热状态升级时发送系统通知，同一告警 5 分钟冷却
- 设置窗口：菜单栏模式、采样间隔（0.5 / 1 / 2 秒）、卡片开关、告警阈值、登录时启动

## 系统特性使用清单

| 类别 | API |
| --- | --- |
| 视觉 | Liquid Glass：`glassEffect`、`GlassEffectContainer`、`glassEffectID`（卡片展开时的玻璃形变）、`.buttonStyle(.glass)` |
| 视觉 | SF Symbols 效果：`variableColor`、`pulse`、`bounce`；`contentTransition(.numericText(value:))` 数字滚动 |
| 视觉 | Swift Charts 面积图、Canvas 逐核心柱图、`Text(_:style:)` |
| 逻辑 | `@Observable`（Observation 框架）驱动全部 UI；Swift 6 语言模式严格并发 |
| 逻辑 | `MenuBarExtra(.window)` 自定义标签与浮窗内容；`SettingsLink` |
| 逻辑 | 采样：mach `host_processor_info` / `host_statistics64`、`getifaddrs`、`sysctl`（vm.swapusage、KERN_PROC_ALL）、`proc_pid_rusage`、IOPowerSources、`ProcessInfo.thermalState` |
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
    Samplers.swift           mach / getifaddrs / sysctl 底层采样
    ProcessSampler.swift     sysctl(KERN_PROC_ALL) + proc_pid_rusage 进程采样
    BatteryKit.swift         IOPowerSources 电池读取
    AlertEngine.swift        纯逻辑告警引擎（阈值 + 持续时长 + 冷却）
    Models.swift             CPUTicks / CPUMath / SwapUsageParser 等纯函数
    LaunchAtLogin.swift      SMAppService 封装
    Units.swift, Ring.swift
  UI/
    PopoverView.swift        浮窗与六张指标卡片（Liquid Glass 容器）
    MenuBarLabelView.swift   菜单栏标签（四种模式）
    SparklineRenderer.swift  CoreGraphics 迷你曲线渲染
    SettingsView.swift       设置表单
    Theme.swift
  Intents/
    ToggleMonitoringIntent.swift
```

采样节奏：CPU / 内存 / 网络每个采样间隔刷新一次；电池每 5 个周期、磁盘每 30 个周期、进程每 5 秒刷新一次，降低常驻开销。

## 已知限制

- 进程名取自 `kinfo_proc.kp_proc.p_comm`，最长 16 字符，长进程名会被截断
- 进程 CPU 占用依赖 `proc_pid_rusage`，其他用户的进程可能取不到数据而跳过
- GPU 占用未实现；如需可基于 IOReport（`GPUPerformanceStatistics`）扩展
- 浮窗卡片点击展开使用 `glassEffectID` 玻璃形变，在「减少动态效果」开启时退化为直接切换
