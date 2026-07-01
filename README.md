# `JobsRemoteHost`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`JobsRemoteHost` 是浏览器访问型远程协助工具：被控电脑打开可见窗口，访问方只用浏览器进入链接；本机必须弹窗授权，授权前不会返回屏幕画面，也不会执行鼠标键盘事件。

当前交付重点是 `./JobsRemoteHost.py/` 里的 [**Python**](https://www.python.org) 跨平台被控端。macOS 生成 `*.dmg` 后打开 `JobsRemoteHost.app`，Windows 生成 `JobsRemoteHost-Windows.exe` 后运行。根目录的 [**Swift**](https://www.swift.org/) 源码保留为 macOS 原型，不再提供旧的源码运行脚本入口。

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

### 2.1、macOS 生成 dmg

```shell
./JobsRemoteHost.py/【MacOS】📦生成dmg.command
```

生成后打开 `JobsRemoteHost-macOS-架构.dmg`，再打开里面的 `JobsRemoteHost.app`。

### 2.2、Windows 生成 exe

```bat
JobsRemoteHost.py\【Windows】📦生成exe.bat
```

生成后运行 `JobsRemoteHost-Windows.exe`。

### 2.3、Swift 原型源码调试

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

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
