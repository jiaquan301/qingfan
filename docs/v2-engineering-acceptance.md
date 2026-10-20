# 青番 V2｜技术架构、研发任务与验收标准（正式版）

> 版本：V2 技术基线；日期：2026-10-20  
> 窗口架构：**一个原生桌面窗口 + Flutter 内部的全/迷你/任务/设置视图**  
> 首发：Ubuntu 22.04/24.04；Windows/macOS 作为持续集成目标  
> 状态：技术方案，最终“可发布”必须由真实构建、图形自动测试和实体桌面验收共同决定。

## 1. 技术评审与最终选型

| 方案 | 自绘/精致动效 | Linux 桌面窗口控制 | 三平台共用代码 | 决策 |
| --- | --- | --- | --- | --- |
| 当前 Python + GTK3 | 可做，但需要大量 Cairo/GTK 原生适配 | 已有兼容问题 | 维护成本高 | 保留为回退基线 |
| Qt6 + QML / C++ | 很强 | 成熟，仍受 Wayland 限制 | 很强 | 合理备选 |
| Tauri + Web UI | 强 | WebView/窗口层行为因平台而异 | 很强 | 不优先 |
| **Flutter 稳定版 + Dart** | **自绘表盘、动画和视图复用适合** | 通过隔离的原生插件控制，仍受系统限制 | **强** | **最终架构选型** |

### 必须注意的新技术风险

Flutter 官方于 2026-08 公布的新 Desktop Windowing API 仍为实验特性，仅在 main 开发通道开放，并明确不建议在生产应用中使用。因此正式版**不依赖该实验 API**。采用 Flutter 稳定版与经过固定版本测试的 `window_manager` 插件，平台能力由本项目适配器统一抽象，以便今后无痛替换。

相关官方资料：
- https://docs.flutter.dev/platform-integration/desktop
- https://docs.flutter.dev/reference/supported-platforms
- https://flutter.dev/blog/desktop-windowing-apis
- https://pub.dev/packages/window_manager

**窗口 API 版本不能浮动发布。** 依赖锁文件必须入库；SDK 及原生插件更新必须经过 X11/Wayland/Windows/macOS 窗口矩阵重新验证。

## 2. 技术栈与依赖边界

- Flutter **stable**（CI 固定审核通过的补丁版本），Dart 3，空安全。
- Flutter SDK 基础绘制（`CustomPainter`）、`AnimationController`、系统辅助功能/主题支持。
- `window_manager`（当前可候选 `0.5.2`）：尺寸、显示/隐藏、置顶请求、移动、关闭、背景透明；包升级前必须检查兼容性。
- `path_provider`：可靠定位应用数据目录；无需账号和数据库服务。
- `flutter_test`、Flutter 自带测试工具及 `flutter_lints`；不引入复杂全局状态框架，仅使用可测试的 Controller/Notifier。
- 独立的 `DesktopWindowAdapter` 接口隐藏窗口插件 API；其他业务代码不允许直接调用第三方窗口插件。
- 本地状态保存为经过版本化 Schema 校验的 JSON，以临时文件写入、flush、同目录 rename 方式避免常见部分写入；崩溃恢复仍需做好备份与损坏处理。
- 不使用 Electron、WebView、Python 子进程、数据库服务、远端 API；Linux 不要求预装 Python/GTK3 GUI 包（Flutter runner 自身仍依赖正常图形栈）。

## 3. 架构分层

```text
app/
  bootstrap                    启动、单例窗口、设置加载、恢复
  domain/
    focus_engine               计时状态机、轮次、完成事件（与 UI 无关）
    tasks                      任务状态、排序、完成/恢复
    preferences                透明度、置顶、窗口模式、时间设置
  application/
    app_controller             统一业务状态和指令入口
    session_repository         保存/恢复和损坏处理
  infrastructure/
    desktop_window_adapter     window_manager 插件唯一入口
    local_json_store           原子本地存储
    notifications              系统通知抽象
  presentation/
    crystal_clock              表盘/圆环/数字、控制热区
    mini_clock                 迷你时钟
    task_drawer                长清单管理
    settings_sheet             设置浮层
    theme                      视觉令牌和动效
```

依赖方向：展示层 → 应用控制器 → 领域层；基础设施由控制器注入，不允许领域模型依赖 Flutter `BuildContext` 或 GTK/Python 代码。

### 应用生命周期

1. `main()` 创建 WidgetsBinding → 加载设置 → 初始化窗口管理插件 → 创建**唯一主窗口**。
2. **首次帧前**设置无装饰、背景、初始尺寸、置顶请求；布局完整后执行 show。
3. 默认模式 full；禁止应用内隐式创建第二个顶层窗口。
4. 应用“打开任务清单”实际执行主窗口尺寸调整 + 当前内容切换，不是启动另一个进程或第二窗口。
5. full ↔ mini 切换只更新当前窗口尺寸与同一个业务状态源。
6. 进入设置界面使用 Flutter 内部 ModalBarrier/Overlay，不产生额外原生窗口。
7. 关闭时保存计时快照与窗口偏好，释放插件监听器。

