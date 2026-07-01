#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const http = require("http");
const { URL } = require("url");

const port = Number(process.env.PORT || 8787);
const sessions = new Map();

function jsonResponse(response, statusCode, payload) {
  const body = Buffer.from(JSON.stringify(payload));
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": body.length,
    "Cache-Control": "no-store"
  });
  response.end(body);
}

function htmlResponse(response, body) {
  const data = Buffer.from(body);
  response.writeHead(200, {
    "Content-Type": "text/html; charset=utf-8",
    "Content-Length": data.length,
    "Cache-Control": "no-store"
  });
  response.end(data);
}

function readRequestBody(request, completion) {
  const chunks = [];
  let size = 0;
  request.on("data", chunk => {
    size += chunk.length;
    if (size > 1024 * 1024) {
      request.destroy();
      return;
    }
    chunks.push(chunk);
  });
  request.on("end", () => {
    completion(Buffer.concat(chunks).toString("utf8"));
  });
}

function publicBaseURL(request) {
  const forwardedProto = String(request.headers["x-forwarded-proto"] || "").split(",")[0].trim();
  const proto = forwardedProto || (request.socket.encrypted ? "https" : "http");
  return `${proto}://${request.headers.host}`;
}

function sanitizeSession(value) {
  return String(value || "").trim().replace(/[^A-Za-z0-9_-]/g, "").slice(0, 64);
}

function getSession(sessionID) {
  let session = sessions.get(sessionID);
  if (!session) {
    session = {
      id: sessionID,
      host: null,
      hostInfo: null,
      viewers: new Map(),
      updatedAt: Date.now()
    };
    sessions.set(sessionID, session);
  }
  session.updatedAt = Date.now();
  return session;
}

function cleanupSession(session) {
  if (!session.host && session.viewers.size === 0) {
    sessions.delete(session.id);
  }
}

function parseJSON(text) {
  try {
    const value = JSON.parse(text);
    return value && typeof value === "object" ? value : null;
  } catch (_) {
    return null;
  }
}

function titleForAuthorization(value) {
  switch (value) {
    case "viewing":
      return "已允许观看";
    case "controlling":
      return "已允许控制";
    case "denied":
      return "已拒绝";
    default:
      return "等待授权";
  }
}

class WebSocketConnection {
  constructor(socket) {
    this.socket = socket;
    this.buffer = Buffer.alloc(0);
    this.closed = false;
    this.fragments = [];
    this.fragmentOpcode = 0;
    this.onText = null;
    this.onClose = null;
    socket.on("data", chunk => this.receive(chunk));
    socket.on("close", () => this.closeSilently());
    socket.on("error", () => this.closeSilently());
  }

  sendJSON(payload) {
    this.sendText(JSON.stringify(payload));
  }

  sendText(text) {
    if (this.closed || this.socket.destroyed) {
      return;
    }
    const payload = Buffer.from(text, "utf8");
    const header = this.frameHeader(0x1, payload.length);
    this.socket.write(Buffer.concat([header, payload]));
  }

