#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""JobsRemoteHost Python 被控端。

这份单文件脚本面向 Windows / macOS 打包：本机显示可见窗口，浏览器端访问后必须等待
被控电脑确认授权，授权前不会返回屏幕画面，也不会执行输入事件。
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import dataclasses
import http.client
import http.server
import io
import json
import os
import platform
import queue
import random
import re
import secrets
import shutil
import signal
import socket
import socketserver
import string
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

APP_NAME = "JobsRemoteHost"
DEFAULT_PORT = 8088
MAX_FRAME_WIDTH = 1600
JPEG_QUALITY = 58
INVITE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
VIEWER_HTML_VERSION = "2026-07-01"
MIN_PYTHON = (3, 11)


# 单像素 JPEG，用于自检，避免自检依赖 mss / Pillow。
SELF_TEST_JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////"
    "2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/"
    "xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAEFAqf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/ASP/"
    "xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/ASP/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/Aqf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/IV//"
    "2gAMAwEAAgADAAAAEP/EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8QH//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8QH//EABQQAQAAAAAAAAAAAAAAAAAAABD/"
    "2gAIAQEAAT8QH//Z"
)


def resource_path(name: str) -> Path:
    """返回源码运行或 PyInstaller 打包后的资源路径。"""

    bundle_root = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    return bundle_root / name


@dataclasses.dataclass(slots=True)
class FrameInfo:
    """记录当前屏幕帧的尺寸信息。"""

    width: int = 0
    height: int = 0
    screen_width: int = 0
    screen_height: int = 0
    left: int = 0
    top: int = 0


@dataclasses.dataclass(slots=True)
class AccessRequest:
    """浏览器访问请求，等待本机窗口弹窗处理。"""

    session_id: str
    invite: str
    mode: str
    remote_addr: str
    created_at: float


@dataclasses.dataclass(slots=True)
class SessionState:
    """浏览器会话状态。"""

    session_id: str
    requested_mode: str
    remote_addr: str
    created_at: float
    status: str = "pending"
    granted_mode: str = "none"
    updated_at: float = dataclasses.field(default_factory=time.time)

    @property
    def can_view(self) -> bool:
        return self.status == "authorized" and self.granted_mode in {"view", "control"}

    @property
    def can_control(self) -> bool:
        return self.status == "authorized" and self.granted_mode == "control"


@dataclasses.dataclass(slots=True)
class AppConfig:
    """运行时配置。"""

    port: int = DEFAULT_PORT
    bind_host: str = "0.0.0.0"
    invite_code: str = ""
    start_tunnel: bool = True
    frame_max_width: int = MAX_FRAME_WIDTH
    jpeg_quality: int = JPEG_QUALITY


class JobsRemoteHostError(RuntimeError):
    """应用级异常。"""


def now_text() -> str:
    """返回适合日志显示的本地时间。"""

    return datetime.now().strftime("%H:%M:%S")


