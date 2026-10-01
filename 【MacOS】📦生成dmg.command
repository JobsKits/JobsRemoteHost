#!/bin/zsh
# 脚本自述：转交现有打包入口；确认、依赖准备及构建由内层入口完成。
# shell: zsh
# 转交已维护的构建入口，产物和快捷方式位于本目录。
run_builder() {
  local script_dir="${0:A:h}"
  "${script_dir}/JobsRemoteHost/【MacOS】📦生成dmg.command" "$@"
}
# 执行唯一构建入口。
main() {
  run_builder "$@" # 内层先展示自述并确认，再构建和发布入口。
}
main "$@"
