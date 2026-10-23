# 青番 V3｜Flutter 桌面工程

本轮**只开发和验收 Ubuntu 22.04、macOS**。面向普通用户的安装、使用和卸载说明见 [根目录 README](../README.md)，产品规格见 [V3 行为和验收基线](../docs/v3-product-and-acceptance.md)。

实现：Flutter 3.47.0、Dart、`window_manager 0.5.2`；**一个原生窗口、一个 104 逻辑像素圆形表盘、专注/休息两个阶段**。项目处于 [PR #4](https://github.com/jiaquan301/qingfan/pull/4) Draft 候选阶段，未合并主分支。

## Ubuntu 22.04 源码构建

先安装 [Flutter Linux 桌面 SDK](https://docs.flutter.dev/platform-integration/linux/setup)，再执行：

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
cd flutter_app
flutter create --no-pub --project-name qingfan --platforms=linux .
python3 tool/patch_linux_runner.py
flutter pub get
flutter analyze
flutter test
flutter build linux --release
bash tool/package_linux.sh
```

正式包路径为 `dist/qingfan_3.0.0~dev1_amd64.deb`，安装和卸载命令见根 README。原生 GUI 验收入口为 `tool/native_smoke.sh`，使用实际 X11 窗口（Xvfb + Openbox + 合成器），而不只运行 widget tests。

> Flutter 默认 Linux runner 的窗口参数对 104×104 无边框窗口有限制；升级 Flutter 时必须重新审核 `tool/patch_linux_runner.py` 的补丁，并复测原生窗口。

## macOS 源码构建

安装 Flutter、Xcode，以及当前插件所需的 CocoaPods 环境：

```bash
cd flutter_app
flutter create --no-pub --project-name qingfan --platforms=macos .
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

APP：`build/macos/Build/Products/Release/qingfan.app`。原生窗口验收脚本：`tool/native_smoke_macos.sh`。CI 还会创建未签名 DMG，完成挂载、内容检查和卸载。正式公开分发前仍需 Apple 签名与公证。

## 行为、数据和验收约束

- **单表盘**：任何界面和缩放比例下，圆形表盘直径固定 104 逻辑像素；主时钟原生窗口为 104×104。常态只显示时间与进度环，悬停才显示任务、更多及标准播放/暂停图标。
- **计时状态机**：专注可暂停/恢复，专注结束自动开始不可暂停的休息，休息结束自动停在下一轮专注待开始；休息期间任务清单的“开始专注”会启动新专注，单纯选择/删除任务不会改变休息进度。
- **设置**：仅两个时长和透明度；用户正在进行的一轮使用锁定的时长和圆环进度基准，修改配置从下一轮生效。
- **数据兼容**：继续使用 `qingfan_v2.json`，旧 `shortBreakMinutes` 转换成新的 `restMinutes`；退出休息后重新打开为全新专注待开始。暂停专注保留剩余时长及进度基准。
- **原生交付证据**：Ubuntu 分析、全量 Flutter 测试、X11 窗口截图、DEB 安装/启动/卸载；macOS 分析、全量测试、真实 WindowServer 窗口检查、APP 和 DMG 验证。
- **物理设备边界**：Ubuntu Wayland、实际 GNOME 环境、macOS 架构/显示器缩放、系统权限及未公证应用的首次启动需要后续实机验证，不能以云端 CI 代替。

[双平台 CI 工作流](https://github.com/jiaquan301/qingfan/actions/workflows/flutter-v2.yml) · [实施计划](../docs/superpowers/plans/2026-10-23-qingfan-v3-ubuntu-macos.md)
