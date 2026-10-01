# `JobsRemoteHost`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

这里是 `JobsRemoteHost.py` 的内层 Python 工程。核心业务集中在 `JobsRemoteHost.py` 单文件中，外层脚本只负责打包分发，不把远程控制逻辑写进 `.bat` / `.command`。

## 一、文件说明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 用途 |
| --- | --- |
| `JobsRemoteHost.py` | Python 被控端核心脚本，包含 GUI、HTTP 服务、屏幕采集、输入控制、cloudflared 通道。 |
| `JobsRemoteHost.spec` | [**PyInstaller**](https://pyinstaller.org/) 打包配置，负责生成 macOS `.app` 或 Windows `.exe`。 |
| `requirements.txt` | 运行依赖：截图、JPEG 压缩、鼠标键盘控制。 |
| `requirements-build.txt` | 打包依赖。 |
| `启动JobsRemoteHost.command` | macOS 内层构建入口。 |
| `启动JobsRemoteHost.bat` | Windows 内层构建入口。 |

## 二、内部命令 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 协议自检：

  ```shell
  python3 JobsRemoteHost.py --self-test
  ```

- macOS 内层打包：

  ```shell
  ./启动JobsRemoteHost.command build-dmg
  ```

- macOS 开发调试源码：

  ```shell
  ./启动JobsRemoteHost.command run-app
  ```

- Windows 内层打包：

  ```bat
  启动JobsRemoteHost.bat build-exe
  ```

## 三、浏览器协议 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 接口 | 说明 |
| --- | --- |
| `GET /` | 浏览器访问页。 |
| `POST /api/request` | 浏览器提交邀请码和访问模式，等待本机授权。 |
| `GET /api/status?session=...` | 轮询授权状态。 |
| `GET /api/frame?session=...` | 授权后拉取 JPEG 屏幕帧。 |
| `POST /api/control` | 控制授权后发送鼠标键盘事件。 |

授权前 `frame` 和 `control` 接口都会返回拒绝，不会传输屏幕或执行输入事件。

## 四、顶部菜单栏驻留 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- macOS 点击黄色最小化按钮后，Tkinter 主窗口会隐藏并驻留系统顶部菜单栏，后台服务和公网通道继续运行。
- 点击顶部菜单栏图标中的“显示 JobsRemoteHost”可恢复窗口。
- 点击“停止服务并退出 JobsRemoteHost”才会停止后台服务、关闭通道并退出进程。

打包前会清理该应用工程的旧 `dist` 产物，清理失败则停止；成功后自动打开当前平台产物的磁盘位置并运行本次生成的 APP / EXE，结尾无需回车。失败时不启动软件；运行前的防误触确认保留。

第一层交付目录与平台打包脚本同层保存 `dist/`，以及最新 APP / DMG 的相对符号链接（Mac）或 EXE / 分发包的 `.lnk`（Windows）。双击快捷方式即可接触成品，真实文件保留在 `dist/`；成功构建自动更新入口，清理旧产物时移除对应旧入口。尚无成品时不生成无效快捷方式。

构建产物使用本机本地构建时间，格式为 `YYYY.MM.DD HH-mm-ss`（年月日时分秒），例如 `2020.06.04 12-23-21`。每次构建的 APP、DMG、EXE、ZIP 和配套文件统一保存到交付层 `../../dist/YYYY.MM.DD HH-mm-ss/`，同次构建只取一次时间；第一层快捷方式指向本次时间目录，成功后打开该目录并启动其中的软件。旧产物沿用原有清理规则；历史产物缺少可靠构建时间时，不补写推测时间。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
