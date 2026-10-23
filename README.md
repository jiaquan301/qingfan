# 青番 Qingfan

**一枚安静的桌面专注时钟。** 只有专注与休息两个阶段、一个直径 **104 逻辑像素**的圆形表盘，日常只显示倒计时与进度环。无账号、无云服务，任务和设置保存在本机。

> **V3 测试候选版**：目标平台仅为 **Ubuntu 22.04（x86-64）和 macOS**。代码位于 [PR #4](https://github.com/jiaquan301/qingfan/pull/4)，尚未合并主分支。Windows 不属于本轮构建、发布或验收范围。原有 Ubuntu GTK3 V1.1 仍留在主分支，本页介绍 Flutter V3。

## 1. 安装

从 [青番 V3 的 GitHub Actions 构建记录](https://github.com/jiaquan301/qingfan/actions/workflows/flutter-v2.yml) 打开 **PR #4 对应的最新成功构建**，在 Artifacts 下载对应附件，先解压附件中的文件。GitHub 可能要求登录才能下载 Actions 附件。

| 平台 | 构建附件 | 安装程序 |
| --- | --- | --- |
| Ubuntu 22.04 x86-64 | `qingfan-v3-ubuntu-deb` | `qingfan_3.0.0~dev1_amd64.deb` |
| macOS | `qingfan-v3-macos-app-unsigned` | `qingfan-v3-macos-unsigned.dmg`（或 `.app` ZIP） |

### Ubuntu 22.04

进入解压出的 DEB 所在目录，在终端执行：

```bash
sudo apt install ./qingfan_3.0.0~dev1_amd64.deb
```

随后从系统应用程序菜单搜索 **青番**，或者执行：

```bash
/usr/lib/qingfan/qingfan
```

V3 DEB 使用 Flutter 桌面原生程序，无需单独安装 Python 运行依赖。升级时先备份任务数据，再安装新生成的 DEB。若旧版 GTK3 V1.1 仍在应用菜单中，建议按第 4 节卸载旧版，以免混淆程序入口。

### macOS

下载并解压 `qingfan-v3-macos-app-unsigned`，打开 `.dmg`，将其中的 `qingfan.app` 拷贝到 **应用程序（Applications）** 文件夹，然后启动。也可以解压附带的 `.app` ZIP 并将应用移动到“应用程序”。

该版本**尚未经过 Apple 开发者签名与公证**。macOS 可能阻止首次启动；请确认来源确为上述 GitHub Actions 产物后，按系统提供的“系统设置 → 隐私与安全性”路径批准。不要为此全局关闭系统安全保护。CI 构建通过不代表已覆盖所有 Intel/Apple Silicon 实机和 macOS 版本。

## 2. 使用

- **单一时钟**：始终保持 104 逻辑像素直径，常态只有 `MM:SS` 和环形进度；**不显示任务名、专注/休息文字或轮次圆点**，没有大/小表盘切换。
- **专注**：默认 25 分钟。点击倒计时数字开始、暂停、继续；鼠标悬停时出现通用的 <播放 / 暂停> 图标及任务清单、更多入口，移开后自动隐藏图标。
- **休息**：专注完成后自动开始 5 分钟休息。休息**不能暂停**；时间结束后自动进入下一轮专注的待开始状态，需手动点击播放才开始计时。
- **新任务**：打开任务清单，选择任务，点击 **开始专注**。如果正在休息，会自动结束休息并开始一轮完整专注；**只选择任务不会中断休息**。也支持无任务的自由专注。
- **任务管理**：新增、选择、完成/恢复、搜索、排序、重命名、删除及撤销；完整完成的一轮才增加当前任务的番茄次数。专注进行时切换当前任务需要先暂停并按提示确认。
- **窗口和设置**：按住表盘外圈拖动窗口。更多菜单仅有偏好设置、专注阶段的“重新开始本轮”、始终置顶切换；不存在独立的跳过休息操作。设置仅调整专注时间、休息时间、透明度，自动保存；当前运行或暂停中的计时与进度环不会因为修改设置而跳变。

| 快捷键 | 行为 |
| --- | --- |
| `Space`（不在文本输入框中） | 专注开始 / 暂停 / 继续；休息期间无操作 |
| Ubuntu：`Ctrl+L` / `Ctrl+F` | 打开任务清单 |
| macOS：`Command+L` / `Command+F` | 打开任务清单 |
| `Esc` | 退出文本编辑焦点或关闭任务面板 |

**应用重启规则**：未完成专注恢复剩余时间并暂停；退出时处于休息则回到完整专注待开始。原任务、已完成番茄数和设置保留。V2 的短休息设置会迁移为 V3 的统一休息时间。

## 3. 卸载与数据保留

### Ubuntu V3

```bash
sudo apt remove qingfan
```

### macOS

先退出青番，再将“应用程序”中的 `qingfan.app` 移到废纸篓；已下载的 DMG/ZIP 可一并删除。

**程序卸载不会自动清空用户数据。** Flutter V3 继续使用 V2 的数据文件 `qingfan_v2.json` 以保留原任务和已完成轮次；具体目录由系统应用支持路径决定。Ubuntu 可通过以下命令查找以便备份：

```bash
find "${XDG_DATA_HOME:-$HOME/.local/share}" -type f -name qingfan_v2.json 2>/dev/null
```

macOS 可在用户的 `~/Library/Application Support/` 下查找 `qingfan_v2.json`。清除历史任务属于**单独的手动数据操作**，不属于正常卸载步骤。

## 4. 旧版 GTK3 与开发

仓库根目录的 `./install.sh`、`./run.sh`、`./uninstall.sh` 仅服务旧版 **Ubuntu GTK3 V1.1**，不用于安装或卸载 Flutter V3。需要移除旧版时，在旧版源码目录执行 `./uninstall.sh`；其任务数据通常保存在 `~/.local/share/qingfan/state.json`，与 V3 不同。

- [V3 产品逻辑及验收基线](docs/v3-product-and-acceptance.md)
- [Flutter V3 源码编译和测试](flutter_app/README.md)
- [Ubuntu 22.04 / macOS CI](https://github.com/jiaquan301/qingfan/actions/workflows/flutter-v2.yml)
- [开发 PR #4](https://github.com/jiaquan301/qingfan/pull/4)

只有对应提交的全部 CI 步骤通过，才能称为自动化候选验收通过；实际桌面环境、不同缩放及 macOS 分发签名仍需单独验证。
