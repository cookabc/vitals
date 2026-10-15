# UI 响应性能基线

优化前后必须用同一口径复测。口径写死在下面，改动测量方式就等于换了一套指标，数字不可比。

## 口径一：面板渲染耗时（app-hosted UI 冒烟测试）

`Tests/VitalsTests/DashboardRenderTests.swift` 里的 `面板渲染耗时在预算内`。
用 `NSHostingView` 真实加载 `PopoverView`，`cacheDisplay` 强制绘制成位图，统计 24 次分布。
数据源用未启动采样循环的 `SensorHub()`，因此不随本机负载漂移。

```bash
xcodebuild -project Vitals.xcodeproj -scheme Vitals -destination 'platform=macOS' \
  -derivedDataPath .ci-dd -only-testing:VitalsTests test 2>&1 | grep RENDER_US
```

| 版本 | p50 | p95 | max | n |
|---|---|---|---|---|
| 改前 2026-10-15 | 17.59 ms | 37.98 ms | 69.65 ms | 24 |
| 改后 2026-10-15 | 11.92 ms | 15.49 ms | 18.79 ms | 24 |
| 收尾复测 2026-10-15 | 10.45 ms | 12.23 ms | 16.43 ms | 24 |

一帧预算 16.7ms：改前 p50 已经超预算，p95 约为其 2.3 倍；改后 p50 与 p95 都回到预算内。

## 口径二：主线程采样耗时

`scripts/measure-tick.sh` 启动 Debug 包，固定 `-samplingInterval 1 -showProcesses YES`，
只收该 PID 的日志，30s 窗口取分布。数字来自 `SensorHub` 的 `tick` signpost 与日志行。

```bash
./scripts/measure-tick.sh 30
```

- `total_us`：一次 tick 的墙钟跨度（改前 = 主线程占用；改后含让给后台的等待）
- `off_us`：改后新增，`await` 后台采样队列的时间（进程枚举 + 逐进程 rusage + IOKit GPU 计数）
- `main_us`：`total_us - off_us`，主线程真正被占用的时长 —— **与改前的 `total_us` 同口径可比**

| 版本 | 主线程 p50 | 主线程 p95 | 主线程 max | n |
|---|---|---|---|---|
| 改前 2026-10-15（`total_us`） | 1.46 ms | 15.48 ms | 15.56 ms | 27 |
| 改后 2026-10-15（`main_us`） | 0.89 ms | 1.55 ms | 1.68 ms | 28 |

改前每约 4.5s 出现一次 ~15ms 的主线程尖峰，其中 ~14ms 是进程采样阶段；
逐进程 `proc_pid_rusage` 与 IOKit GPU 读取移到串行后台队列后，主线程只剩读数与发布，
p95 尖峰从 15.48ms 降到 1.55ms（约 10×）。

## 改动清单（改后）

1. `Core/SamplingEngine.swift`：`HeavySampler` 用一条 `.utility` 串行队列承接阻塞式系统调用，
   `SensorHub.performTick()` 改为 `async`，`await` 后检查取消和暂停状态再发布。
   暂停会取消当前采样循环并中断间隔休眠；恢复会重建速率基线，立即开始新一轮采样。
   旧任务即使稍后返回，也不能覆盖恢复后的读数。每轮采样独立记录后台等待耗时。
2. `UI/PixelArt.swift`：机身静态像素（4480 次点在多边形判定 + 数千次 fill）首次使用时烘焙成位图，
   逐帧只重画状态灯与活动粒子。
3. `Core/Localization.swift` + `UI/LocalizedContent.swift`：`.system` 偏好语言在视图层解析一次，
   `Locale` 每种语言只构造一次；面板一帧几十次取文案不再重复查偏好语言与建 Locale。

## 功能门禁

同一测试文件里的用例，任何性能改动后都必须保持通过：

- `面板绘制出内容`：画面非空白（ink 覆盖率 > 2%），防止重构后视图变空壳
- `暂停状态改变会真正反映到像素`：状态确实驱动到像素，防止数据绑定被改断
- `机身位图方向正确`：烘焙位图未上下颠倒（顶面与正面蓝色分量相对差 > 0.05）

`Tests/VitalsTests/SensorHubLifecycleTests.swift` 使用受控的 GPU／进程采样返回和独立偏好设置，
验证暂停后丢弃在途结果、快速暂停再恢复时旧结果不能覆盖新结果，以及恢复会中断间隔休眠、
只立即采样一次并继续正常周期。运行完整 `VitalsTests` 时会一并执行。

## 可选界面测试

`VitalsUI` scheme 单独运行 `VitalsUITests`：读取 `vitals.panel.*` 标识符，验证读数、
暂停冻结时间戳、恢复更新和详情切换。时间戳测试通过 macOS 的 AXValue 读取显示内容，
使用状态谓词等待，暂停期间使用反向期望。Canvas 绘制的 CPU 读数按标识符查找，
不限定为 StaticText。`--debug-panel` 会激活调试窗口，避免点击被其他应用遮挡；
这些窗口行为只存在于 Debug 构建的显式调试入口。
默认的 `Vitals` scheme 继续运行无需开发者证书的进程内测试。

界面测试需要本机钥匙串中的有效 Apple Development 证书，以及允许测试进程控制界面的权限。
通过命令指定证书所属团队，避免在项目中写死个人账户。团队 ID 是证书 subject 的 OU 字段，
不是证书显示名称末尾括号中的成员 ID。

```bash
xcodegen generate
xcodebuild test -project Vitals.xcodeproj -scheme VitalsUI \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .ci-dd-ui \
  CODE_SIGN_IDENTITY='Apple Development' DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

2026-10-15 修复复测：默认 scheme 的 37 项测试通过（含 5 项采样生命周期回归测试），
`VitalsUI` 的 4 项界面测试通过，Release 构建通过。上述界面结果来自本机签名的 Debug
测试窗口，不代表菜单栏弹出窗口在所有桌面空间和显示器上的交互均已验收。
