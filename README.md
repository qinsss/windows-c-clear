# C 盘清理助手

一个以“先解释、后决定”为核心的 Windows C 盘清理工具。

[下载最新版免安装程序](https://github.com/qinsss/windows-c-clear/releases/latest)（Windows 10/11）

它不会把整个 C 盘都当作可清理空间，而是先把数据分成两类：

- **系统级数据**：Windows、Program Files、ProgramData 等受保护位置。只展示说明，绝不提供删除按钮。
- **用户级数据**：用户临时文件、浏览器缓存、崩溃转储、开发工具缓存，以及 30 天以上的下载文件。每项都会说明用途和删除影响，由用户勾选后再操作。
- **AppData（应用数据）**：统计 `Local`、`LocalLow` 和 `Roaming` 下各应用/厂商目录。支持手动勾选清空，但会经过路径明细确认和第二次高风险确认；双击可先打开目录核对。
- **精确扫描模式**：点击“精确扫描 AppData”后在后台完整遍历，不受快速估算的文件数和时间限制。
- **扫描进度**：快速扫描在隐藏后台进程运行并持续显示 Loading；精确扫描显示真实百分比、目录计数和正在处理的位置。
- **扩展清理**：识别 DirectX、错误报告、缩略图、最近使用记录，以及常见开发工具的依赖/构建缓存。
- **Windows 系统清理项**：解释更新缓存、WinSxS、Windows.old、驱动、休眠文件、分页文件、还原点、回收站和 OneDrive 本地副本的正确处理方式。

## 运行

双击 `启动 C盘清理助手.cmd` 或 `Launch-WindowsCClear.vbs`。隐藏启动器会自动查找 Windows PowerShell 或 PowerShell 7，不依赖系统 `PATH`，并且不会保留命令行窗口。

也可以在 PowerShell 中直接运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\WindowsCClear.ps1
```

不需要管理员权限。建议使用普通用户身份运行，因为此工具本来就只处理当前用户的数据。

首次打开只加载界面，不会自动读取磁盘。点击“开始扫描”进行快速扫描，或点击“精确扫描 AppData”执行完整统计。

## 免安装版本

普通用户建议直接从 [Releases](https://github.com/qinsss/windows-c-clear/releases) 下载 `WindowsCClear-Portable.exe`，双击即可使用，无需安装。程序窗口和文件属性中的产品名称仍为“C盘清理助手”。

程序目前没有商业代码签名证书。Windows 首次运行时可能显示 SmartScreen 提示；请确认下载地址为本仓库，并可使用 Release 附带的 `SHA256SUMS.txt` 校验文件完整性。

仓库中可直接运行以下命令生成单文件免安装程序：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-portable.ps1
```

输出文件为 `dist\C盘清理助手.exe`。双击即可使用，无需安装；程序运行期间会在系统临时目录解压必要脚本，关闭后自动清理。

## 安全设计

- 常规候选由代码内的白名单和缓存目录特征识别；AppData 目录只有在用户明确勾选并完成两次确认后才会处理。
- 系统目录硬性拦截，无法从界面删除。
- 缓存和临时目录只清空其内容，不删除目录本身。
- 删除默认送入 Windows 回收站，可恢复；回收站不够用时该项会失败并显示错误。
- 所有项目均默认不勾选，包括“建议清理”项目；必须由用户逐项确认。
- AppData 删除会清空所选一级目录内容，可能导致登录状态、设置、本地数据库或未同步数据丢失，因此需要两次确认。
- 同时选择父目录和其缓存子目录时会阻止执行，避免重复或扩大删除范围。
- AppData 大目录使用有时间上限的快速估算，并以 `≥` 标记，避免扫描被超大应用目录长时间阻塞。
- 精确扫描在独立后台进程中运行，可能需要几分钟；关闭主窗口会同时停止扫描并清理临时结果。
- 下载目录只列出超过 30 天的普通文件，并且始终默认不勾选。
- 扫描和删除都不会跟随目录联接或符号链接。

## 当前范围

这是一个安全优先的工具。它不会直接清理 Windows Update、组件存储、驱动程序、注册表、系统还原点或其他需要管理员权限的区域。这些区域应交给 Windows 自带的“存储感知/磁盘清理”处理。

明确不直接删除 `Prefetch`、`WinSxS`、`DriverStore`、Windows Installer 缓存、分页文件、注册表和未知应用数据。名称看似“缓存”并不代表可以绕过对应服务或应用直接删除。

## 开源许可

本项目采用 [MIT License](LICENSE)。
