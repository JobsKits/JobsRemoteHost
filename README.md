# `JobsRemoteHost`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`JobsRemoteHost` 是浏览器访问型远程协助工具：被控电脑打开可见窗口，访问方只用浏览器进入链接；本机必须弹窗授权，授权前不会返回屏幕画面，也不会执行鼠标键盘事件。

当前交付重点是 `./JobsRemoteHost/` 内面向 [**macOS**](https://www.apple.com/macos/) / [**Windows**](https://www.microsoft.com/windows) 的 [**Python**](https://www.python.org) 被控端。两平台的完整打包脚本各保留一份，直接放在仓库根目录；源码、依赖和打包配置集中在一层 `JobsRemoteHost/` 中。本页统一说明使用、开发和打包方式。

根目录的 <u>[**Swift**](https://www.swift.org/)</u> 工程与 Python 版是两套实现，保留为 macOS 原型；`relay-server/` 是配套的自建中继实验源码。

- [目录与文件](#project-layout)
- [打包和运行成品](#package-and-run)
- [环境与依赖](#environment)
- [开发与验证命令](#development)
- [连接方式与浏览器协议](#connection-and-protocol)
- [菜单栏与安全边界](#authorization-and-tray)
- [产物与快捷方式](#artifacts)
- [日志与排查](#logs)

## 一、<span id="project-layout">目录与文件</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
仓库根目录/
├── README.md
├── 【MacOS】📦生成dmg.command
├── 【Windows】📦生成exe.bat
├── icon.png
├── JobsRemoteHost/
│   ├── JobsRemoteHost.py
│   ├── JobsRemoteHost.spec
│   ├── requirements.txt
│   ├── requirements-build.txt
│   └── scripts/
│       └── artifact_shortcuts.py
├── Package.swift
├── Sources/JobsRemoteHost/
├── Tests/JobsRemoteHostTests/
└── relay-server/server.js
```

| 文件或目录 | 用途 |
| --- | --- |
| 根目录两份平台脚本 | 唯一平台入口，内部直接完成环境检查、源码运行、协议自检或打包。 |
| `JobsRemoteHost/JobsRemoteHost.py` | Python 单文件业务：窗口、HTTP 服务、屏幕采集、输入控制和公网通道。 |
| `JobsRemoteHost/JobsRemoteHost.spec` | [**PyInstaller**](https://pyinstaller.org/) 配置，生成 macOS `.app` 或 Windows `.exe`，打包根目录的共享 `icon.png`。 |
| `JobsRemoteHost/requirements.txt` | 运行依赖：屏幕采集、JPEG 压缩、鼠标键盘控制和菜单栏图标。 |
| `JobsRemoteHost/requirements-build.txt` | 引入运行依赖并补充打包依赖。 |
| `JobsRemoteHost/scripts/artifact_shortcuts.py` | 清理和更新交付层的最新产物快捷方式。 |
| `Package.swift`、`Sources/`、`Tests/` | 独立 Swift 原型及测试，使用 macOS 原生窗口和屏幕采集能力。 |
| `relay-server/` | Swift 原型使用的 [**Node.js**](https://nodejs.org) 自建中继实验。 |

构建生成的 `.venv/`、`tools/`、`build/` 位于 `JobsRemoteHost/` 内；`dist/` 与最新产物快捷方式位于仓库根目录，详见[产物与快捷方式](#artifacts)。

## 二、<span id="package-and-run">打包和运行成品</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在目标系统上双击根目录对应脚本，或在仓库根目录运行以下命令。默认分别执行 `build-dmg` / `build-exe`，不需要进入内层查找另一份入口。

### [【MacOS】📦生成dmg.command](./【MacOS】📦生成dmg.command)

> **目的：** 生成远程协助工具的 macOS APP / DMG，或进行源码调试与协议自检。

* 阅读自述并回车，检查 Homebrew、Python 3.11+，准备内层项目虚拟环境。
  * 必需依赖缺失：回车安装，任意非空输入取消；失败停止。
* 按参数选择任务，默认执行 `build-dmg`。
  * `run-app`：启动源码界面；`self-test`：只运行协议自检，均不生成安装包。
* 打包模式按需下载 cloudflared，先通过协议自检，再清理外层旧 `dist/` 并构建 APP / DMG。
* 在构建时间目录保存成品、更新快捷方式，打开产物目录并启动 APP；日志位于系统临时目录。


```shell
./【MacOS】📦生成dmg.command
```

生成 `dist/YYYY.MM.DD HH-mm-ss/JobsRemoteHost-macOS-架构.dmg`，并保留同目录的 `JobsRemoteHost.app`。成功后脚本自动打开产物目录并启动 `.app`。分发时打开 DMG，把应用放到 `Applications` 或直接打开。

首次使用按系统提示，在“系统设置 → 隐私与安全性”中给实际运行的 `JobsRemoteHost.app` 授予屏幕录制和辅助功能权限。

### [【Windows】📦生成exe.bat](./【Windows】📦生成exe.bat)

> **目的：** 在 Windows 本机生成远程协助 EXE，或启动源码与协议自检。

* 显示自述并等待按键，检查 Python 3.11+，准备内层 `.venv/`。
  * Python 缺失时提示后停止；必需依赖缺失时回车安装，任意输入取消。
* 按参数选择任务，默认执行 `build-exe`。
  * `run-app`：启动源码界面；`self-test`：运行协议自检。
* 打包模式按需下载 cloudflared.exe，通过协议自检后清理外层旧 `dist/`，构建并复制为 `JobsRemoteHost-Windows.exe`。
* 更新成品快捷方式，打开构建时间目录并启动新 EXE；任一步失败即停止。


```bat
【Windows】📦生成exe.bat
```

生成 `dist/YYYY.MM.DD HH-mm-ss/JobsRemoteHost-Windows.exe`。成功后脚本自动打开产物目录并启动该 EXE；分发时直接运行生成的 EXE。

运行已打包的成品无需准备 Python 构建环境。两平台应分别在本机打包。

## 三、<span id="environment">环境与依赖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Python 版需要 Python 3.11 或更新版本。脚本在 `JobsRemoteHost/.venv/` 中准备项目依赖，并在打包时下载 [**cloudflared**](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) 到 `JobsRemoteHost/tools/`，随成品打包。

运行依赖包括 [**mss**](https://python-mss.readthedocs.io/)、[**Pillow**](https://pillow.readthedocs.io/)、[**pynput**](https://pynput.readthedocs.io/) 和 [**pystray**](https://pystray.readthedocs.io/)，图形界面使用 [**Tkinter**](https://docs.python.org/3/library/tkinter.html)。打包依赖由 `requirements-build.txt` 统一引入。

### 3.1、macOS 自检 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Mac 脚本内部以具名函数携带完整环境自检，不依赖外部环境支持库或父仓文件。阅读运行时自述并确认后，先检查 [**Homebrew**](https://brew.sh/)：已有安装执行 `brew update`，更新自身和配方索引，不全量升级其它软件；缺少时安装并复检。

安装 Homebrew 时，精确输入大写 `YES` 选择系统标准目录，其它输入或回车选择用户目录。失败停止，不自动改换路线。新系统缺少 Command Line Tools 时，按系统提示完成安装后重试。

Python 使用 Homebrew 配方；实际版本和标准库满足要求时复用，不兼容时安装或升级并复检。旧虚拟环境不兼容时完整改名备份后重建，保留备份。Homebrew 和 Python 环境准备可能修改项目目录之外的对应安装位置。

### 3.2、依赖安装与停止条件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- Windows 入口先检查可用的 Python 3.11+，缺少时提示安装后停止。
- 必需依赖或下载缺失时，直接回车联网安装；任意非空输入（含空格）、EOF 或缺少可交互输入均停止。
- 安装或复检失败立即停止，不继续清理旧产物或打包；健康项目依赖直接复用。
- 打包会先运行协议自检；自检失败停止构建。

## 四、<span id="development">开发与验证命令</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令均在仓库根目录运行。

| 入口 | 默认参数 | 其它参数 |
| --- | --- | --- |
| `./【MacOS】📦生成dmg.command` | `build-dmg` | `run-app`、`self-test` |
| `【Windows】📦生成exe.bat` | `build-exe` | `run-app`、`self-test` |

- macOS 开发运行与脚本自检，会按入口规则准备环境：

  ```shell
  ./【MacOS】📦生成dmg.command run-app
  ./【MacOS】📦生成dmg.command self-test
  ```

- Windows 开发运行与脚本自检：

  ```bat
  【Windows】📦生成exe.bat run-app
  【Windows】📦生成exe.bat self-test
  ```

- 只验证 Python 协议，可直接运行源码自检，不启动窗口、不下载通道、不安装依赖：

  ```shell
  python3 ./JobsRemoteHost/JobsRemoteHost.py --self-test
  ```

- Swift 原型调试与测试，需要 macOS 15.2+ 及兼容的 Swift 工具链：

  ```shell
  swift run JobsRemoteHost
  swift test
  ```

协议自检不等于屏幕采集、系统权限、菜单栏和双平台成品验收；这些功能仍需在对应系统实际运行核对。

## 五、<span id="connection-and-protocol">连接方式与浏览器协议</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 方式 | 说明 |
| --- | --- |
| 内网地址 | 同一局域网访问，例如 `http://192.168.x.x:8088/?invite=ABC123`。 |
| 免安装公网链接 | Python 打包版尝试通过 `cloudflared tunnel` 生成 `trycloudflare.com` 临时链接。 |
| 自建公网中继 | `relay-server/` 保留给 Swift 原型的独立实验，Python 打包版不依赖它。 |

自建中继源码运行命令：

```shell
PORT=8787 node ./relay-server/server.js
```

Python 浏览器协议：

| 接口 | 说明 |
| --- | --- |
| `GET /` | 浏览器访问页。 |
| `POST /api/request` | 提交邀请码和访问模式，等待本机授权。 |
| `GET /api/status?session=...` | 轮询授权状态。 |
| `GET /api/frame?session=...` | 授权后拉取 JPEG 屏幕帧。 |
| `POST /api/control` | 控制授权后发送鼠标键盘事件。 |

授权前，画面和控制接口都会拒绝请求，不传输屏幕、不执行输入事件。

## 六、<span id="authorization-and-tray">菜单栏与安全边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 每次启动服务生成新的邀请码；浏览器必须等待本机弹窗确认。
- 申请观看时，本机可选“允许观看 / 拒绝”；申请控制时，可选“允许控制 / 仅允许观看 / 拒绝”。
- macOS 点击黄色最小化按钮后，窗口隐藏并驻留顶部菜单栏，服务和公网通道继续运行；通过“显示 JobsRemoteHost”恢复窗口。
- Windows 使用通知区域图标；菜单提供恢复窗口和“停止服务并退出 JobsRemoteHost”。图标不可用时保留普通窗口模式。
- 菜单中选择“停止服务并退出 JobsRemoteHost”会停止服务、关闭通道并退出进程。
- 程序不写开机启动、不创建常驻系统服务，菜单栏驻留由可见应用提供。
- 临时公网通道适合快速远程协助，不建议长期公开暴露；使用完毕及时停止服务。

## 七、<span id="artifacts">产物与快捷方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

真实产物统一保存在根目录 `dist/YYYY.MM.DD HH-mm-ss/` 中，使用本机本地构建时间，例如 `dist/2020.06.04 12-23-21/`。同次构建只取一次时间，APP、DMG、EXE 和配套文件共用该时间目录；历史产物缺少可靠时间时不补写推测时间。

**打包前会清理该应用根目录的旧 `dist/` 及对应旧快捷方式。** 运行前保留用途与影响确认；清理失败停止。需要留存的旧成品应先移出该目录。

成功构建后，根目录自动更新最新 APP / DMG 的相对符号链接（Mac）或 EXE 的 `.lnk`（Windows），与平台脚本和 `dist/` 同层。快捷方式指向当前时间目录，真实产物仍在 `dist/`；没有成品时不生成无效入口。

成功后自动打开产物所在目录并启动当前平台软件，结尾无需回车；失败时不启动软件。

## 八、<span id="logs">日志与排查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 类型 | 位置 |
| --- | --- |
| Mac 脚本日志 | 系统临时目录中的 `【MacOS】📦生成dmg.log`，脚本自述显示实际位置。 |
| Windows 脚本输出 | 当前终端窗口。 |
| macOS 应用日志 | 当前用户 `Library/Logs/JobsRemoteHost/` 中的 `JobsRemoteHost.log`。 |
| Windows 应用日志 | 当前用户本地应用数据目录 `JobsRemoteHost/logs/` 中的 `JobsRemoteHost.log`。 |

- 画面或输入不可用：检查本机授权状态和 macOS 屏幕录制、辅助功能权限。
- 公网链接未生成：检查应用日志中的 `cloudflared` 输出；同一局域网可使用窗口显示的内网地址。
- 菜单栏图标不可用：应用会记录原因并继续普通窗口模式，核对项目依赖和共享 `icon.png`。
- 依赖准备失败：查看入口终端和 Mac 脚本日志，修复失败层级后重新运行；不要绕过复检直接打包。

## 九、<span id="repository-layout-and-entrypoints">本仓目录与脚本入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下为当前检出的源码与维护入口；依赖环境、Git 元数据、构建缓存和生成产物略去，独立子仓仅列目录。

```text
.
├── .gitignore
├── 【MacOS】📦生成dmg.command
├── 【Windows】📦生成exe.bat
├── icon.png
├── JobsRemoteHost/
│   ├── JobsRemoteHost.py
│   ├── JobsRemoteHost.spec
│   ├── requirements-build.txt
│   ├── requirements.txt
│   └── scripts/
├── Package.swift
├── README.md
├── relay-server/
│   └── server.js
├── Sources/
└── Tests/
```

* `JobsRemoteHost/` 保存 Python 被控端、依赖、工具与打包辅助代码；`Sources/`、`Tests/` 是 Swift 原型，`relay-server/` 是中继实验源码。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
