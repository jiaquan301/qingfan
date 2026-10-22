# 青番 V2｜Flutter 跨平台桌面版

本目录是 **Flutter V2 的开发工程**（Flutter 3.47.0，Dart，`window_manager 0.5.2`）。面向普通用户的下载、**Ubuntu / Windows / macOS 安装、使用和卸载步骤统一在 [仓库根目录 README](../README.md)**。

> **状态**：PR #4 的测试候选版；尚未合并 `main`。2026-10-22 提交 `59c29f2` 的 [三平台 CI](https://github.com/jiaquan301/qingfan/actions/runs/39745725008) 已通过。macOS 包未签名/公证，Windows 包未签名，尚待真实设备最终验收。

## 使用 V2

- 启动时显示完整悬浮表盘，无需先建任务；点击中央开始、暂停、继续专注。
- 表盘“任务清单”可新增、选择、完成/恢复、重命名、删除、搜索和排序任务；完成/删除可在提示有效期内撤销。
- 在短/长休息阶段，完整表盘、迷你表盘、更多菜单以及任务清单都有跳过休息、直接开始专注的入口。**重新开始本轮**在休息期间会返回新的专注阶段。
- 应用退出后重新进入：进行中的专注作为暂停状态恢复剩余时间；未完成休息恢复为全新专注；已完成番茄次数、任务和设置保留。
- 在表盘外圈空白处按住并移动可拖动窗口；按住并移动才触发拖动。设置会自动保存；“始终置顶”只在表盘的“更多”菜单。
- Windows/Linux `Ctrl+L` 或 `Ctrl+F`、macOS `Command+L` 或 `Command+F` 打开任务清单；非输入状态下 `Space` 切换计时，`Esc` 收起面板或退出编辑焦点。

默认专注 25 分钟、短休息 5 分钟、长休息 15 分钟；所有时长可在设置中调整。只对**真正完成的专注轮次**记一次番茄数，休息跳过/重置不增加次数。

## 安装、升级与卸载速查

| 平台 | 候选安装包 | 启动 | 卸载 |
| --- | --- | --- | --- |
| Ubuntu 22.04 / 24.04 x86-64 | [DEB](https://github.com/jiaquan301/qingfan/actions/runs/39745725008/artifacts/12411307813)：`sudo apt install ./qingfan_2.0.0~dev4_amd64.deb`（在 DEB 所在目录执行） | 应用菜单“青番”或 `/usr/lib/qingfan/qingfan` | `sudo apt remove qingfan` |
| Windows 10/11 x64 | [安装 EXE](https://github.com/jiaquan301/qingfan/actions/runs/39745725008/artifacts/12410798248) 或 [便携 ZIP](https://github.com/jiaquan301/qingfan/actions/runs/39745725008/artifacts/12411935146) | 开始菜单；便携版解压后运行 `qingfan.exe`（保留整个目录） | 系统“已安装的应用”卸载；便携版删除解压目录 |
| macOS（CI 候选版） | [DMG / APP ZIP](https://github.com/jiaquan301/qingfan/actions/runs/39745725008/artifacts/12411696796)，将 APP 拷贝至“应用程序” | “应用程序”中的青番；首次打开可能需在系统隐私与安全性中批准可信包 | 退出后删除“应用程序”内 `qingfan.app` |

以上链接下载的是 GitHub Actions Artifacts，**需先解压**。默认卸载保留本地数据；V2 文件名为 `qingfan_v2.json`，具体位置取决于系统应用支持目录。旧版 GTK3 V1.1 使用根目录 `./install.sh` 与 `./uninstall.sh`，它们**不会安装或卸载 Flutter V2**。

## 源码构建与验证

### Ubuntu 22.04 / 24.04

安装 Flutter 3.47.0 及 Linux 桌面构建依赖（示例）：

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

编译生成 `build/linux/x64/release/bundle/`，打包生成 `dist/qingfan_2.0.0~dev4_amd64.deb`。Linux Runner 补丁用于在 Flutter 默认窗口几何参数之外正确创建小尺寸无边框窗口，**升级 Flutter 时必须重新审核并测试该补丁**。

### Windows 10/11 x64

需要 Flutter SDK、Visual Studio 的 Desktop development with C++ 工作负载：

```powershell
cd flutter_app
flutter create --no-pub --project-name qingfan --platforms=windows .
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

可执行文件位于 `build/windows/x64/runner/Release/qingfan.exe`。发布时必须连同该目录中的 DLL、`data` 等资源一起打包。CI 使用 `tool/qingfan_windows.iss` 和 Inno Setup 构建 unsigned EXE；原生窗口测试在 `tool/native_smoke_windows.ps1`。

### macOS

需要 Flutter SDK、Xcode 与适用的 CocoaPods 环境：

```bash
cd flutter_app
flutter create --no-pub --project-name qingfan --platforms=macos .
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

APP 位于 `build/macos/Build/Products/Release/qingfan.app`，原生测试脚本为 `tool/native_smoke_macos.sh`；CI 使用 `hdiutil` 生成并验证未签名 DMG。正式分发须另行处理 macOS 签名、公证和目标架构。

## 验收范围与技术约束

当前实际窗口尺寸：主表盘 **376 × 408**、Ubuntu/macOS 迷你时钟 **104 × 104**、Windows 迷你窗 **136 × 104**（Win32 最小顶层窗口宽度限制）、展开任务/设置工作区 **714 × 510**，单位为逻辑像素。

[CI #39745725008](https://github.com/jiaquan301/qingfan/actions/runs/39745725008) 已在 Ubuntu、Windows、macOS 运行 `flutter analyze`、`flutter test`、Release 构建与原生窗口验收，并分别验证 DEB 安装/启动/卸载、Windows 安装器安装/启动/卸载、macOS DMG 挂载/内容检查/卸载。新增的休息阶段回归测试涵盖中途跳过、旧休息时间清理、任务切换、表盘入口、阶段自然到时的刷新与持久化。

**未覆盖**所有用户物理设备、Wayland 合成器、外接显示器与各档系统缩放。Wayland 对强制置顶、拖动和透明绘制可能施加桌面环境限制。Linux 运行时透明边缘仍需图形合成环境支持。

架构：`lib/domain/` 维护计时状态机；`lib/application/` 维护任务与界面状态；`lib/infrastructure/` 负责本地存储、单例锁和系统窗口；`lib/presentation/` 实现 Flutter 界面。旧 GTK3 版本仍保留作为回退基线。

更多资料：[产品需求](../docs/v2-product-prd.md) · [技术验收规范](../docs/v2-engineering-acceptance.md) · [PR #4](https://github.com/jiaquan301/qingfan/pull/4)