  close() {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      this.socket.end(Buffer.from([0x88, 0x00]));
    } catch (_) {
      this.socket.destroy();
    }
  }

  receive(chunk) {
    if (this.closed) {
      return;
    }
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.buffer.length >= 2) {
      const first = this.buffer[0];
      const second = this.buffer[1];
      const fin = (first & 0x80) !== 0;
      const opcode = first & 0x0f;
      const masked = (second & 0x80) !== 0;
      let length = second & 0x7f;
      let offset = 2;

      if (length === 126) {
        if (this.buffer.length < offset + 2) {
          return;
        }
        length = this.buffer.readUInt16BE(offset);
        offset += 2;
      } else if (length === 127) {
        if (this.buffer.length < offset + 8) {
          return;
        }
        const high = this.buffer.readUInt32BE(offset);
        const low = this.buffer.readUInt32BE(offset + 4);
        if (high !== 0 || low > 16 * 1024 * 1024) {
          this.close();
          return;
        }
        length = low;
        offset += 8;
      }

      if (!masked || this.buffer.length < offset + 4 + length) {
        return;
      }

      const mask = this.buffer.subarray(offset, offset + 4);
      offset += 4;
      const payload = Buffer.from(this.buffer.subarray(offset, offset + length));
      this.buffer = this.buffer.subarray(offset + length);

      for (let index = 0; index < payload.length; index += 1) {
        payload[index] ^= mask[index % 4];
      }

      if (opcode === 0x8) {
        this.close();
        return;
      }
      if (opcode === 0x9) {
        this.sendPong(payload);
        continue;
      }
      if (opcode === 0x1 || opcode === 0x0) {
        this.handleTextFrame(opcode, fin, payload);
      }
    }
  }

  handleTextFrame(opcode, fin, payload) {
    if (opcode === 0x1 && fin) {
      this.onText?.(payload.toString("utf8"));
      return;
    }
    if (opcode === 0x1) {
      this.fragmentOpcode = opcode;
      this.fragments = [payload];
      return;
    }
    if (opcode === 0x0 && this.fragmentOpcode === 0x1) {
      this.fragments.push(payload);
      if (fin) {
        const text = Buffer.concat(this.fragments).toString("utf8");
        this.fragments = [];
        this.fragmentOpcode = 0;
        this.onText?.(text);
      }
    }
  }

  sendPong(payload) {
    if (this.closed || this.socket.destroyed) {
      return;
    }
    this.socket.write(Buffer.concat([this.frameHeader(0xA, payload.length), payload]));
  }

  frameHeader(opcode, length) {
    if (length < 126) {
      return Buffer.from([0x80 | opcode, length]);
    }
    if (length <= 0xffff) {
      const header = Buffer.alloc(4);
      header[0] = 0x80 | opcode;
      header[1] = 126;
      header.writeUInt16BE(length, 2);
      return header;
    }
    const header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeUInt32BE(0, 2);
    header.writeUInt32BE(length, 6);
    return header;
  }

  closeSilently() {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.onClose?.();
  }
}

function handleRegister(request, response) {
  readRequestBody(request, body => {
    const payload = parseJSON(body) || {};
    const inviteCode = sanitizeSession(payload.inviteCode);
    if (!inviteCode) {
      jsonResponse(response, 400, { ok: false, message: "inviteCode 不能为空" });
      return;
    }
    const session = getSession(inviteCode);
    session.hostInfo = {
      localURLs: Array.isArray(payload.localURLs) ? payload.localURLs.slice(0, 8) : [],
      publicDirectURL: String(payload.publicDirectURL || ""),
      capabilities: Array.isArray(payload.capabilities) ? payload.capabilities : [],
      registeredAt: Date.now()
    };
    jsonResponse(response, 200, {
      ok: true,
      sessionURL: `${publicBaseURL(request)}/s/${inviteCode}`
    });
  });
}

function handleHTTP(request, response) {
  const url = new URL(request.url, publicBaseURL(request));
  if (request.method === "GET" && url.pathname === "/") {
    htmlResponse(response, landingPage());
    return;
  }
  if (request.method === "GET" && url.pathname === "/health") {
    jsonResponse(response, 200, { ok: true, sessions: sessions.size });
    return;
  }
  if (request.method === "POST" && url.pathname === "/api/hosts/register") {
    handleRegister(request, response);
    return;
  }
  const match = url.pathname.match(/^\/s\/([A-Za-z0-9_-]+)$/);
  if (request.method === "GET" && match) {
    htmlResponse(response, viewerPage(match[1]));
    return;
  }
  jsonResponse(response, 404, { ok: false, message: "没有这个页面" });
}

function handleUpgrade(request, socket) {
  const url = new URL(request.url, publicBaseURL(request));
  if (url.pathname !== "/ws") {
    socket.destroy();
    return;
  }
  const key = request.headers["sec-websocket-key"];
  const role = url.searchParams.get("role");
  const sessionID = sanitizeSession(url.searchParams.get("session"));
  if (!key || !sessionID || (role !== "host" && role !== "viewer")) {
    socket.destroy();
    return;
  }
  const accept = crypto
    .createHash("sha1")
    .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
    .digest("base64");
  socket.write([
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    `Sec-WebSocket-Accept: ${accept}`,
    "",
    ""
  ].join("\r\n"));

  const ws = new WebSocketConnection(socket);
  if (role === "host") {
    attachHost(sessionID, ws, request);
  } else {
    attachViewer(sessionID, ws, request);
  }
}

