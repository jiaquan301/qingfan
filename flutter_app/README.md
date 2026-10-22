# 青番 Flutter V3｜三平台候选工程

普通用户的安装、使用和卸载请阅读 [根目录 README](../README.md)；严格的交互与计时行为详见 [V3 产品与验收基线](../docs/v3-product-and-acceptance.md)。

本工程基于 Flutter 3.47.0 / Dart，`window_manager 0.5.2`，采用**一个原生窗口、一个直径 104px 的表盘、专注与休息两个阶段**。PR #4 尚未合并；Windows/macOS 候选包尚未签名/公证。

## Ubuntu 22.04/24.04 源码编译

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

生成 `dist/qingfan_3.0.0~dev1_amd64.deb`；安装和卸载参见根目录 README。

## Windows 10/11 x64 源码编译

要求 Flutter、Visual Studio C++ 桌面开发工具链。

```powershell
cd flutter_app
flutter create --no-pub --project-name qingfan --platforms=windows .
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

`build/windows/x64/runner/Release/qingfan.exe` 必须连同 DLL 与 `data` 资源文件夹一起部署。CI 另使用 `tool/qingfan_windows.iss` 打包测试版 Inno Setup 安装器。

## macOS 源码编译

要求 Flutter、Xcode 与 CocoaPods。

```bash
cd flutter_app
flutter create --no-pub --project-name qingfan --platforms=macos .
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

生成 `build/macos/Build/Products/Release/qingfan.app`。CI 通过 `hdiutil` 创建/验证 unsigned DMG。

## 验收

- 表盘绘制恒为 104px。Ubuntu/macOS 独立原生窗口为 104×104，Windows 可能为 136×104 的透明容器；展开面板为 522×510，其中表盘依旧只占 104px。
- 保持数字和环形进度是唯一常态绘制；通用媒体图标只在悬停专注表盘时出现。无任务名、阶段标签、大/小切换、四轮指示器、专用跳过休息按钮。
- 专注完成立即进入自动休息；休息不能暂停；休息完成停在下一轮待开始；任务面板“开始专注”可以提前结束休息但选择任务不能。
- V2 状态文件 `qingfan_v2.json` 向后兼容：`shortBreakMinutes` 自动映射 `restMinutes`；保留选中任务、已完成次数等。
- X11 原生验收使用 `tool/native_smoke.sh`，Windows、macOS 通过对应 `native_smoke_*.ps1/.sh`。三平台发布构建在 [Flutter CI](https://github.com/jiaquan301/qingfan/actions/workflows/flutter-v2.yml)。

结构：`lib/domain` 负责计时状态机，`lib/application` 负责任务与状态，`lib/infrastructure` 负责本地持久化及窗口，`lib/presentation` 负责绘制。旧 GTK3 版保持在项目根目录，PR 完成评审前不替换 main。