## 4. 关键状态机

### 计时

```text
阶段 Phase: focus | shortBreak | longBreak
运行 RunState: idle | running | paused | finished
活动任务: taskId?  （可为 null；空值代表自由专注）
```

- 无任务直接开始 focus 合法，任何任务界面都不得强制要求 `taskId != null`。
- 单击表盘中心执行 `toggleRun()`；按钮重复触发使用单线程事件串行化和防重复事务。
- 运行中：当前时间 = 基于单调时钟的 elapsed 与基线 remaining 计算；**不能靠每秒减一维持权威状态**。
- 睡眠/恢复：保存的 UTC 截止时间辅助恢复；恢复时基于系统时间与生命周期事件重新计算，发现时钟大幅回拨/超前须采取可解释的保守策略。
- 完成判定 idempotent：一次 `focusSessionId` 最多记录一次完成事件，不因应用恢复或 UI 重建重复累加。
- focus 完成：全局番茄数 +1；存在有效的当前任务才为该任务 +1；自由专注不能误记入别的任务。
- focus 结束转入休息待开始，按四次一长休息规则；不自动开下一轮。
- 对正在运行的当前任务做切换/完成/删除操作必须中断并提示，不允许破坏计时状态。

### 视图与窗口

```text
ClockMode: full | mini
OverlayMode: none | tasks | settings
alwaysOnTopDesired: bool
alwaysOnTopEffective: supported | applied | unavailable | unknown
```

所有模式共用同一个 Window ID、同一个 `AppController`。

- **必须串行执行窗口转换**：锁定 transition → 记录位置 → 变更内容布局 → setSize → 查询实际尺寸 → 尝试维持置顶 → 解除锁定。
- 主窗口允许自由拖动，但只有非交互边缘作为拖动热区；中心计时热区只处理启停。
- 置顶失败不能悄悄吞掉：显示简洁说明“当前桌面不支持强制置顶”；提供继续使用普通窗口。
- 设置中保留 `desired` 值，UI 不得把成功发出调用当成系统确实支持。
- 若系统禁止透明背景，则使用指定的纯色回退，不使用不可见的无边框黑色方块。
- 位置恢复要先查询可用显示器边界，避免上次在外接显示器的位置导致启动后找不到窗口。

## 5. 产品级窗口适配策略

### Linux X11
- 尺寸、移动、置顶、透明 alpha 在 CI（Xvfb）和真实 GNOME/X11 分别验证。
- 检查窗口从 full → mini → full 的实际尺寸，以及桌面其他窗口遮挡测试。
- `setAlwaysOnTop(true)` 后还要检查可见效果和回读（如平台接口支持）。

### Linux Wayland
- Wayland 的窗口管理策略受合成器控制，不能承诺任意全局位置移动或绝对置顶。
- 能力不足时向用户明确反馈；默认可工作，不阻止计时。
- 避免通过私有 Shell 扩展或环境变量冒充普适平台能力。
- 首次发布必须在 Ubuntu GNOME Wayland 实机记录结果和降级行为。

### macOS 与 Windows
- 验证 Retina / 高 DPI、自定义无边框区域可拖动、置顶、任务栏/程序坞交互、正常退出和安装包。
- 窗口显示状态必须不影响其他应用；绝不能“抢占其他程序窗口置顶权限”。

## 6. 数据模型

```json
{
  "schemaVersion": 2,
  "settings": {
    "focusMinutes": 25,
    "shortBreakMinutes": 5,
    "longBreakMinutes": 15,
    "glassOpacity": 0.90,
    "alwaysOnTop": false,
    "clockMode": "full"
  },
  "tasks": [
    {"id": "uuid", "title": "设计方案", "done": false, "pomodoros": 2}
  ],
  "currentTaskId": null,
  "session": {
    "id": "uuid",
    "phase": "focus",
    "runState": "idle",
    "remainingMillis": 1500000,
    "deadlineUtc": null,
    "completedFocusSessionIds": [],
    "completedRounds": 0
  }
}
```

- `taskId` 可空；保存任务时任务排序只由数组顺序决定。
- 设置范围：focus/short/long 1–180 分钟，透明度 0.70–1.00。
- 严格校验 title 长度和空白、任务 ID 唯一、番茄数非负；禁止 JSON 字段注入影响程序逻辑。
- 可利用 `schemaVersion` 执行一次性 GTK3→Flutter 迁移；用户已明确当前未对外发布，因此可以将存量数据迁移列为内部辅助工具，**不能为了兼容大幅增加正式架构复杂度**。
- 损坏 JSON 必须备份后恢复默认，不得崩溃或静默清空旧文件。

## 7. 测试与验收矩阵