function attachHost(sessionID, ws, request) {
  const session = getSession(sessionID);
  if (session.host && !session.host.closed) {
    session.host.close();
  }
  session.host = ws;
  session.updatedAt = Date.now();
  ws.sendJSON({ type: "relay:ready", session: sessionID });
  console.log(`[relay] host connected: ${sessionID} from ${request.socket.remoteAddress}`);

  ws.onText = text => {
    const message = parseJSON(text);
    if (!message || !message.type) {
      return;
    }
    if (message.type === "host:hello") {
      ws.sendJSON({ type: "relay:ready", session: sessionID });
    } else if (message.type === "auth") {
      handleHostAuth(session, message);
    } else if (message.type === "frame") {
      relayFrame(session, message);
    }
  };
  ws.onClose = () => {
    if (session.host === ws) {
      session.host = null;
      for (const viewer of session.viewers.values()) {
        viewer.ws.sendJSON({ type: "host:offline", message: "主机已离线" });
      }
      console.log(`[relay] host disconnected: ${sessionID}`);
      cleanupSession(session);
    }
  };
}

function handleHostAuth(session, message) {
  const viewer = session.viewers.get(String(message.viewerID || ""));
  if (!viewer) {
    return;
  }
  const authorization = String(message.authorization || "denied");
  viewer.authorization = authorization;
  viewer.ws.sendJSON({
    type: "auth",
    viewerID: viewer.id,
    authorization,
    title: message.title || titleForAuthorization(authorization)
  });
}

function relayFrame(session, message) {
  if (!message.data) {
    return;
  }
  const frameMessage = {
    type: "frame",
    mime: message.mime || "image/jpeg",
    data: message.data
  };
  for (const viewer of session.viewers.values()) {
    if (viewer.authorization === "viewing" || viewer.authorization === "controlling") {
      viewer.ws.sendJSON(frameMessage);
    }
  }
}

function attachViewer(sessionID, ws, request) {
  const session = getSession(sessionID);
  const viewerID = crypto.randomBytes(8).toString("hex");
  const viewer = {
    id: viewerID,
    ws,
    authorization: "pending",
    remoteAddress: request.socket.remoteAddress || "unknown",
    displayName: "浏览器访客",
    mode: "view",
    connectedAt: Date.now()
  };
  session.viewers.set(viewerID, viewer);
  session.updatedAt = Date.now();
  ws.sendJSON({ type: "viewer:ready", viewerID, hostOnline: Boolean(session.host) });
  console.log(`[relay] viewer connected: ${sessionID}/${viewerID} from ${viewer.remoteAddress}`);

  ws.onText = text => {
    const message = parseJSON(text);
    if (!message || !message.type) {
      return;
    }
    if (message.type === "viewer:request") {
      handleViewerRequest(session, viewer, message, request);
    } else if (message.type === "control") {
      handleViewerControl(session, viewer, message);
    }
  };
  ws.onClose = () => {
    session.viewers.delete(viewerID);
    if (session.host && !session.host.closed) {
      session.host.sendJSON({ type: "viewer:disconnect", viewerID });
    }
    console.log(`[relay] viewer disconnected: ${sessionID}/${viewerID}`);
    cleanupSession(session);
  };
}

function handleViewerRequest(session, viewer, message, request) {
  viewer.displayName = String(message.displayName || "浏览器访客").trim() || "浏览器访客";
  viewer.mode = message.mode === "control" ? "control" : "view";
  viewer.authorization = "pending";
  if (!session.host || session.host.closed) {
    viewer.ws.sendJSON({ type: "host:offline", message: "主机未连接公网会话服务" });
    return;
  }
  session.host.sendJSON({
    type: "viewer:request",
    viewerID: viewer.id,
    displayName: viewer.displayName,
    mode: viewer.mode,
    remoteAddress: viewer.remoteAddress,
    entryHost: message.entryHost || request.headers.host || "relay"
  });
}

function handleViewerControl(session, viewer, message) {
  if (viewer.authorization !== "controlling" || !session.host || session.host.closed) {
    return;
  }
  const payload = message.payload && typeof message.payload === "object" ? message.payload : {};
  session.host.sendJSON({
    type: "control",
    viewerID: viewer.id,
    payload
  });
}