def json_bytes(payload: dict[str, Any]) -> bytes:
    """把对象编码为 HTTP JSON 字节。"""

    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def parse_json_body(handler: http.server.BaseHTTPRequestHandler) -> dict[str, Any]:
    """读取并解析请求体 JSON。"""

    content_length = int(handler.headers.get("Content-Length") or "0")
    raw_body = handler.rfile.read(content_length) if content_length > 0 else b"{}"
    if not raw_body:
        return {}
    try:
        payload = json.loads(raw_body.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise JobsRemoteHostError("请求体不是合法 JSON") from exc
    if not isinstance(payload, dict):
        raise JobsRemoteHostError("请求体必须是 JSON Object")
    return payload


def generate_invite_code(length: int = 6) -> str:
    """生成本轮服务使用的邀请码。"""

    return "".join(secrets.choice(INVITE_ALPHABET) for _ in range(length))


def app_data_dir() -> Path:
    """返回当前平台的应用数据目录。"""

    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        return Path(base) / APP_NAME
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / APP_NAME
    return Path.home() / f".{APP_NAME.lower()}"


def log_file_path() -> Path:
    """返回应用日志文件路径。"""

    if sys.platform == "darwin":
        log_dir = Path.home() / "Library" / "Logs" / APP_NAME
    elif os.name == "nt":
        log_dir = app_data_dir() / "logs"
    else:
        log_dir = app_data_dir() / "logs"
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
    except OSError:
        log_dir = Path(tempfile.gettempdir()) / APP_NAME / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
    return log_dir / f"{APP_NAME}.log"


def bundled_base_dir() -> Path:
    """返回源码或 PyInstaller 临时解包目录。"""

    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        return Path(meipass)
    return Path(__file__).resolve().parent


def executable_dir() -> Path:
    """返回可执行文件所在目录。"""

    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


class LogSink:
    """同时写 GUI 队列和本地文件的日志器。"""

    def __init__(self, ui_queue: queue.Queue[tuple[str, Any]] | None = None) -> None:
        self.ui_queue = ui_queue
        self.path = log_file_path()
        self._lock = threading.Lock()

    def write(self, message: str) -> None:
        line = f"[{now_text()}] {message}"
        with self._lock:
            with self.path.open("a", encoding="utf-8") as stream:
                stream.write(line + "\n")
        if self.ui_queue is not None:
            self.ui_queue.put(("log", line))


class SessionRegistry:
    """维护浏览器会话和本机授权队列。"""

    def __init__(self, invite_code: str, ui_queue: queue.Queue[tuple[str, Any]], log: LogSink) -> None:
        self.invite_code = invite_code
        self.ui_queue = ui_queue
        self.log = log
        self._lock = threading.RLock()
        self._sessions: dict[str, SessionState] = {}

    def request_access(self, invite: str, mode: str, remote_addr: str) -> SessionState:
        """创建待授权会话。"""

        if invite != self.invite_code:
            raise PermissionError("邀请码错误")
        if mode not in {"view", "control"}:
            raise JobsRemoteHostError("访问模式只能是 view 或 control")
        session_id = secrets.token_urlsafe(18)
        state = SessionState(
            session_id=session_id,
            requested_mode=mode,
            remote_addr=remote_addr,
            created_at=time.time(),
        )
        request = AccessRequest(
            session_id=session_id,
            invite=invite,
            mode=mode,
            remote_addr=remote_addr,
            created_at=state.created_at,
        )
        with self._lock:
            self._sessions[session_id] = state
        self.ui_queue.put(("access_request", request))
        self.log.write(f"浏览器请求{self._mode_text(mode)}，来源 {remote_addr}")
        return state

    def resolve(self, session_id: str, granted_mode: str) -> None:
        """写入本机窗口授权结果。"""

        with self._lock:
            state = self._sessions.get(session_id)
            if state is None:
                return
            state.updated_at = time.time()
            if granted_mode in {"view", "control"}:
                if state.requested_mode == "view" and granted_mode == "control":
                    granted_mode = "view"
                state.status = "authorized"
                state.granted_mode = granted_mode
                self.log.write(f"已授权 {state.remote_addr}：{self._mode_text(granted_mode)}")
            else:
                state.status = "denied"
                state.granted_mode = "none"
                self.log.write(f"已拒绝 {state.remote_addr} 的访问请求")

    def get(self, session_id: str) -> SessionState | None:
        """查询会话状态。"""

        with self._lock:
            return self._sessions.get(session_id)

    def cleanup(self) -> None:
        """清理过期会话。"""

        now = time.time()
        with self._lock:
            expired = [
                session_id
                for session_id, state in self._sessions.items()
                if now - state.updated_at > 3600 or (state.status in {"denied", "pending"} and now - state.created_at > 600)
            ]
            for session_id in expired:
                self._sessions.pop(session_id, None)

    @staticmethod
    def _mode_text(mode: str) -> str:
        """把访问模式转成中文。"""

        return "允许控制" if mode == "control" else "仅观看"


class ScreenCaptureService:
    """负责采集桌面画面并压缩为 JPEG。"""

    def __init__(self, max_width: int, quality: int) -> None:
        self.max_width = max_width
        self.quality = quality
        self.info = FrameInfo()
        self._lock = threading.Lock()
        self._mss: Any | None = None

    def capture_jpeg(self) -> bytes:
        """采集当前屏幕帧。"""

        with self._lock:
            return self._capture_locked()

    def _capture_locked(self) -> bytes:
        """在锁内执行一次屏幕采集。"""

        try:
            import mss
            from PIL import Image
        except ImportError as exc:
            raise JobsRemoteHostError("缺少屏幕采集依赖，请通过打包脚本安装 mss 和 Pillow") from exc

        if self._mss is None:
            self._mss = mss.mss()
        monitor = self._mss.monitors[0]
        shot = self._mss.grab(monitor)
        image = Image.frombytes("RGB", shot.size, shot.rgb)
        original_width, original_height = image.size
        if original_width > self.max_width:
            next_height = max(1, int(original_height * (self.max_width / original_width)))
            image = image.resize((self.max_width, next_height), Image.Resampling.BILINEAR)
        self.info = FrameInfo(
            width=image.size[0],
            height=image.size[1],
            screen_width=original_width,
            screen_height=original_height,
            left=int(monitor.get("left", 0)),
            top=int(monitor.get("top", 0)),
        )
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=self.quality, optimize=True)
        return buffer.getvalue()

    def map_control_event(self, event: dict[str, Any]) -> dict[str, Any]:
        """把浏览器图像坐标映射回真实屏幕坐标。"""

        event_type = str(event.get("type") or "")
        if event_type not in {"mouseMove", "mouseDown", "mouseUp"}:
            return event
        info = self.info
        if info.width <= 0 or info.height <= 0 or info.screen_width <= 0 or info.screen_height <= 0:
            return event
        mapped = dict(event)
        x = float(mapped.get("x") or 0)
        y = float(mapped.get("y") or 0)
        mapped["x"] = int(info.left + (x / info.width) * info.screen_width)
        mapped["y"] = int(info.top + (y / info.height) * info.screen_height)
        return mapped


class SelfTestCaptureService:
    """自检用的假屏幕采集器。"""

    def __init__(self) -> None:
        self.info = FrameInfo(width=1, height=1, screen_width=1, screen_height=1)

    def capture_jpeg(self) -> bytes:
        return SELF_TEST_JPEG

    def map_control_event(self, event: dict[str, Any]) -> dict[str, Any]:
        return event


class InputController:
    """把浏览器控制事件映射到本机鼠标键盘。"""

    KEY_MAP = {
        "Alt": "alt",
        "AltGraph": "alt_gr",
        "Backspace": "backspace",
        "CapsLock": "caps_lock",
        "Control": "ctrl",
        "Delete": "delete",
        "End": "end",
        "Enter": "enter",
        "Escape": "esc",
        "F1": "f1",
        "F2": "f2",
        "F3": "f3",
        "F4": "f4",
        "F5": "f5",
        "F6": "f6",
        "F7": "f7",
        "F8": "f8",
        "F9": "f9",
        "F10": "f10",
        "F11": "f11",
        "F12": "f12",
        "Home": "home",
        "Meta": "cmd",
        "PageDown": "page_down",
        "PageUp": "page_up",
        "Shift": "shift",
        "Space": "space",
        "Tab": "tab",
        "ArrowUp": "up",
        "ArrowDown": "down",
        "ArrowLeft": "left",
        "ArrowRight": "right",
    }

    def __init__(self) -> None:
        self._mouse: Any | None = None
        self._keyboard: Any | None = None

    def apply(self, event: dict[str, Any]) -> None:
        """执行一个浏览器输入事件。"""

        try:
            from pynput import keyboard, mouse
        except ImportError as exc:
            raise JobsRemoteHostError("缺少控制依赖，请通过打包脚本安装 pynput") from exc

        if self._mouse is None:
            self._mouse = mouse.Controller()
        if self._keyboard is None:
            self._keyboard = keyboard.Controller()

        event_type = str(event.get("type") or "")
        if event_type == "mouseMove":
            self._mouse.position = (int(event.get("x") or 0), int(event.get("y") or 0))
        elif event_type in {"mouseDown", "mouseUp"}:
            button = self._mouse_button(mouse, int(event.get("button") or 0))
            if event_type == "mouseDown":
                self._mouse.press(button)
            else:
                self._mouse.release(button)
        elif event_type == "wheel":
            self._mouse.scroll(int(event.get("dx") or 0), int(event.get("dy") or 0))
        elif event_type in {"keyDown", "keyUp"}:
            key = self._keyboard_key(keyboard, str(event.get("key") or ""))
            if key is None:
                return
            if event_type == "keyDown":
                self._keyboard.press(key)
            else:
                self._keyboard.release(key)

    @staticmethod
    def _mouse_button(mouse_module: Any, button_index: int) -> Any:
        """把 DOM 鼠标按钮映射到 pynput。"""

        if button_index == 1:
            return mouse_module.Button.middle
        if button_index == 2:
            return mouse_module.Button.right
        return mouse_module.Button.left

    @classmethod
    def _keyboard_key(cls, keyboard_module: Any, key_name: str) -> Any | None:
        """把 DOM 键名映射到 pynput。"""

        mapped = cls.KEY_MAP.get(key_name)
        if mapped:
            return getattr(keyboard_module.Key, mapped, None)
        if len(key_name) == 1:
            return key_name
        return None


