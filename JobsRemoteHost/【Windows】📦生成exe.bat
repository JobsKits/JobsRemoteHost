@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PROJECT_LAUNCHER=%SCRIPT_DIR%JobsRemoteHost\启动JobsRemoteHost.bat"

echo.
echo ============================== 脚本自述 ==============================
echo 当前脚本：%~f0
echo 核心用途：生成 JobsRemoteHost 的 Windows exe。
echo 影响范围：会调用内层 Python 工程，准备 .venv、依赖、cloudflared.exe 和 dist。
echo 输出目录：%SCRIPT_DIR%
echo ======================================================================
echo.
pause

if not exist "%PROJECT_LAUNCHER%" (
  echo 未找到内层构建脚本：%PROJECT_LAUNCHER%
  exit /b 1
)

set "JOBS_REMOTE_HOST_CONFIRMED=1"
set "JOBS_REMOTE_HOST_OUTPUT_DIR=%SCRIPT_DIR%"
call "%PROJECT_LAUNCHER%" build-exe %*
exit /b %ERRORLEVEL%
