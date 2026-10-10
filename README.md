# Vitals — 菜单栏系统监控

Vitals 是一个只驻留在 macOS 菜单栏的系统监控工具。菜单栏图标实时显示 CPU 迷你曲线与占用百分比，点击展开深色像素仪表盘查看 CPU、内存、网络、磁盘、电池和进程明细。无 Dock 图标、无主窗口。

系统要求：macOS 26.0 及以上。开发环境为 Xcode 27 / macOS 27 SDK。

## 功能

- 应用图标使用像素 V 形脉冲，菜单栏保留清晰的单色 V 形标记；菜单栏为自适应浅深色的单色矢量图标
- 菜单栏四种显示模式：图形、数字、图形+数字、图标；曲线颜色随负载变化（绿 / 橙 / 红），暂停时叠加暂停符号
- CPU：总占用、逐核心柱状图、最近 120 次采样的点阵历史曲线，主屏显示分段逐核柱条及性能核 / 能效核数量；DETAILS 入口提供历史曲线、平均负载和逐核明细
- GPU：主屏显示驱动报告的占用率、历史、使用中 / 已分配内存；明细增加渲染与分块占用，缺失字段显示 N/A
- 内存：已用 / 总量、不可分页-应用-压缩-可用分段条、系统内存压力、交换空间；展开查看文件缓存、空闲页和交换总量
- 网络：上下行速率与历史曲线，像素曲线区分上传与下载，明细页保留峰值统计
- 磁盘：系统盘容量进度条；明细页显示所有可读取块设备（含磁盘映像）的读写速率、读写次数和历史曲线，可在设置中关闭读写采样
- 系统：1 / 5 / 15 分钟平均负载、逻辑核心数、热状态、运行时间与低电量模式
- 电池：SYSTEM 区域显示电量、悬停查看充电状态、剩余时间估算（IOPowerSources）；低电量模式标识
- 进程：明细页显示按 CPU 排序的前 5 个进程，显示占用率与常驻内存（sysctl + libproc 差值采样）
- 热状态：SYSTEM 区域使用 NORMAL / WARM / HOT / CRITICAL 显示系统热状态
- 告警：CPU 持续高占用（默认连续 30 秒 ≥ 90%）、磁盘占用、热状态升级时发送系统通知，同一告警 5 分钟冷却
- 语言：可选择跟随系统、简体中文或 English，主屏、明细、设置、提示和通知同步切换；必要的产品名、进程名和技术缩写保留原文
- 设置窗口：菜单栏模式、采样间隔（0.5 / 1 / 2 秒）、CPU / GPU / 内存 / 网络 / 磁盘 / 传感器 / 电池 / 进程开关、告警阈值、登录时启动

## 系统特性使用清单

| 类别 | API |
| --- | --- |
| 视觉 | Canvas 像素字形、等距主机插画、分段柱条、点阵曲线，方角边框与固定深色配色 |
| 视觉 | 主屏、明细与设置使用同一套 PixelSection / PixelSegments / PixelTrace / 像素开关与选项按钮 |
| 视觉 | Canvas 点阵折线、分段逐核柱图，SF Symbols 用于操作图标 |
| 逻辑 | `@Observable`（Observation 框架）驱动全部 UI；Swift 6 语言模式严格并发 |
| 逻辑 | `MenuBarExtra(.window)` 自定义标签与浮窗内容；`openSettings` + 设置窗口激活 |
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
    GPUSampler.swift         IOAccelerator 驱动统计与缺失值校验
    BatteryKit.swift         IOPowerSources 电池读取
    AlertEngine.swift        纯逻辑告警引擎（阈值 + 持续时长 + 冷却）
    Models.swift             CPUTicks / CPUMath / DiskMath 等数据模型与纯函数
    LaunchAtLogin.swift      SMAppService 封装
    Localization.swift      语言选择、资源查找与格式化
    Units.swift, Ring.swift
  UI/
    PopoverView.swift        浮窗入口
    PixelDashboardView.swift 像素仪表盘、主屏 / 明细导航
    PixelArt.swift           自绘像素字形与等距主机插画
    PixelDetailsView.swift   同一套像素样式的完整明细
    PixelControls.swift      设置与明细共用的像素控件
    LocalizedContent.swift   跨窗口语言与地区环境
    MenuBarLabelView.swift   菜单栏标签（四种模式）
    SparklineRenderer.swift  CoreGraphics 迷你曲线与 V 形矢量标记
    SettingsView.swift       像素设置页
    SettingsPresenter.swift  设置窗口激活、首次展示与已有窗口置前
    Theme.swift
  Intents/
    ToggleMonitoringIntent.swift
