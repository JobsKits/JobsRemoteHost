#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：启动JobsRemoteHost.command
# - 核心用途：准备 Python 构建环境，按参数生成 macOS dmg，或供开发时源码启动。
# - 影响范围：只在当前 JobsRemoteHost Python 工程内创建 .venv、tools、build、dist，并输出 dmg 到工程 dist。
# - 运行提示：运行后会先打印内置自述；终端确认后继续，外层打包脚本可通过环境变量跳过重复确认。

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
setopt NO_NOMATCH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
PROJECT_DIR="${SCRIPT_DIR}"
OUTER_DIR="$(cd "${PROJECT_DIR}/../.." && pwd)"
VENV_DIR="${PROJECT_DIR}/.venv"
PYTHON_BIN="${VENV_DIR}/bin/python"
PIP_BIN="${VENV_DIR}/bin/pip"
MODE="${1:-build-dmg}"
DIST_ROOT="${OUTER_DIR}/dist"
OUTPUT_DIR="$DIST_ROOT"
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
  highlight_echo "============================== 脚本自述 ==============================" | jobs_intro_style title
  note_echo "当前脚本：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：生成 JobsRemoteHost 的 macOS dmg；内层也保留开发用源码启动参数。" | jobs_intro_style body
  note_echo "构建产物按本机年月日时分秒保存到 dist/YYYY.MM.DD HH-mm-ss/（例如 2020.06.04 12-23-21），同次构建共用一个时间目录。" | jobs_intro_style body
  warn_echo "打包前清理工程旧 dist；成功后定位产物并启动本机 APP。" | jobs_intro_style body
  warn_echo "影响范围：会在 ${PROJECT_DIR} 内创建 .venv / tools / build / dist，并下载 cloudflared。" | jobs_intro_style body
  gray_echo "输出目录：${OUTPUT_DIR}" | jobs_intro_style body
  gray_echo "日志文件：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body
  if [[ "${JOBS_REMOTE_HOST_CONFIRMED:-0}" == "1" ]]; then
    gray_echo "外层入口已确认，跳过重复回车。" | jobs_intro_style body
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
# 必需依赖缺失时回车安装，任意字符取消整个流程。
confirm_required_install() {
  local answer=""
  IFS= read -r "?${1}（直接回车安装；输入任意字符后回车取消）：" answer || { print -u2 '没有交互输入，停止依赖安装。'; exit 1; }
  [[ -z "$answer" ]] || { print -u2 '已取消依赖安装，停止当前流程。'; exit 1; }
}
# 创建虚拟环境并安装运行 / 构建依赖。
prepare_python_environment() {
  cd "$PROJECT_DIR" || return 1
  if [[ ! -x "$PYTHON_BIN" ]]; then
    note_echo "创建 Python 虚拟环境：${VENV_DIR}"
    python3 -m venv "$VENV_DIR" || return 1
  fi
  if ! "$PYTHON_BIN" -c 'import mss, PIL, pynput, PyInstaller' >/dev/null 2>&1; then
    confirm_required_install "需要联网补齐工程依赖"
    "$PIP_BIN" install -r requirements-build.txt | tee -a "$LOG_FILE" || return 1
    "$PYTHON_BIN" -c 'import mss, PIL, pynput, PyInstaller' || return 1
  fi
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
  confirm_required_install "缺少 cloudflared，需要联网下载"
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
  [[ ! -L "${DIST_ROOT}" ]] || { error_echo "拒绝清理符号链接 dist"; return 1; }
  "$PYTHON_BIN" "${PROJECT_DIR}/scripts/artifact_shortcuts.py" --root "$OUTER_DIR" --clear || return 1
  rm -rf -- "$DIST_ROOT" || return 1
  BUILD_STAMP="$(date "+%Y.%m.%d %H-%M-%S")"
  OUTPUT_DIR="${DIST_ROOT}/${BUILD_STAMP}"
  note_echo "构建时间（年月日时分秒）：${BUILD_STAMP}"
  note_echo "开始 PyInstaller 打包"
  "$PYTHON_BIN" -m PyInstaller --noconfirm --clean --distpath "$OUTPUT_DIR" JobsRemoteHost.spec | tee -a "$LOG_FILE" || return 1
  [[ -d "${OUTPUT_DIR}/JobsRemoteHost.app" ]] || {
    error_echo "未找到构建产物：${OUTPUT_DIR}/JobsRemoteHost.app"
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
  cp -R "${OUTPUT_DIR}/JobsRemoteHost.app" "$stage_dir/"
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
      "$PYTHON_BIN" "${PROJECT_DIR}/scripts/artifact_shortcuts.py" --root "$OUTER_DIR" "${OUTPUT_DIR}/JobsRemoteHost.app" "${OUTPUT_DIR}/JobsRemoteHost-macOS-$(uname -m).dmg" || return 1
      open "$OUTPUT_DIR" || return 1
      open "${OUTPUT_DIR}/JobsRemoteHost.app" || return 1
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
