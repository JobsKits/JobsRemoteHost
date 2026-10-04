# `JobsRemoteHost`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`JobsRemoteHost` 是浏览器访问型远程协助工具：被控电脑打开可见窗口，访问方只用浏览器进入链接；本机必须弹窗授权，授权前不会返回屏幕画面，也不会执行鼠标键盘事件。

当前交付重点是 `./JobsRemoteHost/` 里的 [**Python**](https://www.python.org) 跨平台被控端。macOS 生成 `*.dmg` 后打开 `JobsRemoteHost.app`，Windows 生成 `JobsRemoteHost-Windows.exe` 后运行。根目录的 [**Swift**](https://www.swift.org/) 源码保留为 macOS 原型，不再提供旧的源码运行脚本入口。

## 一、目录结构 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
JobsRemoteHost/
├── JobsRemoteHost.py/
│   ├── README.md
│   ├── 【MacOS】📦生成dmg.command
│   ├── 【Windows】📦生成exe.bat
│   └── JobsRemoteHost/
│       ├── JobsRemoteHost.py
│       ├── JobsRemoteHost.spec
│       ├── requirements.txt
│       ├── requirements-build.txt
│       ├── 启动JobsRemoteHost.command
│       └── 启动JobsRemoteHost.bat
├── Sources/
├── Tests/
├── relay-server/
├── Package.swift
└── README.md
```

## 二、打包与运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 2.1、macOS 生成 dmg <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
./【MacOS】📦生成dmg.command
```

生成后打开 `JobsRemoteHost-macOS-架构.dmg`，再打开里面的 `JobsRemoteHost.app`。

### 2.2、Windows 生成 exe <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```bat
JobsRemoteHost.py\【Windows】📦生成exe.bat
```

生成后运行 `JobsRemoteHost-Windows.exe`。

### 2.3、Swift 原型源码调试 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Swift 版只作为 macOS 原型保留，不作为最终交付入口。需要调试时直接使用 [**Swift**](https://www.swift.org/) 命令：

```shell
swift run JobsRemoteHost
```

## 三、连接方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 方式 | 说明 |
| --- | --- |
| 内网地址 | 同一局域网访问，例如 `http://192.168.x.x:8088/?invite=ABC123`。 |
| 免安装公网链接 | Python 打包版会尝试使用 `cloudflared tunnel` 生成 `trycloudflare.com` 临时链接。 |
| 自建公网中继 | `relay-server/` 保留给 Swift 原型的自建中继实验；生产交付优先使用 Python 打包版。 |

自建中继源码运行命令：

```shell
PORT=8787 node ./relay-server/server.js
```

## 四、安全边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 每次启动服务都会生成新的邀请码。
- 浏览器访问后必须等待本机弹窗授权。
- 授权分为 `仅允许观看` 和 `允许控制`。
- 拒绝授权后，浏览器拿不到画面，也不能发送控制事件。
- 程序不做后台隐藏、不写开机启动、不创建常驻服务。
- 免安装公网链接是临时通道，适合快速远程协助，不建议长期公开暴露。

## 五、验证命令 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Python 协议自检：

```shell
python3 JobsRemoteHost.py/JobsRemoteHost/JobsRemoteHost.py --self-test
```

Swift 测试：

```shell
swift test
```

打包前会清理该应用工程的旧 `dist` 产物，清理失败则停止；成功后自动打开当前平台产物的磁盘位置并运行本次生成的 APP / EXE，结尾无需回车。失败时不启动软件；运行前的防误触确认保留。

必需依赖缺失时，直接回车联网安装；输入任意字符后回车取消整个流程。安装失败或复检仍不可用时停止，不继续清理旧产物或打包。健康依赖直接复用；可选升级和词库更新仍为回车跳过、任意字符执行。

第一层交付目录与平台打包脚本同层保存 `dist/`，以及最新 APP / DMG 的相对符号链接（Mac）或 EXE / 分发包的 `.lnk`（Windows）。双击快捷方式即可接触成品，真实文件保留在 `dist/`；成功构建自动更新入口，清理旧产物时移除对应旧入口。尚无成品时不生成无效快捷方式。

构建产物使用本机本地构建时间，格式为 `YYYY.MM.DD HH-mm-ss`（年月日时分秒），例如 `2020.06.04 12-23-21`。每次构建的 APP、DMG、EXE、ZIP 和配套文件统一保存到交付层 `./dist/YYYY.MM.DD HH-mm-ss/`，同次构建只取一次时间；第一层快捷方式指向本次时间目录，成功后打开该目录并启动其中的软件。旧产物沿用原有清理规则；历史产物缺少可靠构建时间时，不补写推测时间。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