```

采样节奏：CPU / GPU / 内存 / 网络 / 系统负载 / 磁盘读写每个采样间隔刷新一次；电池每 5 个周期、磁盘容量每 30 个周期、进程每 5 秒刷新一次，降低常驻开销。

## 已知限制

- 进程名取自 `kinfo_proc.kp_proc.p_comm`，最长 16 字符，长进程名会被截断
- 进程 CPU 占用依赖 `proc_pid_rusage`，其他用户的进程可能取不到数据而跳过
- GPU 数据依赖驱动提供的 IOKit PerformanceStatistics，非稳定的跨机型接口；不可用字段为 N/A，不以 0 代替
- GPU 使用中 / 已分配内存为驱动计数，与系统内存分类可能重叠，不能相加或推导独立显存
- 具体温度、风扇转速、时钟频率与功耗未接入可靠数据源，显示 N/A；系统热状态不换算成摄氏度
- 内存占用为内核页面计数估算，不承诺与活动监视器完全一致；内存压力读取失败时显示「不可用」
- 磁盘读写为可读取设备合计，包含磁盘映像，不代表单个启动卷；新接入、计数重置和恢复采样时先建立基线，避免假尖峰
- 像素主机是装饰性示意，不代表当前 Mac 的机壳外观；指示像素随真实 CPU 占用变化
- 像素主屏和明细不使用持续动画，仅随真实采样更新

## 视觉走查

Debug 构建可用 `--debug-panel` 将浮窗内容显示在普通窗口中；附加 `--debug-dark` 检查深色外观。这些入口不包含在 Release 构建中。

浮窗尺寸为 680 × 500，采用固定深色像素仪表盘。上部为主机示意、逐核柱条与 GPU 历史，中部为内存分段条，下部为网络、磁盘、系统；进程排行放入明细页。DETAILS 进入可滚动的明细页，MONITOR 返回主屏；暂停和设置始终可访问。

风格参考：[像素系统监控面板](https://hub.v2core.com/p/c7e22d4d210af8835c20a4de7734dd7c139ddac335c3689e030e1de4eb6b84c8)。所有图形通过原生 SwiftUI / Canvas 绘制；文案来自 `Resources/en.lproj` 与 `Resources/zh-Hans.lproj`。英文短标题采用像素字形，中文或缺字文本回退到清晰的系统字体。GPU 使用本机驱动报告的真实读数；参考中的功耗、频率与温度读数不复制、不模拟。


## 数据口径

- `vm.swapusage` 按 `xsw_usage` 二进制结构读取，字段单位为字节。
- 进程 CPU 时间先按 `mach_timebase_info` 转为纳秒，再按时间差计算；单个逻辑核心满载为 100%，多线程进程可超过 100%。换算依据见 [Apple XNU task.c](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c)。
- 内存压力 sysctl 返回 dispatch 标志（1 / 2 / 4），不同于内核内部枚举。依据见 [Apple XNU kern_memorystatus_notify.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c)。
- 磁盘吞吐基于设备累计计数差值，按稳定的设备 ID 匹配后汇总。[Apple 对读取字节计数的说明](https://developer.apple.com/documentation/iokit/kioblockstoragedriverstatisticsbytesreadkey)。

模块开关同时控制主屏和明细。关闭 GPU / 磁盘读写也会停止对应采样；CPU / 内存继续为菜单栏和告警提供数据。多 GPU 时主屏显示占用最高的设备，设备切换会重建 GPU 历史，明细列出各设备。性能核 / 能效核只显示系统报告的总数，不推测逐核编号归属。