class SelfTestInputController:
    """自检用的假输入控制器。"""

    def __init__(self) -> None:
        self.events: list[dict[str, Any]] = []

    def apply(self, event: dict[str, Any]) -> None:
        self.events.append(event)


class NetworkAddressService:
    """枚举本机可展示给访问方的内网地址。"""

    @staticmethod
    def local_http_urls(port: int, invite_code: str) -> list[str]:
        addresses: set[str] = set()
        with contextlib.suppress(Exception):
            hostname = socket.gethostname()
            for item in socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_STREAM):
                ip = item[4][0]
                if NetworkAddressService._is_usable_ipv4(ip):
                    addresses.add(ip)
        with contextlib.suppress(Exception):
            probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                probe.connect(("8.8.8.8", 80))
                ip = probe.getsockname()[0]
                if NetworkAddressService._is_usable_ipv4(ip):
                    addresses.add(ip)
            finally:
                probe.close()
        if not addresses:
            addresses.add("127.0.0.1")
        query = urllib.parse.urlencode({"invite": invite_code})
        return [f"http://{ip}:{port}/?{query}" for ip in sorted(addresses)]

    @staticmethod
    def _is_usable_ipv4(ip: str) -> bool:
        """过滤回环、链路本地和空地址。"""

        return not (
            ip.startswith("127.")
            or ip.startswith("169.254.")
            or ip == "0.0.0.0"
            or ip.startswith("224.")
            or ip.startswith("255.")
        )


class QuickTunnelService:
    """管理 cloudflared 临时公网通道。"""

    URL_RE = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com", re.IGNORECASE)

    def __init__(self, log: LogSink, event_queue: queue.Queue[tuple[str, Any]]) -> None:
        self.log = log
        self.event_queue = event_queue
        self.process: subprocess.Popen[str] | None = None
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()

    def start(self, port: int, invite_code: str) -> None:
        """启动临时公网通道。"""

        if self.process is not None:
            return
        executable = self.find_cloudflared()
        if executable is None:
            self.log.write("未找到 cloudflared，公网链接暂不可用；可继续使用内网地址")
            self.event_queue.put(("tunnel_error", "未找到 cloudflared"))
            return
        self._stop_event.clear()
        command = [str(executable), "tunnel", "--url", f"http://127.0.0.1:{port}", "--no-autoupdate"]
        self.process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        self.log.write("正在准备免安装公网链接")
        self._thread = threading.Thread(
            target=self._read_output,
            args=(invite_code,),
            name="cloudflared-output",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        """停止临时公网通道。"""

        self._stop_event.set()
        process = self.process
        self.process = None
        if process is None:
            return
        with contextlib.suppress(Exception):
            process.terminate()
        with contextlib.suppress(Exception):
            process.wait(timeout=5)
        if process.poll() is None:
            with contextlib.suppress(Exception):
                process.kill()
        self.log.write("免安装公网通道已停止")

    def _read_output(self, invite_code: str) -> None:
        """解析 cloudflared 输出里的 trycloudflare URL。"""

        assert self.process is not None
        seen_url = ""
        for line in self.process.stdout or []:
            if self._stop_event.is_set():
                break
            clean = line.strip()
            if clean:
                self.log.write(f"cloudflared：{clean}")
            match = self.URL_RE.search(clean)
            if match:
                base_url = match.group(0).rstrip("/")
                if base_url != seen_url:
                    seen_url = base_url
                    public_url = f"{base_url}/?{urllib.parse.urlencode({'invite': invite_code})}"
                    self.event_queue.put(("tunnel_url", public_url))
                    self.log.write(f"免安装公网链接已生成：{public_url}")
        if not self._stop_event.is_set():
            self.event_queue.put(("tunnel_error", "cloudflared 已退出"))
            self.log.write("cloudflared 已退出")

    @staticmethod
    def find_cloudflared() -> Path | None:
        """从打包资源、项目 tools 或 PATH 查找 cloudflared。"""

        binary_name = "cloudflared.exe" if os.name == "nt" else "cloudflared"
        candidates = [
            bundled_base_dir() / "bin" / binary_name,
            executable_dir() / binary_name,
            executable_dir() / "tools" / binary_name,
            Path(__file__).resolve().parent / "tools" / binary_name,
        ]
        for candidate in candidates:
            if candidate.is_file():
                return candidate
        from_path = shutil.which(binary_name)
        return Path(from_path) if from_path else None


class RemoteHTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    """浏览器访问端 HTTP 接口。"""

    server_version = f"{APP_NAME}/{VIEWER_HTML_VERSION}"

    @property
    def app_server(self) -> "RemoteHTTPServer":
        return self.server  # type: ignore[return-value]

    def log_message(self, format_text: str, *args: Any) -> None:
        """关闭 BaseHTTPRequestHandler 默认 stderr 日志。"""

    def do_GET(self) -> None:
        """处理 GET 请求。"""

        try:
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == "/":
                self._send_html(viewer_html())
            elif parsed.path == "/api/info":
                self._send_json(self.app_server.info_payload())
            elif parsed.path == "/api/status":
                self._handle_status(parsed)
            elif parsed.path == "/api/frame":
                self._handle_frame(parsed)
            else:
                self._send_json({"ok": False, "error": "Not Found"}, status=404)
        except Exception as exc:
            self._handle_exception(exc)

    def do_POST(self) -> None:
        """处理 POST 请求。"""

        try:
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == "/api/request":
                self._handle_request_access()
            elif parsed.path == "/api/control":
                self._handle_control()
            else:
                self._send_json({"ok": False, "error": "Not Found"}, status=404)
        except Exception as exc:
            self._handle_exception(exc)

    def _handle_request_access(self) -> None:
        """处理浏览器申请观看或控制。"""

        payload = parse_json_body(self)
        invite = str(payload.get("invite") or "")
        mode = str(payload.get("mode") or "view")
        remote_addr = self.client_address[0] if self.client_address else "unknown"
        try:
            state = self.app_server.registry.request_access(invite=invite, mode=mode, remote_addr=remote_addr)
        except PermissionError:
            self._send_json({"ok": False, "error": "邀请码错误"}, status=403)
            return
        self._send_json(
            {
                "ok": True,
                "session": state.session_id,
                "status": state.status,
                "requestedMode": state.requested_mode,
            }
        )

    def _handle_status(self, parsed: urllib.parse.ParseResult) -> None:
        """返回浏览器会话状态。"""

        query = urllib.parse.parse_qs(parsed.query)
        session_id = (query.get("session") or [""])[0]
        state = self.app_server.registry.get(session_id)
        if state is None:
            self._send_json({"ok": False, "error": "会话不存在"}, status=404)
            return
        frame = self.app_server.capture.info
        self._send_json(
            {
                "ok": True,
                "status": state.status,
                "requestedMode": state.requested_mode,
                "grantedMode": state.granted_mode,
                "canView": state.can_view,
                "canControl": state.can_control,
                "frameWidth": frame.width,
                "frameHeight": frame.height,
            }
        )

    def _handle_frame(self, parsed: urllib.parse.ParseResult) -> None:
        """返回已授权会话的 JPEG 屏幕帧。"""

        query = urllib.parse.parse_qs(parsed.query)
        session_id = (query.get("session") or [""])[0]
        state = self.app_server.registry.get(session_id)
        if state is None or not state.can_view:
            self._send_json({"ok": False, "error": "未授权"}, status=403)
            return
        try:
            frame = self.app_server.capture.capture_jpeg()
        except Exception as exc:
            self.app_server.log.write(f"采集屏幕失败：{exc}")
            self._send_json({"ok": False, "error": str(exc)}, status=503)
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(frame)))
        self.end_headers()
        self.wfile.write(frame)

    def _handle_control(self) -> None:
        """执行已授权控制会话的输入事件。"""

        payload = parse_json_body(self)
        session_id = str(payload.get("session") or "")
        state = self.app_server.registry.get(session_id)
        if state is None or not state.can_control:
            self._send_json({"ok": False, "error": "没有控制权限"}, status=403)
            return
        event = payload.get("event")
        if not isinstance(event, dict):
            self._send_json({"ok": False, "error": "缺少控制事件"}, status=400)
            return
        try:
            mapped_event = self.app_server.capture.map_control_event(event)
            self.app_server.input_controller.apply(mapped_event)
        except Exception as exc:
            self.app_server.log.write(f"执行控制事件失败：{exc}")
            self._send_json({"ok": False, "error": str(exc)}, status=503)
            return
        self._send_json({"ok": True})

    def _send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        """发送 JSON 响应。"""

        raw = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _send_html(self, html: str) -> None:
        """发送 HTML 页面。"""

        raw = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _handle_exception(self, exc: Exception) -> None:
        """把异常转换为 HTTP 响应和本机日志。"""

        self.app_server.log.write(f"HTTP 接口异常：{exc}")
        if isinstance(exc, JobsRemoteHostError):
            self._send_json({"ok": False, "error": str(exc)}, status=400)
        else:
            self._send_json({"ok": False, "error": "服务器内部错误"}, status=500)


class RemoteHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """带应用上下文的多线程 HTTP Server。"""

    daemon_threads = True
    allow_reuse_address = True

    def __init__(
        self,
        server_address: tuple[str, int],
        registry: SessionRegistry,
        capture: ScreenCaptureService | SelfTestCaptureService,
        input_controller: InputController | SelfTestInputController,
        log: LogSink,
    ) -> None:
        super().__init__(server_address, RemoteHTTPRequestHandler)
        self.registry = registry
        self.capture = capture
        self.input_controller = input_controller
        self.log = log

    def info_payload(self) -> dict[str, Any]:
        """返回服务基础信息。"""

        return {
            "ok": True,
            "name": APP_NAME,
            "platform": platform.platform(),
            "version": VIEWER_HTML_VERSION,
        }


class HostServer:
    """控制本地 HTTP 服务生命周期。"""

    def __init__(
        self,
        config: AppConfig,
        registry: SessionRegistry,
        capture: ScreenCaptureService | SelfTestCaptureService,
        input_controller: InputController | SelfTestInputController,
        log: LogSink,
    ) -> None:
        self.config = config
        self.registry = registry
        self.capture = capture
        self.input_controller = input_controller
        self.log = log
        self.httpd: RemoteHTTPServer | None = None
        self.thread: threading.Thread | None = None

    @property
    def is_running(self) -> bool:
        return self.httpd is not None

    @property
    def bound_port(self) -> int:
        if self.httpd is None:
            return self.config.port
        return int(self.httpd.server_address[1])

    def start(self) -> None:
        """启动 HTTP 服务。"""

        if self.httpd is not None:
            return
        self.httpd = RemoteHTTPServer(
            (self.config.bind_host, self.config.port),
            registry=self.registry,
            capture=self.capture,
            input_controller=self.input_controller,
            log=self.log,
        )
        self.thread = threading.Thread(target=self.httpd.serve_forever, name="remote-http-server", daemon=True)
        self.thread.start()
        self.config.port = self.bound_port
        self.log.write(f"服务已开启，端口 {self.bound_port}，邀请码 {self.config.invite_code}")
        self.log.write("HTTP 服务状态：ready")

    def stop(self) -> None:
        """停止 HTTP 服务。"""

        httpd = self.httpd
        self.httpd = None
        if httpd is None:
            return
        httpd.shutdown()
        httpd.server_close()
        self.log.write("服务已停止")


