# 青番 Qingfan

**一个安静的桌面专注时钟。** 一个直径 104 像素的圆形倒计时表盘，只有**专注**与**休息**两个阶段，无需账号或云服务。常态只显示时间与进度环。

> **版本状态**：Flutter V3 正在 [PR #4](https://github.com/jiaquan301/qingfan/pull/4) 验收，尚未合并到 main。原有 Ubuntu GTK3 V1.1 仍为 main 的旧版本；以下 V3 安装方式适用于 PR 构建产物。Windows 安装包尚未签名，macOS 包尚未签名、公证。

## 一、安装

打开 [GitHub Actions：Flutter 跨平台候选构建](https://github.com/jiaquan301/qingfan/actions/workflows/flutter-v2.yml)，选择 **最新成功的 PR #4 构建**，从 Artifacts 下载对应平台压缩包并先解压。

| 系统 | 构建附件 | 安装方式 |
| --- | --- | --- |
| Ubuntu 22.04/24.04 x86-64 | `qingfan-v2-ubuntu-deb` | 解压后在 DEB 所在目录执行 `sudo apt install ./qingfan_2.0.0~dev4_amd64.deb` |
| Windows 10/11 x64 | `qingfan-v2-windows-installer` | 解压后双击 `qingfan-v2-windows-x64-installer-unsigned.exe`，按向导安装 |
| Windows 10/11 x64 便携版 | `qingfan-v2-windows-portable` | 完整解压后运行 `qingfan.exe`；不能只复制 EXE |
| macOS 候选版 | `qingfan-v2-macos-app-unsigned` | 解压并打开 DMG，将 `qingfan.app` 复制到“应用程序” |

安装完成后在系统应用菜单搜索“青番”。Ubuntu 也可用 `/usr/lib/qingfan/qingfan` 启动。

未签名的 Windows/macOS 测试包可能触发系统安全警告，必须确认来自上述 GitHub 构建；不要关闭系统安全保护。macOS Intel/Apple Silicon 全架构与真实设备兼容仍须独立验收。

## 二、使用

- **时钟表盘**：始终固定直径 104 逻辑像素，没有大小模式；常态仅显示 `MM:SS` 与进度环。
- **专注**：初始 25 分钟，点击时间数字开始；点击暂停、再次点击继续。鼠标悬停时显示通用的播放或暂停图标。移开鼠标后隐藏控件。
- **休息**：专注完成后自动运行 5 分钟休息，期间**不可暂停**。休息结束后自动回到新一轮 25 分钟专注，但不会自动开始，需人工点击播放。
- **开始新任务**：打开任务清单，选择任务并点击“开始专注”。如果正在休息，系统自动结束休息并启动新的完整专注；**仅选择任务不会中断休息**。未选择任务时也可自由专注。
- **任务管理**：支持新增、选择、完成/恢复、重命名、删除、搜索、排序、短时撤销与已完成番茄数统计。正在运行的专注不能直接切换当前任务。
- **其他操作**：悬停表盘查看清单/更多入口；在圆环空白处拖动窗口。“更多”菜单可打开偏好设置、切换始终置顶；专注阶段可重置本轮。不存在独立跳过休息操作。
- **偏好设置**：只设置专注时长、休息时长与透明度，自动保存。
- **快捷键**：Windows/Ubuntu `Ctrl+L` 或 `Ctrl+F`、macOS `Command+L` 或 `Command+F` 打开清单；非输入状态 `Space` 控制专注的播放/暂停；`Esc` 返回时钟或取消编辑焦点。

退出重启后，未完成专注以**暂停**方式恢复剩余时间；休息阶段则回到全新专注待开始。原来的任务、轮次和设置继续保留。V2 的短休息时长自动迁移为统一休息时长，不丢失已有数据。

## 三、卸载

| 平台 | 卸载步骤 |
| --- | --- |
| Ubuntu V3（DEB） | `sudo apt remove qingfan` |
| Windows 安装版 | **设置 → 应用 → 已安装的应用 → 青番 → 卸载** |
| Windows 便携版 | 退出青番，删除完整的便携版文件夹 |
| macOS | 退出青番，将“应用程序”内的 `qingfan.app` 移至废纸篓 |
| Ubuntu 旧 GTK3 V1.1 | 在原源码仓库根目录执行 `./uninstall.sh` |

**默认卸载只移除程序，不删除用户任务数据。** Flutter 版本的数据文件名为 `qingfan_v2.json`（延续 V2 文件名以保留历史任务），位置由系统应用支持目录确定。Ubuntu 可以通过 `find "${XDG_DATA_HOME:-$HOME/.local/share}" -type f -name qingfan_v2.json 2>/dev/null` 查找和备份。旧 GTK3 数据在 `~/.local/share/qingfan/state.json`，属于独立格式。

## 四、旧版 Ubuntu GTK3 V1.1

仓库根目录的 `./install.sh`、`./run.sh`、`./uninstall.sh` **只服务旧 GTK3 版**。运行这些脚本不会安装或卸载 Flutter V3。使用新的 V3 时不要混淆两种程序入口。

## 五、开发与验收

- [V3 完整行为与验收基线](docs/v3-product-and-acceptance.md)
- [Flutter 工程与三平台源码构建](flutter_app/README.md)
- [跨平台 CI](https://github.com/jiaquan301/qingfan/actions/workflows/flutter-v2.yml)
- [PR #4](https://github.com/jiaquan301/qingfan/pull/4)

CI 通过表示对应提交的自动化构建与规定的原生窗口/安装测试通过，不代表所有物理设备及桌面组合已经人工验收。