function landingPage() {
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>JobsRemoteHost Relay</title>
  <style>
    body { margin:0; min-height:100vh; display:grid; place-items:center; background:#10131a; color:#f5f7fb; font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
    main { width:min(760px, calc(100vw - 32px)); border:1px solid #303746; border-radius:8px; padding:24px; background:#1a1f29; }
    code { background:#101620; border:1px solid #303746; border-radius:6px; padding:2px 6px; }
  </style>
</head>
<body>
  <main>
    <h1>JobsRemoteHost Relay</h1>
    <p>服务已运行。Mac 端在“公网会话服务 Base URL”里填写当前站点地址，开启服务后会生成 <code>/s/邀请码</code> 公网会话链接。</p>
    <p>健康检查：<code>/health</code></p>
  </main>
</body>
</html>`;
}

function viewerPage(sessionID) {
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>JobsRemoteHost</title>
  <style>
    :root { color-scheme: dark; --bg:#10131a; --panel:#1a1f29; --text:#f5f7fb; --muted:#aab2c0; --line:#303746; --accent:#3ddc97; }
    * { box-sizing:border-box; }
    body { margin:0; min-height:100vh; background:var(--bg); color:var(--text); font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
    header { display:flex; align-items:center; justify-content:space-between; gap:16px; padding:14px 18px; border-bottom:1px solid var(--line); background:#151922; }
    h1 { margin:0; font-size:18px; letter-spacing:0; }
    main { display:grid; grid-template-columns:minmax(300px, 360px) 1fr; gap:16px; padding:16px; }
    section { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px; }
    label { display:block; color:var(--muted); font-size:13px; margin:10px 0 6px; }
    input, select, button { width:100%; border-radius:7px; border:1px solid var(--line); background:#111620; color:var(--text); padding:10px 11px; font:inherit; }
    button { cursor:pointer; background:#243143; }
    button.primary { margin-top:12px; background:var(--accent); border-color:var(--accent); color:#06110c; font-weight:700; }
    button.secondary { margin-top:8px; }
    button:disabled { opacity:.55; cursor:not-allowed; }
    .status { color:var(--muted); min-height:24px; word-break:break-word; }
    .screenWrap { min-height:calc(100vh - 96px); display:flex; align-items:center; justify-content:center; overflow:hidden; }
    img { max-width:100%; max-height:calc(100vh - 128px); object-fit:contain; border-radius:8px; border:1px solid var(--line); background:#05070a; cursor:crosshair; user-select:none; }
    .hint { color:var(--muted); font-size:13px; margin-top:10px; }
    .pill { display:inline-flex; align-items:center; min-height:30px; padding:5px 9px; border-radius:999px; background:#101620; border:1px solid var(--line); color:var(--muted); }
    @media (max-width: 860px) {
      main { grid-template-columns:1fr; }
      .screenWrap { min-height:52vh; }
      img { max-height:58vh; }
    }
  </style>
</head>
<body>
  <header>
    <h1>JobsRemoteHost</h1>
    <span class="pill" id="modePill">连接中</span>
  </header>
  <main>
    <section>
      <div class="status" id="status">正在连接公网会话服务。</div>
      <label for="nameInput">访问者名称</label>
      <input id="nameInput" autocomplete="name" placeholder="例如：朋友A">
      <label for="modeSelect">请求权限</label>
      <select id="modeSelect">
        <option value="view">仅观看</option>
        <option value="control">观看并控制</option>
      </select>
      <button class="primary" id="requestButton" disabled>请求授权</button>
      <button class="secondary" id="disconnectButton" disabled>断开本次会话</button>
      <p class="hint">主机端同意之前，浏览器不会看到屏幕。允许控制后，鼠标、滚轮和常用键盘会发送到主机。</p>
    </section>
    <section class="screenWrap">
      <img id="screen" alt="等待主机授权后显示屏幕" draggable="false" tabindex="0">
    </section>
  </main>
  <script>
    const SESSION_ID = ${JSON.stringify(sessionID)};
    const statusEl = document.getElementById("status");
    const modePill = document.getElementById("modePill");
    const imageEl = document.getElementById("screen");
    const requestButton = document.getElementById("requestButton");
    const disconnectButton = document.getElementById("disconnectButton");
    let socket = null;
    let viewerID = "";
    let authorization = "pending";
    let lastMoveAt = 0;

    function wsURL() {
      const protocol = location.protocol === "https:" ? "wss:" : "ws:";
      return protocol + "//" + location.host + "/ws?role=viewer&session=" + encodeURIComponent(SESSION_ID);
    }

    function setStatus(text, pill) {
      statusEl.textContent = text;
      modePill.textContent = pill || text;
    }

    function send(payload) {
      if (!socket || socket.readyState !== WebSocket.OPEN) return;
      socket.send(JSON.stringify(payload));
    }

    function connect() {
      socket = new WebSocket(wsURL());
      socket.addEventListener("open", () => {
        setStatus("已连接公网会话服务，请请求主机授权。", "未授权");
        requestButton.disabled = false;
      });
      socket.addEventListener("message", event => {
        let message = null;
        try { message = JSON.parse(event.data); } catch (_) { return; }
        handleMessage(message);
      });
      socket.addEventListener("close", () => {
        requestButton.disabled = true;
        disconnectButton.disabled = true;
        setStatus("公网会话已断开，请刷新页面重试。", "已断开");
      });
      socket.addEventListener("error", () => {
        setStatus("公网会话连接失败，请确认主机已开启服务。", "连接失败");
      });
    }

    function handleMessage(message) {
      if (message.type === "viewer:ready") {
        viewerID = message.viewerID || "";
        if (!message.hostOnline) {
          setStatus("主机暂未连接公网会话服务。", "主机离线");
        }
      } else if (message.type === "auth") {
        authorization = message.authorization || "denied";
        if (authorization === "denied") {
          setStatus("主机端已拒绝本次访问。", "已拒绝");
          requestButton.disabled = false;
          disconnectButton.disabled = true;
        } else if (authorization === "controlling") {
          setStatus("主机端已允许控制。", "可控制");
          disconnectButton.disabled = false;
        } else if (authorization === "viewing") {
          setStatus("主机端已允许观看。", "可观看");
          disconnectButton.disabled = false;
        }
      } else if (message.type === "frame" && message.data) {
        imageEl.src = "data:" + (message.mime || "image/jpeg") + ";base64," + message.data;
      } else if (message.type === "host:offline") {
        setStatus(message.message || "主机已离线。", "主机离线");
      }
    }

    function requestAccess() {
      const displayName = document.getElementById("nameInput").value.trim() || "浏览器访客";
      const mode = document.getElementById("modeSelect").value;
      requestButton.disabled = true;
      disconnectButton.disabled = false;
      authorization = "pending";
      setStatus("已发送请求，等待主机端授权。", "等待授权");
      send({
        type: "viewer:request",
        displayName,
        mode,
        entryHost: location.host
      });
    }

    function clamp(value) {
      return Math.max(0, Math.min(1, value));
    }

    function pointerPayload(event) {
      const rect = imageEl.getBoundingClientRect();
      return {
        nx: clamp((event.clientX - rect.left) / Math.max(rect.width, 1)),
        ny: clamp((event.clientY - rect.top) / Math.max(rect.height, 1))
      };
    }

    function sendControl(type, event, extra = {}) {
      if (authorization !== "controlling") return;
      const payload = Object.assign({ type }, extra);
      if (event && "clientX" in event) Object.assign(payload, pointerPayload(event));
      send({ type: "control", payload });
    }

    imageEl.addEventListener("mousemove", event => {
      const now = performance.now();
      if (now - lastMoveAt < 50) return;
      lastMoveAt = now;
      sendControl("mouseMove", event);
    });
    imageEl.addEventListener("mousedown", event => {
      event.preventDefault();
      imageEl.focus();
      sendControl("mouseDown", event, { button: event.button });
    });
    imageEl.addEventListener("mouseup", event => {
      event.preventDefault();
      sendControl("mouseUp", event, { button: event.button });
    });
    imageEl.addEventListener("wheel", event => {
      event.preventDefault();
      sendControl("wheel", event, { deltaX: event.deltaX, deltaY: event.deltaY });
    }, { passive:false });
    document.addEventListener("keydown", event => {
      if (authorization !== "controlling") return;
      event.preventDefault();
      sendControl("keyDown", null, { key: event.key, shift: event.shiftKey, control: event.ctrlKey, option: event.altKey, command: event.metaKey });
    });
    document.addEventListener("keyup", event => {
      if (authorization !== "controlling") return;
      event.preventDefault();
      sendControl("keyUp", null, { key: event.key, shift: event.shiftKey, control: event.ctrlKey, option: event.altKey, command: event.metaKey });
    });
    requestButton.addEventListener("click", requestAccess);
    disconnectButton.addEventListener("click", () => {
      socket?.close();
      imageEl.removeAttribute("src");
      authorization = "pending";
      setStatus("已断开本次浏览器会话。", "已断开");
    });
    connect();
  </script>
</body>
</html>`;
}

const server = http.createServer(handleHTTP);
server.on("upgrade", handleUpgrade);
server.listen(port, "0.0.0.0", () => {
  console.log(`[relay] JobsRemoteHost relay server listening on http://0.0.0.0:${port}`);
});
