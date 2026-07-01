# `JobsRemoteHost.py`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`JobsRemoteHost.py` 是 `JobsRemoteHost` 的 [**Python**](https://www.python.org) 跨平台被控端打包工程。它按 `LANFileServer.py` 同款交付方式组织：外层只放用户双击的打包入口，内层 `./JobsRemoteHost/` 保存真正的 Python 单脚本、依赖文件和 PyInstaller 配置。

运行成品时不是双击源码脚本：macOS 用户打开生成的 `*.dmg` 后再打开 `JobsRemoteHost.app`；Windows 用户运行生成的 `JobsRemoteHost-Windows.exe`。

## 一、目录结构 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
JobsRemoteHost.py/
├── README.md
├── 【MacOS】📦生成dmg.command
├── 【Windows】📦生成exe.bat
└── JobsRemoteHost/
    ├── JobsRemoteHost.py
    ├── JobsRemoteHost.spec
    ├── README.md
    ├── requirements.txt
    ├── requirements-build.txt
    ├── 启动JobsRemoteHost.command
    └── 启动JobsRemoteHost.bat
```

## 二、打包入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 平台 | 双击入口 | 输出产物 |
| --- | --- | --- |
| macOS | `./【MacOS】📦生成dmg.command` | `./JobsRemoteHost-macOS-架构.dmg` |
| Windows | `./【Windows】📦生成exe.bat` | `./JobsRemoteHost-Windows.exe` |

打包脚本会在内层工程中创建 `.venv`，安装运行依赖和 [**PyInstaller**](https://pyinstaller.org/)，并下载 [**cloudflared**](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) 到 `./JobsRemoteHost/tools/`。这些内容只写在当前目录树内，不安装到系统目录。

## 三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- macOS：

  1. 双击 `./【MacOS】📦生成dmg.command`。
  2. 生成 `JobsRemoteHost-macOS-架构.dmg`。
  3. 打开 dmg，把 `JobsRemoteHost.app` 放到 `Applications` 或直接打开。
  4. 如系统提示屏幕录制 / 辅助功能权限，到系统设置里给 `JobsRemoteHost.app` 授权。

- Windows：

  1. 在 Windows 本机双击 `./【Windows】📦生成exe.bat`。
  2. 生成 `JobsRemoteHost-Windows.exe`。
  3. 双击 exe 打开被控端窗口。

## 四、安全边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 每次启动都会生成新的邀请码。
- 浏览器访问后，本机必须弹窗确认，确认前不会返回屏幕画面。
- 浏览器申请观看时，本机弹窗只允许“允许观看 / 拒绝”。
- 浏览器申请控制时，本机弹窗允许“允许控制 / 仅允许观看 / 拒绝”。
- 程序不做后台隐藏、不写开机启动、不创建常驻服务。
- 免安装公网链接通过 `cloudflared tunnel` 生成临时 `trycloudflare.com` 地址，适合快速协助，不建议长期公开暴露。

## 五、日志位置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 类型 | 位置 |
| --- | --- |
| 打包脚本日志 | 系统临时目录里的 `【MacOS】📦生成dmg.log` 或终端窗口输出 |
| 应用日志（macOS） | `~/Library/Logs/JobsRemoteHost/JobsRemoteHost.log` |
| 应用日志（Windows） | `%LOCALAPPDATA%\JobsRemoteHost\logs\JobsRemoteHost.log` |

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
