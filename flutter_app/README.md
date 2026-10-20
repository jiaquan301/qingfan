# 青番 V2 · Flutter Desktop

**状态：跨平台候选版，正式 GTK3 V1.1 入口尚未被替换。** 本版本以 Flutter 3.47.0 + Dart + `window_manager 0.5.2` 实现一个原生窗口的完整时钟、迷你时钟、任务抽屉和设置界面。

- [正式产品需求](../docs/v2-product-prd.md)
- [技术架构和验收标准](../docs/v2-engineering-acceptance.md)
- [自动化构建与验收记录](https://github.com/jiaquan301/qingfan/actions/workflows/flutter-v2.yml)

## 启动与交互

打开即显示晶透主表盘，不要求预先添加任务；点击表盘中央开始、暂停或继续，点击图标查看任务、设置、缩小、重置。

任务清单支持新增、选择当前任务、完成/恢复、重命名、删除、7 秒撤销、拖动及 Alt+方向键排序、搜索和 50 项以上内部滚动。专注进行中不允许直接切换或完成当前任务；暂停且已产生进度时需确认放弃未完成的本轮。专注完成次数独立于任务完成状态。

置顶、窗口大小和背景透明度由原生适配层管理；Wayland 不保证窗口管理器会执行强制置顶请求，不允许将已发送请求理解为已实际置顶。

## 一、Ubuntu 22.04/24.04

**建议先从对应提交的 GitHub Actions 中下载 `qingfan-v2-ubuntu-deb` 候选包。** 尚未签名或宣告正式发布，只适合开发测试环境。

安装：

```bash
sudo apt install ./qingfan_2.0.0~dev1_amd64.deb
qingfan
```

也可从应用程序菜单打开“青番”。如系统未将 `/usr/lib/qingfan` 加入 PATH，请从应用菜单打开，或使用 `/usr/lib/qingfan/qingfan` 直接执行。

卸载：

```bash
sudo apt remove qingfan
```

用户数据位于操作系统为应用提供的本地应用支持目录，卸载不会主动删除个人任务数据。安装包依赖 `fonts-noto-cjk`，确保干净的 Ubuntu 安装也能正确显示中文。

### Linux 源码构建

按 [Flutter Linux 官方文档](https://docs.flutter.dev/platform-integration/linux/setup) 安装 Flutter SDK。CI 固定 Flutter 3.47.0，开发机应尽量使用相同版本：

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
cd flutter_app
flutter create --no-pub --project-name qingfan --platforms=linux .
python3 tool/patch_linux_runner.py
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

用 `flutter build linux --release` 编译发布版，然后用 `bash tool/package_linux.sh` 生成 Debian 安装包。

**重要**：Flutter 3.47 的默认 Linux Runner 使用 1280×720 初始窗口。项目有校验过模板锚点的 Runner 修补脚本，必须执行，避免原生窗口拒绝缩至 104×104。将来升级 Flutter SDK 时必须重新验证补丁并重新验收实际窗口尺寸。

## 二、Windows 10/11 x64

在对应 CI 中下载 `qingfan-v2-windows-installer`（测试版安装程序）或 `qingfan-v2-windows-portable`（便携压缩包）。安装程序由 Inno Setup 配置 `tool/qingfan_windows.iss` 生成，支持开始菜单、可选桌面快捷方式和正常卸载。

源码构建（Windows + Visual Studio Desktop development with C++ + Flutter）：

```powershell
cd flutter_app
flutter create --no-pub --project-name qingfan --platforms=windows .
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

Windows CI 固定压缩 `build/windows/x64/runner/Release` 完整目录，而不单独分发 EXE；EXE 必须与 Flutter DLL 及资源文件保持一起。开发候选安装包尚未进行 Authenticode 代码签名。

## 三、macOS

下载 CI 的 `qingfan-v2-macos-app-unsigned`，其中有未签名的 `.dmg` 和 `.app` ZIP，**用于开发评测，不作为对外公开发行物**。正式发行仍需开发者证书签名与 Apple 公证。

源码构建（Xcode、CocoaPods 和 Flutter）：

```bash
cd flutter_app
flutter create --no-pub --project-name qingfan --platforms=macos .
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

CI 构建的 `.app` 放于 `build/macos/Build/Products/Release/`。当前构建目标为 CI 所用 macOS Runner，通用 Intel/Apple Silicon 分发需进一步确认并按各架构验收。

## 四、测试与发布门槛

运行 `flutter analyze`、`flutter test`。Linux 自动验收使用 Xvfb、Openbox 和真正的 Flutter Release Runner，验证：

- 376×408 主表盘、104×104 迷你、768×540 任务管理及返回窗口尺寸；
- 始终只有一个顶层窗口、重复启动的进程互斥；
- X11 置顶报告与真实窗口尺寸；
- 五种窗口形态的截图是否空白；截图保存在 CI 附件中；
- Debian 包的安装、桌面入口和正常卸载。

Windows/macOS CI 分别真实编译 Release 和安装候选制品，但无 GUI 真机测试时**不能宣称已完成用户桌面验收**。Ubuntu GNOME/X11、Wayland 与高 DPI/多显示器真实场景仍需手工按验收清单测试。

## 五、架构与发布原则

`lib/domain` 包含与 GUI 解耦的计时逻辑，`lib/application` 管理任务与界面状态，`lib/infrastructure` 统一窗口、单例和本地存储，`lib/presentation` 只包含 Flutter 界面。

Flutter V2 作为正式技术路线维护，但 GTK3 V1.1 在 V2 的 P0 阻断项清零前维持稳定发布入口。不能以构建或 Xvfb 截图代替 Wayland 原生置顶与三个操作系统的真实桌面验收。
