#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：【MacOS】📦生成dmg.command
# - 核心用途：进入内层 Python 工程，生成 JobsRemoteHost 的 macOS dmg 安装包。
# - 影响范围：只调用内层启动JobsRemoteHost.command 的 build-dmg 流程，不直接运行远程控制业务。
# - 运行提示：运行后会先打印内置自述；确认后继续，按 Ctrl+C 可取消。

setopt NO_NOMATCH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
PROJECT_LAUNCHER="${SCRIPT_DIR}/JobsRemoteHost/启动JobsRemoteHost.command"
: > "$LOG_FILE"

# 记录终端和日志。
log() {
  echo -e "$1" | tee -a "$LOG_FILE"
}
# 输出高亮信息。
highlight_echo() {
  log "\033[1;36m🔹 $1\033[0m"
}
# 输出说明信息。
note_echo() {
  log "\033[1;35m➤ $1\033[0m"
}
# 输出警告信息。
warn_echo() {
  log "\033[1;33m⚠ $1\033[0m"
}
# 输出错误信息。
error_echo() {
  log "\033[1;31m✖ $1\033[0m"
}
# 输出灰色辅助信息。
gray_echo() {
  log "\033[0;90m$1\033[0m"
}
# 打印脚本内置自述，并等待用户确认。
show_script_intro_and_wait() {
  clear
  highlight_echo "============================== 脚本自述 =============================="
  note_echo "当前脚本：${SCRIPT_PATH}"
  note_echo "核心用途：生成 JobsRemoteHost 的 macOS dmg 安装包。"
  warn_echo "影响范围：会调用内层 Python 工程打包流程，准备 .venv、依赖、cloudflared 和 dist。"
  gray_echo "输出目录：${SCRIPT_DIR}"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "======================================================================="
  echo ""
  if [[ ! -t 0 ]]; then
    error_echo "当前没有可交互输入，请在终端或 Finder 中运行。"
    return 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 检查内层构建入口是否存在。
check_launcher() {
  if [[ ! -f "$PROJECT_LAUNCHER" ]]; then
    error_echo "未找到内层构建脚本：${PROJECT_LAUNCHER}"
    return 1
  fi
  chmod +x "$PROJECT_LAUNCHER"
}
# 委托内层 Python 工程执行 dmg 打包。
run_build() {
  JOBS_REMOTE_HOST_CONFIRMED=1 JOBS_REMOTE_HOST_OUTPUT_DIR="${SCRIPT_DIR}" "$PROJECT_LAUNCHER" build-dmg "$@"
}
# 编排外层确认、入口检查和 dmg 构建。
main() {
  show_script_intro_and_wait # 打印外层脚本自述并等待确认，避免双击误触后直接构建。
  check_launcher # 确认内层 Python 工程的构建入口存在且可执行。
  run_build "$@" # 委托内层脚本执行完整 dmg 构建流程。
}

main "$@"
