#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：启动JobsRemoteHost.command
# - 核心用途：准备 Python 构建环境，按参数生成 macOS dmg，或供开发时源码启动。
# - 影响范围：只在当前 JobsRemoteHost Python 工程内创建 .venv、tools、build、dist，并输出 dmg 到外层目录。
# - 运行提示：运行后会先打印内置自述；终端确认后继续，外层打包脚本可通过环境变量跳过重复确认。

setopt NO_NOMATCH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
PROJECT_DIR="${SCRIPT_DIR}"
OUTER_DIR="$(cd "${PROJECT_DIR}/.." && pwd)"
VENV_DIR="${PROJECT_DIR}/.venv"
PYTHON_BIN="${VENV_DIR}/bin/python"
PIP_BIN="${VENV_DIR}/bin/pip"
MODE="${1:-build-dmg}"
OUTPUT_DIR="${JOBS_REMOTE_HOST_OUTPUT_DIR:-${OUTER_DIR}}"
: > "$LOG_FILE"

# 记录终端和日志。
log() {
  echo -e "$1" | tee -a "$LOG_FILE"
}
# 输出绿色成功信息。
success_echo() {
  log "\033[1;32m✔ $1\033[0m"
}
# 输出蓝色说明信息。
note_echo() {
  log "\033[1;35m➤ $1\033[0m"
}
# 输出黄色警告信息。
warn_echo() {
  log "\033[1;33m⚠ $1\033[0m"
}
# 输出红色错误信息。
error_echo() {
  log "\033[1;31m✖ $1\033[0m"
}
# 输出高亮信息。
highlight_echo() {
  log "\033[1;36m🔹 $1\033[0m"
}
# 输出灰色辅助信息。
gray_echo() {
  log "\033[0;90m$1\033[0m"
}
# 打印脚本内置自述，并按入口决定是否等待回车。
show_script_intro_and_wait() {
  clear
  highlight_echo "============================== 脚本自述 =============================="
  note_echo "当前脚本：${SCRIPT_PATH}"
  note_echo "核心用途：生成 JobsRemoteHost 的 macOS dmg；内层也保留开发用源码启动参数。"
  warn_echo "影响范围：会在 ${PROJECT_DIR} 内创建 .venv / tools / build / dist，并下载 cloudflared。"
  gray_echo "输出目录：${OUTPUT_DIR}"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "======================================================================="
  echo ""
  if [[ "${JOBS_REMOTE_HOST_CONFIRMED:-0}" == "1" ]]; then
    gray_echo "外层入口已确认，跳过重复回车。"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前没有可交互输入，请在终端双击或从外层打包脚本启动。"
    return 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 检查系统命令和 Python 版本。
check_environment() {
  command -v python3 >/dev/null 2>&1 || {
    error_echo "未找到 python3，请先安装 Python 3.11+。"
    return 1
  }
  python3 - <<'PY'
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
  if [[ "$?" != "0" ]]; then
    error_echo "Python 版本过低，需要 Python 3.11+。"
    return 1
  fi
  command -v hdiutil >/dev/null 2>&1 || {
    error_echo "未找到 hdiutil，无法生成 dmg。"
    return 1
  }
}
# 创建虚拟环境并安装运行 / 构建依赖。
prepare_python_environment() {
  cd "$PROJECT_DIR" || return 1
  if [[ ! -x "$PYTHON_BIN" ]]; then
    note_echo "创建 Python 虚拟环境：${VENV_DIR}"
    python3 -m venv "$VENV_DIR" || return 1
  fi
  note_echo "安装运行与打包依赖"
  "$PIP_BIN" install --upgrade pip wheel setuptools | tee -a "$LOG_FILE" || return 1
  "$PIP_BIN" install -r requirements-build.txt | tee -a "$LOG_FILE" || return 1
}
# 返回当前 Mac CPU 架构名称。
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "amd64"
}
# 下载 cloudflared 到项目 tools 目录。
prepare_cloudflared() {
  local arch=""
  local url=""
  local archive=""
  local tools_dir="${PROJECT_DIR}/tools"
  mkdir -p "$tools_dir"
  if [[ -x "${tools_dir}/cloudflared" ]]; then
    success_echo "cloudflared 已存在：${tools_dir}/cloudflared"
    return 0
  fi
  arch="$(get_cpu_arch)"
  url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-${arch}.tgz"
  archive="${tools_dir}/cloudflared-darwin-${arch}.tgz"
  note_echo "下载 cloudflared：${url}"
  /usr/bin/curl -L --fail "$url" -o "$archive" | tee -a "$LOG_FILE" || return 1
  /usr/bin/tar -xzf "$archive" -C "$tools_dir" || return 1
  chmod +x "${tools_dir}/cloudflared"
  rm -f "$archive"
  success_echo "cloudflared 已准备：${tools_dir}/cloudflared"
}
# 执行 PyInstaller 构建。
build_app() {
  cd "$PROJECT_DIR" || return 1
  note_echo "开始 PyInstaller 打包"
  "$PYTHON_BIN" -m PyInstaller --noconfirm --clean JobsRemoteHost.spec | tee -a "$LOG_FILE" || return 1
  [[ -d "${PROJECT_DIR}/dist/JobsRemoteHost.app" ]] || {
    error_echo "未找到 dist/JobsRemoteHost.app"
    return 1
  }
}
# 生成 dmg 文件。
create_dmg() {
  local arch=""
  local stage_dir=""
  local dmg_path=""
  arch="$(uname -m)"
  stage_dir="${PROJECT_DIR}/build/dmg-stage"
  dmg_path="${OUTPUT_DIR}/JobsRemoteHost-macOS-${arch}.dmg"
  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"
  cp -R "${PROJECT_DIR}/dist/JobsRemoteHost.app" "$stage_dir/"
  ln -s /Applications "${stage_dir}/Applications"
  rm -f "$dmg_path"
  note_echo "生成 dmg：${dmg_path}"
  hdiutil create -volname "JobsRemoteHost" -srcfolder "$stage_dir" -ov -format UDZO "$dmg_path" | tee -a "$LOG_FILE" || return 1
  success_echo "dmg 已生成：${dmg_path}"
}
# 执行源码 GUI，供开发调试使用。
run_source_app() {
  cd "$PROJECT_DIR" || return 1
  "$PYTHON_BIN" JobsRemoteHost.py
}
# 执行协议自检。
run_self_test() {
  cd "$PROJECT_DIR" || return 1
  "$PYTHON_BIN" JobsRemoteHost.py --self-test
}
# 按入口参数分派实际任务。
run_selected_mode() {
  local mode="$1"
  case "$mode" in
    build-dmg)
      prepare_python_environment || return 1
      prepare_cloudflared || return 1
      run_self_test || return 1
      build_app || return 1
      create_dmg || return 1
      ;;
    run-app)
      prepare_python_environment || return 1
      run_source_app || return 1
      ;;
    self-test)
      prepare_python_environment || return 1
      run_self_test || return 1
      ;;
    *)
      error_echo "未知参数：${mode}。可用参数：build-dmg / run-app / self-test"
      return 1
      ;;
  esac
}
# 编排脚本自述、环境检查和打包流程。
main() {
  show_script_intro_and_wait # 打印内置自述并等待确认，避免误触直接安装依赖或生成产物。
  check_environment # 检查 python3、Python 版本和 dmg 生成工具是否可用。
  run_selected_mode "$MODE" # 根据入口参数执行 dmg 打包、源码启动或协议自检。
}

main "$@"