def viewer_html() -> str:
    """返回浏览器观看 / 控制页面。"""

    return r"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>JobsRemoteHost</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; min-height: 100vh; background: #0f172a; color: #e5e7eb; }
    .wrap { max-width: 1120px; margin: 0 auto; padding: 28px 18px 40px; }
    .hero { display: flex; align-items: center; justify-content: space-between; gap: 18px; margin-bottom: 18px; }
    h1 { margin: 0 0 6px; font-size: 30px; letter-spacing: -0.03em; }
    p { margin: 0; color: #94a3b8; }
    .card { background: rgba(15, 23, 42, .86); border: 1px solid rgba(148, 163, 184, .25); border-radius: 18px; padding: 18px; box-shadow: 0 24px 60px rgba(2, 6, 23, .35); }
    .controls { display: grid; grid-template-columns: 1fr auto auto; gap: 10px; align-items: center; }
    input { height: 42px; border-radius: 12px; border: 1px solid rgba(148, 163, 184, .32); background: #111827; color: #e5e7eb; padding: 0 12px; font-size: 17px; outline: none; }
    button { height: 42px; padding: 0 18px; border: 0; border-radius: 12px; background: #2563eb; color: white; font-size: 16px; font-weight: 700; cursor: pointer; }
    button.secondary { background: #334155; }
    button:disabled { opacity: .55; cursor: not-allowed; }
    .status { margin-top: 12px; color: #cbd5e1; min-height: 22px; }
    .screen-wrap { margin-top: 18px; background: #020617; border-radius: 18px; overflow: hidden; border: 1px solid rgba(148, 163, 184, .25); min-height: 420px; display: grid; place-items: center; }
    img { max-width: 100%; display: block; user-select: none; -webkit-user-drag: none; cursor: crosshair; }
    .empty { color: #64748b; padding: 44px; text-align: center; }
    @media (max-width: 720px) { .controls { grid-template-columns: 1fr; } .hero { display: block; } }
  </style>
</head>
<body>
<div class="wrap">
  <div class="hero">
    <div>
      <h1>JobsRemoteHost</h1>
      <p>浏览器访问端。输入邀请码后，本机必须弹窗授权才会显示屏幕。</p>
    </div>
  </div>
  <div class="card">
    <div class="controls">
      <input id="invite" placeholder="输入邀请码" autocomplete="one-time-code">
      <button id="viewBtn">请求观看</button>
      <button id="controlBtn" class="secondary">请求控制</button>
    </div>
    <div id="status" class="status">等待输入邀请码。</div>
  </div>
  <div class="screen-wrap" id="screenWrap">
    <div class="empty" id="empty">授权通过后，这里会显示被控电脑屏幕。</div>
    <img id="screen" alt="Remote screen" hidden>
  </div>
</div>
<script>
const inviteInput = document.getElementById("invite");
const statusEl = document.getElementById("status");
const screen = document.getElementById("screen");
const empty = document.getElementById("empty");
const viewBtn = document.getElementById("viewBtn");
const controlBtn = document.getElementById("controlBtn");
const params = new URLSearchParams(location.search);
inviteInput.value = params.get("invite") || "";
let session = "";
let canControl = false;
let lastMove = 0;
function setStatus(text) { statusEl.textContent = text; }
async function postJson(url, payload) {
  const response = await fetch(url, { method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(payload) });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.ok === false) throw new Error(data.error || response.statusText);
  return data;
}
async function requestAccess(mode) {
  const invite = inviteInput.value.trim().toUpperCase();
  if (!invite) { setStatus("请先输入邀请码。"); return; }
  viewBtn.disabled = true; controlBtn.disabled = true;
  try {
    const data = await postJson("/api/request", { invite, mode });
    session = data.session;
    setStatus("已发送请求，等待被控电脑确认授权…");
    pollStatus();
  } catch (error) {
    viewBtn.disabled = false; controlBtn.disabled = false;
    setStatus("请求失败：" + error.message);
  }
}
async function pollStatus() {
  if (!session) return;
  try {
    const response = await fetch("/api/status?session=" + encodeURIComponent(session) + "&t=" + Date.now(), { cache: "no-store" });
    const data = await response.json();
    if (!response.ok || !data.ok) throw new Error(data.error || response.statusText);
    if (data.status === "authorized") {
      canControl = !!data.canControl;
      setStatus(canControl ? "已授权控制。移动鼠标或键盘会传到被控电脑。" : "已授权观看。");
      startFrames();
      return;
    }
    if (data.status === "denied") {
      setStatus("被控电脑已拒绝本次访问。");
      viewBtn.disabled = false; controlBtn.disabled = false;
      return;
    }
    setTimeout(pollStatus, 800);
  } catch (error) {
    setStatus("查询状态失败：" + error.message);
    setTimeout(pollStatus, 1200);
  }
}
function startFrames() {
  empty.hidden = true;
  screen.hidden = false;
  const loop = () => {
    if (!session) return;
    screen.src = "/api/frame?session=" + encodeURIComponent(session) + "&t=" + Date.now();
    setTimeout(loop, 180);
  };
  loop();
}
function framePoint(event) {
  const rect = screen.getBoundingClientRect();
  const naturalW = screen.naturalWidth || rect.width;
  const naturalH = screen.naturalHeight || rect.height;
  return {
    x: Math.max(0, Math.round((event.clientX - rect.left) * naturalW / rect.width)),
    y: Math.max(0, Math.round((event.clientY - rect.top) * naturalH / rect.height))
  };
}
function sendControl(event) {
  if (!session || !canControl) return;
  fetch("/api/control", { method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({ session, event }) }).catch(() => {});
}
screen.addEventListener("mousemove", event => {
  if (Date.now() - lastMove < 30) return;
  lastMove = Date.now();
  const point = framePoint(event);
  sendControl({ type: "mouseMove", x: point.x, y: point.y });
});
screen.addEventListener("mousedown", event => {
  const point = framePoint(event);
  sendControl({ type: "mouseDown", x: point.x, y: point.y, button: event.button });
});
screen.addEventListener("mouseup", event => {
  const point = framePoint(event);
  sendControl({ type: "mouseUp", x: point.x, y: point.y, button: event.button });
});
screen.addEventListener("wheel", event => {
  event.preventDefault();
  sendControl({ type: "wheel", dx: Math.sign(event.deltaX), dy: -Math.sign(event.deltaY) });
}, { passive: false });
window.addEventListener("keydown", event => sendControl({ type: "keyDown", key: event.key }));
window.addEventListener("keyup", event => sendControl({ type: "keyUp", key: event.key }));
screen.addEventListener("contextmenu", event => event.preventDefault());
viewBtn.addEventListener("click", () => requestAccess("view"));
controlBtn.addEventListener("click", () => requestAccess("control"));
</script>
</body>
</html>"""


class JobsRemoteHostApp:
    """Tkinter 桌面窗口。"""

    def __init__(self, config: AppConfig) -> None:
        self.config = config
        self.ui_queue: queue.Queue[tuple[str, Any]] = queue.Queue()
        self.log = LogSink(self.ui_queue)
        self.registry = SessionRegistry(config.invite_code, self.ui_queue, self.log)
        self.capture = ScreenCaptureService(config.frame_max_width, config.jpeg_quality)
        self.input_controller = InputController()
        self.host_server = HostServer(config, self.registry, self.capture, self.input_controller, self.log)
        self.tunnel = QuickTunnelService(self.log, self.ui_queue)
        self.root: Any | None = None
        self.port_var: Any | None = None
        self.status_var: Any | None = None
        self.permission_var: Any | None = None
        self.local_urls_text: Any | None = None
        self.public_url_var: Any | None = None
        self.log_text: Any | None = None
        self.start_button: Any | None = None
        self.stop_button: Any | None = None
        self.tray_icon: Any | None = None
        self._quitting = False

    def run(self) -> None:
        """运行 GUI 主循环。"""

        import tkinter as tk
        from tkinter import scrolledtext, ttk

        self.root = tk.Tk()
        self.root.title(APP_NAME)
        self.root.minsize(900, 760)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self.root.bind("<Unmap>", self._on_window_unmap, add="+")
        self._setup_window_icon()
        self._setup_system_tray()

        self.status_var = tk.StringVar(value=f"服务未开启，邀请码：{self.config.invite_code}")
        self.permission_var = tk.StringVar(value=self._permission_status_text())
        self.port_var = tk.StringVar(value=str(self.config.port))
        self.public_url_var = tk.StringVar(value="服务开启后自动准备")

        main = ttk.Frame(self.root, padding=(18, 18, 18, 18))
        main.grid(row=0, column=0, sticky="nsew")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        for row in (2, 3, 4):
            main.rowconfigure(row, weight=1)
        main.columnconfigure(0, weight=1)

        title = ttk.Label(main, text=APP_NAME, font=("", 28, "bold"))
        title.grid(row=0, column=0, pady=(0, 8), sticky="ew")
        title.configure(anchor="center")
        ttk.Label(
            main,
            text="推荐用免安装公网链接：朋友只用浏览器访问，本机先弹授权窗口。",
            font=("", 15),
            foreground="#777777",
            anchor="center",
        ).grid(row=1, column=0, pady=(0, 16), sticky="ew")

        control_box = ttk.LabelFrame(main, text="服务控制", padding=(16, 14))
        control_box.grid(row=2, column=0, sticky="ew", pady=(0, 14))
        control_box.columnconfigure(1, weight=1)
        ttk.Label(control_box, text="监听端口", font=("", 13, "bold")).grid(row=0, column=0, padx=(0, 10), sticky="w")
        ttk.Entry(control_box, textvariable=self.port_var, font=("", 14)).grid(row=0, column=1, sticky="ew")
        button_bar = ttk.Frame(control_box)
        button_bar.grid(row=1, column=0, columnspan=2, pady=(14, 0))
        self.start_button = ttk.Button(button_bar, text="开启服务", command=self.start_service)
        self.start_button.grid(row=0, column=0, padx=6)
        self.stop_button = ttk.Button(button_bar, text="停止服务", command=self.stop_service, state="disabled")
        self.stop_button.grid(row=0, column=1, padx=6)
        ttk.Button(button_bar, text="权限说明", command=self.show_permission_help).grid(row=0, column=2, padx=6)
        ttk.Label(control_box, textvariable=self.status_var, anchor="center").grid(row=2, column=0, columnspan=2, pady=(14, 0), sticky="ew")
        ttk.Label(control_box, textvariable=self.permission_var, anchor="center").grid(row=3, column=0, columnspan=2, pady=(6, 0), sticky="ew")

        link_box = ttk.LabelFrame(main, text="连接地址", padding=(16, 14))
        link_box.grid(row=3, column=0, sticky="nsew", pady=(0, 14))
        link_box.columnconfigure(0, weight=1)
        ttk.Label(link_box, text="内网地址", font=("", 13, "bold"), anchor="center").grid(row=0, column=0, sticky="ew")
        self.local_urls_text = scrolledtext.ScrolledText(link_box, height=5, wrap="word", font=("Menlo", 13))
        self.local_urls_text.grid(row=1, column=0, sticky="ew", pady=(8, 14))
        self.local_urls_text.configure(state="disabled")
        ttk.Label(link_box, text="免安装公网链接（推荐）", font=("", 13, "bold"), anchor="center").grid(row=2, column=0, sticky="ew")
        public_entry = ttk.Entry(link_box, textvariable=self.public_url_var, font=("Menlo", 13), justify="center")
        public_entry.grid(row=3, column=0, sticky="ew", pady=(8, 0))

        log_box = ttk.LabelFrame(main, text="日志", padding=(0, 0))
        log_box.grid(row=4, column=0, sticky="nsew")
        log_box.rowconfigure(0, weight=1)
        log_box.columnconfigure(0, weight=1)
        self.log_text = scrolledtext.ScrolledText(log_box, height=10, wrap="word", font=("Menlo", 12))
        self.log_text.grid(row=0, column=0, sticky="nsew")
        self._install_log_context_menu()
        self._refresh_local_urls()
        self._poll_ui_queue()
        self.log.write("窗口已启动")
        self.root.mainloop()

    def _setup_window_icon(self) -> None:
        """为 Tk 窗口设置与菜单栏一致的图标。"""

        if self.root is None:
            return
        try:
            import tkinter as tk

            self._window_icon = tk.PhotoImage(file=str(resource_path("icon.png")))
            self.root.iconphoto(True, self._window_icon)
        except Exception as exc:
            self.log.write(f"窗口图标加载失败，继续使用系统默认图标：{exc}")

    def _setup_system_tray(self) -> None:
        """创建 macOS 顶部菜单栏 / Windows 通知区域图标。"""

        try:
            import pystray
            from PIL import Image

            image = Image.open(resource_path("icon.png")).convert("RGBA")
            menu = pystray.Menu(
                pystray.MenuItem("显示 JobsRemoteHost", self._tray_restore),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("停止服务并退出 JobsRemoteHost", self._tray_quit),
            )
            self.tray_icon = pystray.Icon(APP_NAME, image, APP_NAME, menu)
            self.tray_icon.run_detached()
        except Exception as exc:
            self.tray_icon = None
            self.log.write(f"顶部菜单栏图标不可用，继续使用普通窗口模式：{exc}")

    def _on_window_unmap(self, _event: Any) -> None:
        """黄色最小化按钮触发后，把窗口隐藏到顶部菜单栏。"""

        if self.root is not None:
            self.root.after_idle(self._hide_to_system_tray_if_minimized)

    def _hide_to_system_tray_if_minimized(self) -> None:
        if self.root is None or self.tray_icon is None or self._quitting:
            return
        if self.root.state() == "iconic":
            self.root.withdraw()

    def _tray_restore(self, _icon: Any = None, _item: Any = None) -> None:
        if self.root is not None:
            self.root.after(0, self._restore_from_system_tray)

    def _restore_from_system_tray(self) -> None:
        if self.root is None:
            return
        self.root.deiconify()
        self.root.lift()
        self.root.focus_force()

    def _tray_quit(self, _icon: Any = None, _item: Any = None) -> None:
        if self.root is not None:
            self.root.after(0, self._quit_application)

    def _quit_application(self) -> None:
        if self._quitting:
            return
        self._quitting = True
        self.stop_service()
        if self.tray_icon is not None:
            self.tray_icon.stop()
            self.tray_icon = None
        if self.root is not None:
            self.root.destroy()

    def start_service(self) -> None:
        """响应开启服务按钮。"""

        assert self.port_var is not None
        try:
            self.config.port = int(self.port_var.get().strip())
            if not (1 <= self.config.port <= 65535):
                raise ValueError
        except ValueError:
            self.log.write("端口必须是 1-65535 的整数")
            return
        try:
            self.host_server.start()
        except OSError as exc:
            self.log.write(f"开启服务失败：{exc}")
            return
        self._set_running_ui(True)
        self._refresh_local_urls()
        if self.config.start_tunnel:
            self.tunnel.start(self.config.port, self.config.invite_code)

    def stop_service(self) -> None:
        """响应停止服务按钮。"""

        self.tunnel.stop()
        self.host_server.stop()
        self._set_running_ui(False)
        self._set_status(f"服务未开启，邀请码：{self.config.invite_code}")
        if self.public_url_var is not None:
            self.public_url_var.set("服务开启后自动准备")

    def show_permission_help(self) -> None:
        """展示权限说明。"""

        from tkinter import messagebox

        messagebox.showinfo(
            "权限说明",
            "Windows 通常可直接采集与控制。\n\n"
            "macOS 运行打包版时，若系统拦截屏幕录制或辅助功能，请到：\n"
            "系统设置 -> 隐私与安全性 -> 屏幕录制 / 辅助功能，给 JobsRemoteHost 授权。\n\n"
            "无论在哪个平台，浏览器访问都必须经过本机弹窗确认。",
        )

    def _poll_ui_queue(self) -> None:
        """定时消费后台线程事件。"""

        while True:
            try:
                kind, payload = self.ui_queue.get_nowait()
            except queue.Empty:
                break
            if kind == "log":
                self._append_log(str(payload))
            elif kind == "access_request":
                self._show_access_dialog(payload)
            elif kind == "tunnel_url" and self.public_url_var is not None:
                self.public_url_var.set(str(payload))
            elif kind == "tunnel_error" and self.public_url_var is not None:
                self.public_url_var.set(str(payload))
        self.registry.cleanup()
        if self.root is not None:
            self.root.after(250, self._poll_ui_queue)

    def _show_access_dialog(self, request: AccessRequest) -> None:
        """弹出本机授权窗口。"""

        import tkinter as tk
        from tkinter import ttk

        if self.root is None:
            self.registry.resolve(request.session_id, "deny")
            return
        dialog = tk.Toplevel(self.root)
        dialog.title("远程访问请求")
        dialog.transient(self.root)
        dialog.grab_set()
        dialog.resizable(False, False)
        frame = ttk.Frame(dialog, padding=18)
        frame.grid(row=0, column=0, sticky="nsew")
        mode_text = "控制电脑" if request.mode == "control" else "观看屏幕"
        ttk.Label(frame, text="收到浏览器访问请求", font=("", 16, "bold")).grid(row=0, column=0, columnspan=3, sticky="w")
        ttk.Label(frame, text=f"来源：{request.remote_addr}\n请求：{mode_text}\n\n确认后才会开始传输画面。").grid(
            row=1,
            column=0,
            columnspan=3,
            pady=(10, 16),
            sticky="w",
        )

        def resolve(mode: str) -> None:
            self.registry.resolve(request.session_id, mode)
            dialog.destroy()

        if request.mode == "control":
            ttk.Button(frame, text="允许控制", command=lambda: resolve("control")).grid(row=2, column=0, padx=(0, 8))
            ttk.Button(frame, text="仅允许观看", command=lambda: resolve("view")).grid(row=2, column=1, padx=(0, 8))
            ttk.Button(frame, text="拒绝", command=lambda: resolve("deny")).grid(row=2, column=2)
        else:
            ttk.Button(frame, text="允许观看", command=lambda: resolve("view")).grid(row=2, column=0, padx=(0, 8))
            ttk.Button(frame, text="拒绝", command=lambda: resolve("deny")).grid(row=2, column=1, padx=(0, 8))
        dialog.protocol("WM_DELETE_WINDOW", lambda: resolve("deny"))
        self._center_dialog(dialog)

    def _center_dialog(self, dialog: Any) -> None:
        """把授权弹窗居中到主窗口附近。"""

        dialog.update_idletasks()
        width = dialog.winfo_width()
        height = dialog.winfo_height()
        root_x = self.root.winfo_rootx() if self.root is not None else 100
        root_y = self.root.winfo_rooty() if self.root is not None else 100
        root_w = self.root.winfo_width() if self.root is not None else 900
        root_h = self.root.winfo_height() if self.root is not None else 760
        x = root_x + max(0, (root_w - width) // 2)
        y = root_y + max(0, (root_h - height) // 2)
        dialog.geometry(f"+{x}+{y}")

    def _install_log_context_menu(self) -> None:
        """给日志框安装右键菜单。"""

        import tkinter as tk

        if self.log_text is None:
            return
        menu = tk.Menu(self.log_text, tearoff=False)
        menu.add_command(label="复制", command=lambda: self.log_text.event_generate("<<Copy>>"))
        menu.add_command(label="全选", command=self._select_all_logs)
        menu.add_separator()
        menu.add_command(label="清除日志", command=self._clear_logs)

        def popup(event: Any) -> None:
            menu.tk_popup(event.x_root, event.y_root)

        self.log_text.bind("<Button-3>", popup)
        self.log_text.bind("<Control-Button-1>", popup)

    def _select_all_logs(self) -> None:
        """选中日志框全部文字。"""

        if self.log_text is None:
            return
        self.log_text.tag_add("sel", "1.0", "end")
        self.log_text.mark_set("insert", "1.0")
        self.log_text.see("insert")

    def _clear_logs(self) -> None:
        """清空窗口日志。"""

        if self.log_text is None:
            return
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="normal")

    def _append_log(self, line: str) -> None:
        """追加一行窗口日志。"""

        if self.log_text is None:
            return
        self.log_text.configure(state="normal")
        self.log_text.insert("end", line + "\n")
        self.log_text.see("end")
        self.log_text.configure(state="normal")

    def _refresh_local_urls(self) -> None:
        """刷新本机内网地址显示。"""

        if self.local_urls_text is None:
            return
        urls = NetworkAddressService.local_http_urls(self.config.port, self.config.invite_code)
        self.local_urls_text.configure(state="normal")
        self.local_urls_text.delete("1.0", "end")
        self.local_urls_text.insert("end", "\n".join(urls))
        self.local_urls_text.configure(state="disabled")

    def _set_running_ui(self, running: bool) -> None:
        """切换服务按钮状态。"""

        if self.start_button is not None:
            self.start_button.configure(state="disabled" if running else "normal")
        if self.stop_button is not None:
            self.stop_button.configure(state="normal" if running else "disabled")
        self._set_status(f"服务已开启，邀请码：{self.config.invite_code}" if running else f"服务未开启，邀请码：{self.config.invite_code}")

    def _set_status(self, text: str) -> None:
        """更新顶部服务状态。"""

        if self.status_var is not None:
            self.status_var.set(text)

    def _permission_status_text(self) -> str:
        """返回权限提示文案。"""

        if sys.platform == "darwin":
            return "屏幕录制 / 辅助功能：请在系统设置里给打包后的 App 授权"
        if os.name == "nt":
            return "Windows：通常不需要额外系统授权；仍需本机弹窗确认浏览器访问"
        return "Linux：需要桌面环境允许截图与输入注入"

    def _on_close(self) -> None:
        """关闭窗口前停止后台服务。"""

        self._quit_application()


def run_self_test() -> int:
    """执行不依赖 GUI 和第三方库的基础协议自检。"""

    event_queue: queue.Queue[tuple[str, Any]] = queue.Queue()
    config = AppConfig(port=0, bind_host="127.0.0.1", invite_code="TEST42", start_tunnel=False)
    log = LogSink(None)
    registry = SessionRegistry(config.invite_code, event_queue, log)
    capture = SelfTestCaptureService()
    input_controller = SelfTestInputController()
    server = HostServer(config, registry, capture, input_controller, log)
    server.start()
    base = f"http://127.0.0.1:{server.bound_port}"
    try:
        bad_status = _self_test_request_status(base, {"invite": "BAD", "mode": "view"})
        if bad_status != 403:
            raise AssertionError(f"错误邀请码应返回 403，实际 {bad_status}")
        payload = _self_test_post_json(base + "/api/request", {"invite": "TEST42", "mode": "control"})
        session = str(payload["session"])
        kind, request = event_queue.get(timeout=2)
        if kind != "access_request" or request.session_id != session:
            raise AssertionError("授权请求未进入本机队列")
        registry.resolve(session, "control")
        status = _self_test_get_json(base + f"/api/status?session={urllib.parse.quote(session)}")
        if not status.get("canControl"):
            raise AssertionError("授权控制状态错误")
        frame_status, frame_content_type = _self_test_get_status_and_content_type(base + f"/api/frame?session={urllib.parse.quote(session)}")
        if frame_status != 200 or "image/jpeg" not in frame_content_type:
            raise AssertionError("授权后帧接口未返回 JPEG")
        _self_test_post_json(
            base + "/api/control",
            {"session": session, "event": {"type": "mouseMove", "x": 1, "y": 1}},
        )
        if not input_controller.events:
            raise AssertionError("控制事件未写入输入控制器")
    finally:
        server.stop()
    print("SELF_TEST_OK")
    return 0


def _self_test_request_status(base: str, payload: dict[str, Any]) -> int:
    """自检：返回 POST /api/request 的 HTTP 状态码。"""

    request = urllib.request.Request(
        base + "/api/request",
        data=json_bytes(payload),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(request, timeout=3).read()
    except urllib.error.HTTPError as exc:
        return exc.code
    return 200


def _self_test_post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    """自检：POST JSON 并解析响应。"""

    request = urllib.request.Request(
        url,
        data=json_bytes(payload),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=3) as response:
        return json.loads(response.read().decode("utf-8"))


def _self_test_get_json(url: str) -> dict[str, Any]:
    """自检：GET JSON 并解析响应。"""

    with urllib.request.urlopen(url, timeout=3) as response:
        return json.loads(response.read().decode("utf-8"))


def _self_test_get_status_and_content_type(url: str) -> tuple[int, str]:
    """自检：GET 并读取状态码和 Content-Type。"""

    with urllib.request.urlopen(url, timeout=3) as response:
        response.read()
        return int(response.status), str(response.headers.get("Content-Type") or "")


def build_parser() -> argparse.ArgumentParser:
    """构建命令行参数解析器。"""

    parser = argparse.ArgumentParser(description="JobsRemoteHost Python 被控端")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="启动 GUI 时默认监听端口")
    parser.add_argument("--no-tunnel", action="store_true", help="启动 GUI 后不自动准备 cloudflared 公网链接")
    parser.add_argument("--self-test", action="store_true", help="执行协议自检后退出")
    return parser


def ensure_python_version() -> None:
    """检查 Python 版本。"""

    if sys.version_info < MIN_PYTHON:
        version_text = ".".join(str(item) for item in MIN_PYTHON)
        raise SystemExit(f"{APP_NAME} 需要 Python {version_text}+")


def main(argv: list[str] | None = None) -> int:
    """命令行入口。"""

    ensure_python_version()
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.self_test:
        return run_self_test()
    config = AppConfig(port=args.port, invite_code=generate_invite_code(), start_tunnel=not args.no_tunnel)
    app = JobsRemoteHostApp(config)
    try:
        app.run()
    except KeyboardInterrupt:
        return 130
    except Exception:
        error_path = log_file_path()
        with error_path.open("a", encoding="utf-8") as stream:
            stream.write(traceback.format_exc() + "\n")
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
