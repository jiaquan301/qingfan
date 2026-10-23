# 青番 V3.0 双平台完善实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 按已确认 V3 需求交付单一 104 像素圆形专注钟，范围限定 Ubuntu 22.04 和 macOS，修复审查发现的行为缺口并建立可复查证据。

**Architecture:** 保留现有 Flutter 状态机/控制器/窗口适配分层，基于已合入 PR #4 分支的 V3 代码做最小修正；使用纯时钟测试与 UI 测试验证行为；仅以 Ubuntu 22.04、macOS 自动化安装包测试作为发布门槛。

**Tech Stack:** Flutter 3.47.0, Dart, window_manager 0.5.2, GitHub Actions ubuntu-22.04/macOS-15.

**Spec:** docs/v3-product-and-acceptance.md；用户补充最新约束：仅 Ubuntu 22.04、macOS。

## Global Constraints

- 只有专注和休息两阶段，无短/长休息；休息自动运行且不能暂停；结束后进入待开始专注。
- 单一可见 104 逻辑像素表盘，常态仅 MM:SS + 进度环；悬停播放/暂停和清单/更多入口，无任务文字。
- 休息期间可以选择/整理任务；只有“开始专注”才中断休息并启动新的全时长专注。
- 设置仅专注时间、休息时间、透明度；时长更改不改变正在运行/暂停轮次的剩余时间或进度比例。
- V2 数据兼容、轮次不重复计数、PR #4 保持 Draft，不合并 main。

## Review Focus

- 休息正在运行时，对当前任务的删除与撤销必须正常生效，不应出现“请暂停专注”。
- 改变专注或休息配置时，正在运行轮次的数字和进度圆弧都不能跳变。
- 调整时长后退出重启，暂停专注的进度基线与剩余秒数仍一致。
- 在 Ubuntu/macOS 的原生 104px 表盘上，悬停控制不能遮挡数字或破坏拖动。
- 删除 Windows 构建门槛不意味着删除历史源文件，已有 V2 数据和旧版本使用说明仍可追溯。

---

### Task 1: 计时区间固定时长

**Files:** flutter_app/test/focus_engine_test.dart, flutter_app/lib/domain/focus_engine.dart

**Interfaces:** FocusEngine.phaseDurationMillis, configure({int? focus,int? rest}), toJson/restore(Map).

- [ ] 增加两种运行阶段的“变更配置不改变进度分母”失败用例，以及重启恢复暂停区间测试。
- [ ] 在现有状态机中锁定每轮实际时长；完成/重置/主动进入下一轮时才使用新配置，存储相应恢复信息。
- [ ] 检查新增测试由红转绿和原有全部状态机测试。

### Task 2: 休息期间任务操作

**Files:** flutter_app/test/focus_engine_test.dart, flutter_app/test/task_workflow_test.dart, flutter_app/lib/application/qingfan_controller.dart, flutter_app/lib/presentation/task_drawer.dart

- [ ] 增加休息中删除当前任务、不打断休息、撤销恢复的失败回归测试。
- [ ] 仅阻止正在专注时删除任务；休息期间按普通任务操作执行。
- [ ] 检查休息过程中选择、完成、重命名与开始新专注的路径。

### Task 3: 缩减平台与独立验收

**Files:** .github/workflows/flutter-v2.yml, docs/v3-product-and-acceptance.md, README.md, flutter_app/README.md, PR #4.

- [ ] 仅保留 Ubuntu 22.04 与 macOS 的正式工作流和产物；去除 Windows 验收门槛。
- [ ] 文档统一成两个目标平台，安装、使用、卸载和限制准确可操作。
- [ ] 在本轮提交上读取完整 flutter analyze/test、Ubuntu X11 / DEB、macOS 原生 / APP / DMG 工作流结论与产物。
- [ ] 更新 PR #4 事实记录，保留 Draft；明确 CI 与用户实机验收的区别。
