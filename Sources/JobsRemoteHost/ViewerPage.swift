//
//  ViewerPage.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Foundation

enum ViewerPage {
    static func html(inviteCode: String) -> String {
        """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>JobsRemoteHost</title>
          <style>
            :root { color-scheme: dark; --bg:#10131a; --panel:#1a1f29; --text:#f5f7fb; --muted:#aab2c0; --line:#303746; --accent:#3ddc97; --danger:#ff6b6b; }
            * { box-sizing: border-box; }
            body { margin:0; min-height:100vh; background:var(--bg); color:var(--text); font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
            header { display:flex; gap:16px; align-items:center; justify-content:space-between; padding:14px 18px; border-bottom:1px solid var(--line); background:#151922; position:sticky; top:0; z-index:2; }
            h1 { margin:0; font-size:18px; letter-spacing:0; }
            main { display:grid; grid-template-columns: minmax(300px, 360px) 1fr; gap:16px; padding:16px; }
            section { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px; }
            label { display:block; color:var(--muted); font-size:13px; margin:10px 0 6px; }
            input, select, button { width:100%; border-radius:7px; border:1px solid var(--line); background:#111620; color:var(--text); padding:10px 11px; font:inherit; }
            button { cursor:pointer; background:#243143; }
            button.primary { background:var(--accent); border-color:var(--accent); color:#06110c; font-weight:700; }
            button.secondary { margin-top:8px; }
            button:disabled { opacity:.55; cursor:not-allowed; }
            .status { color:var(--muted); min-height:24px; word-break:break-word; }
            .screenWrap { min-height:calc(100vh - 96px); display:flex; align-items:center; justify-content:center; overflow:hidden; }
            img { max-width:100%; max-height:calc(100vh - 128px); object-fit:contain; border-radius:8px; border:1px solid var(--line); background:#05070a; cursor:crosshair; user-select:none; }
            .hint { color:var(--muted); font-size:13px; margin-top:10px; }
            .pill { display:inline-flex; align-items:center; gap:8px; padding:5px 9px; border-radius:99px; background:#101620; border:1px solid var(--line); color:var(--muted); }
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
            <span class="pill" id="modePill">未连接</span>
          </header>
          <main>
            <section>
              <div class="status" id="status">请输入名称并请求主机授权。</div>
              <label for="nameInput">访问者名称</label>
              <input id="nameInput" autocomplete="name" placeholder="例如：朋友A">
              <label for="modeSelect">请求权限</label>
              <select id="modeSelect">
                <option value="view">仅观看</option>
                <option value="control">观看并控制</option>
              </select>
              <button class="primary" id="requestButton">请求授权</button>
              <button class="secondary" id="disconnectButton" disabled>断开本次会话</button>
              <p class="hint">主机端同意之前，浏览器不会看到屏幕。允许控制后，鼠标、滚轮和常用键盘会发送到主机。</p>
            </section>
            <section class="screenWrap">
              <img id="screen" alt="等待主机授权后显示屏幕" draggable="false">
            </section>
          </main>
          <script>
            const EXPECTED_INVITE = "\(inviteCode)";
            const params = new URLSearchParams(location.search);
            const invite = params.get("invite") || "";
            const statusEl = document.getElementById("status");
            const modePill = document.getElementById("modePill");
            const imageEl = document.getElementById("screen");
            const requestButton = document.getElementById("requestButton");
            const disconnectButton = document.getElementById("disconnectButton");
            let sessionID = "";
            let authorization = "pending";
            let frameTimer = 0;
            let lastMoveAt = 0;

            function setStatus(text, pill) {
              statusEl.textContent = text;
              modePill.textContent = pill || text;
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

            async function postJSON(path, body) {
              const response = await fetch(path, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(body)
              });
              return await response.json();
            }

            async function requestAccess() {
              if (invite !== EXPECTED_INVITE) {
                setStatus("链接验证码无效，请让主机重新复制当前地址。", "验证码错误");
                return;
              }
              const displayName = document.getElementById("nameInput").value.trim() || "浏览器访客";
              const mode = document.getElementById("modeSelect").value;
              requestButton.disabled = true;
              setStatus("已发送请求，等待主机端授权。", "等待授权");
              const result = await postJSON("/api/request", {
                invite,
                displayName,
                mode,
                entryHost: location.host
              });
              if (!result.ok) {
                setStatus(result.message || "请求失败。", "请求失败");
                requestButton.disabled = false;
                return;
              }
              sessionID = result.sessionID;
              disconnectButton.disabled = false;
              pollStatus();
            }

            async function pollStatus() {
              if (!sessionID) return;
              const response = await fetch(`/api/status?session=${encodeURIComponent(sessionID)}&t=${Date.now()}`);
              const result = await response.json();
              authorization = result.authorization || "pending";
              if (authorization === "pending") {
                setStatus("主机端还未处理授权请求。", "等待授权");
                setTimeout(pollStatus, 1000);
              } else if (authorization === "denied") {
                setStatus("主机端已拒绝本次访问。", "已拒绝");
                requestButton.disabled = false;
                disconnectButton.disabled = true;
              } else {
                const canControl = authorization === "controlling";
                setStatus(canControl ? "主机端已允许控制。" : "主机端已允许观看。", canControl ? "可控制" : "可观看");
                startFrames();
                setTimeout(pollStatus, 3000);
              }
            }

            function startFrames() {
              if (frameTimer) return;
              const loadNext = () => {
                if (!sessionID || (authorization !== "viewing" && authorization !== "controlling")) {
                  frameTimer = 0;
                  return;
                }
                imageEl.src = `/api/frame?session=${encodeURIComponent(sessionID)}&t=${Date.now()}`;
                frameTimer = window.setTimeout(loadNext, 180);
              };
              loadNext();
            }

            async function sendControl(type, event, extra = {}) {
              if (authorization !== "controlling" || !sessionID) return;
              const payload = Object.assign({ type, session: sessionID }, extra);
              if (event && "clientX" in event) Object.assign(payload, pointerPayload(event));
              await postJSON("/api/control", payload).catch(() => {});
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
            }, { passive: false });
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
            disconnectButton.addEventListener("click", () => {
              sessionID = "";
              authorization = "pending";
              imageEl.removeAttribute("src");
              requestButton.disabled = false;
              disconnectButton.disabled = true;
              setStatus("已断开本次浏览器会话。", "未连接");
            });
            requestButton.addEventListener("click", requestAccess);
            if (invite !== EXPECTED_INVITE) {
              requestButton.disabled = true;
              setStatus("链接验证码无效，请使用主机端当前显示的地址。", "验证码错误");
            }
          </script>
        </body>
        </html>
        """
    }
}