| 阶段 | 测试 | 必须通过 |
| --- | --- | --- |
| 静态检查 | `flutter analyze`、格式检查 | 0 errors，0 新增 warnings |
| 领域测试 | 计时、暂停、恢复、睡眠、完成幂等、自由专注 | 100% P0 |
| 控件测试 | 中央单击启停、图标、任务抽屉、设置 | 100% P0 |
| 单窗测试 | 启动时窗口数、模式切换、无叠窗 | 100% |
| Linux 构建 | Ubuntu 22.04 release build | 成功 |
| 图形测试 | Xvfb 真实窗口、完整/迷你/抽屉 | 无黑边/双计时/裁切 |
| 实机测试 | GNOME X11/Wayland | 行为符合能力矩阵 |
| 跨平台 | Windows/macOS 稳定版构建及基本操作 | 正式跨平台发布前必须通过 |
| 可靠性 | 反复启停 100 次、切换 200 次、50 任务滚动 | 0 崩溃、0 错计数 |
| 数据 | 断电/异常退出模拟、本地读写 | 不丢已完成的确认记录 |
| 可访问性 | 125/150/200% 缩放、Tab/Space、焦点、对比度 | 不裁切，可键盘操作 |

### 量化非功能门槛（首发目标，需实测，不提前宣称达成）

- 普通电脑冷启动主表盘可交互：目标 ≤ 2 秒；以 Ubuntu 真机基准和多次采样确定最终阈值。
- 单击主表盘到状态反馈：P95 ≤ 100ms。
- 秒数显示相对真实时间漂移：60 分钟连续运行 ≤ 1 秒。
- 一次轮次完成只增加一次计数，通知重复率为 0。
- 静置 10 分钟空闲 CPU 使用率：目标 ≤ 1%，实际按电脑和刷新率分档。
- Release 包体和常驻内存不硬套 GTK 数值，先测 Flutter 基线再制定合理预算。
- 50 项任务抽屉交互流畅，无超过 200ms 的持续主线程卡顿。

## 8. 研发拆解与交付物

### M0｜技术可行性门（必须先通过）
- 建立 `flutter_app/` 独立源码树，生成 Linux/Windows/macOS Runner。
- 最小完整表盘可构建、Linux 真实启动、支持透明/降级。
- 验证 Flutter 单一主窗口的 `setAlwaysOnTop` 在 GNOME X11、Wayland 下的真实边界。
- **决策关口**：若稳定版窗口插件无法满足硬性单窗与迷你尺寸，必须提交证据进行架构复评，而不是用第二个窗口偷偷实现。

### M1｜核心计时模型
- 实现纯 Dart 领域模型、无任务开始、暂停/继续、休息、完成幂等。
- 单元测试覆盖结束边界、零任务、重新启动、数据损坏和系统时间跳变。

### M2｜正式视觉
- Flutter 自绘 Crystal Timepiece，中央点击、环形进度、四个辅助图标。
- 完整/迷你尺寸切换和窗口拖动；消除叠窗根因。
- 在复杂桌面背景下提供透明及不透明两组视觉回归图。

### M3｜管理体验
- 迁移 V1.1 任务行为到 Dart，窗口内展开任务抽屉，Ctrl+F、键盘排序、撤销。
- 在不启动第二顶层窗口的前提下支持高 DPI、长任务名和 50 项任务。

### M4｜设置与可靠性
- 透明度、置顶、时间配置、模式与窗口位置持久化。
- 挂起/恢复、异常退出、单实例、系统托盘（仅确认必要性后）。
- 做好可访问性、通知、无网络运行。

### M5｜发布准备
- GitHub Actions：Linux 测试/构建，Windows/macOS 构建。
- Linux 正式安装包和卸载流程，明确用户数据保留策略。
- README 改为新架构，并保留 GTK3 源码回退分支/标签至 V2 验收结束。
- 真实平台人工验收、录屏、CI 证据汇总，**所有阻断项清零才合并或发布正式默认入口**。

## 9. 质量责任与禁止事项

- 不允许以 Flutter widget test 代替 OS 窗口置顶测试。
- 不允许以“调用 `setAlwaysOnTop(true)` 没报错”宣称 Wayland 真置顶。
- 不允许以设计图替代运行中截图，不允许以源码目录存在宣称 Linux 原生包已构建。
- 不允许构建失败时默默回退旧 GTK 再向用户说“迁移成功”。
- 不允许替换 README 后仍用旧 GTK 安装脚本宣传为 Flutter 正式产品。
- 合并正式主分支的门槛是：M0–M4 功能达标、必选系统平台测过、回归与截图可追溯。
- 遇到功能与质量冲突，**先保留可靠的现有 V1.1，不能为了视觉升级牺牲用户正常使用**。

## 10. 当前实施约定

先把本技术文档与 PRD 定为 Git 中正式产品基线。Flutter 实施沿独立分支进行，现有 GTK3 产品维持可用，直到新平台正式构建、集成、实机验收结束。

发布前决策严格以通过的测试证据为准，而不是以研发自评或界面精致程度为准。
