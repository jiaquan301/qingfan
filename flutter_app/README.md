# 青番 V2 · Flutter Desktop 开发版

此目录是 **Flutter 稳定版桌面迁移工程**，与当前可用的 GTK3 青番 V1.1 并行。**目前尚未宣称已通过正式 Linux/Windows/macOS 实机验收。**

阅读正式需求：

- [产品需求与视觉交互规范](../docs/v2-product-prd.md)
- [技术架构与研发验收标准](../docs/v2-engineering-acceptance.md)

## 技术栈

Flutter 3.47.0（CI 固定）、Dart、`window_manager 0.5.2`、`path_provider`、Flutter 自带绘制和测试工具。主界面为 **单一原生窗口**，通过自身尺寸和内容切换完整/迷你/任务/设置，不允许重复生成叠加顶层窗口。

## Ubuntu 22.04 首次构建

先按照 [Flutter Linux 桌面安装文档](https://docs.flutter.dev/platform-integration/linux/setup) 安装 Flutter SDK。然后：

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev

cd flutter_app
flutter --version
flutter create --no-pub --project-name qingfan --platforms=linux,windows,macos .
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

发布包预构建：`flutter build linux --release`。当前由 GitHub Actions 自动构建候选包，并保留构建日志。

注意：`flutter create` 只用于一次性生成目标平台 Runner。架构评审通过后须将正式 Runner（Linux、Windows、macOS）固定提交到仓库，而不能把临时生成项目当作最后交付。

## 关键产品操作

- 打开默认直接显示表盘，**无需任务**即可点击中央开始/暂停。
- 任务、设置、重置、迷你四个图标沿表盘外缘布置。
- 迷你切换应确实改变原生窗口的像素尺寸，不新建窗口。
- 任务面板在同一原生窗口内展开，保留 V1.1 任务操作语义。
- 全局置顶申请由 `DesktopWindowBridge` 独立负责；Wayland 可能拒绝强制置顶。
- 本地 JSON 保存，不依赖网络。

## 开发约束

- **不能**依赖 Flutter experimental windowing main-channel API。
- **不能**以 Widget 测试通过代替 GTK/X11/Wayland 真实置顶验证。
- **不能**直接合并替换旧版 GTK3：只有 CI、原生构建、真实窗口截图与 Ubuntu 桌面验收通过，才允许切换正式启动入口。
