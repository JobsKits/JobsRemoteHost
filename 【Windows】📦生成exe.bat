@echo off
rem 脚本自述：构建 Windows EXE，或通过 run-app / self-test 参数开发调试。
rem 运行前先显示影响范围并确认；构建产物统一写入本脚本同层的 dist。
setlocal EnableExtensions DisableDelayedExpansion
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%JobsRemoteHost"
for %%I in ("%SCRIPT_DIR%.") do set "OUTER_DIR=%%~fI"
set "DIST_ROOT=%OUTER_DIR%\dist"
set "OUTPUT_DIR=%DIST_ROOT%"
set "MODE=%~1"
if "%MODE%"=="" set "MODE=build-exe"
set "VENV_DIR=%PROJECT_DIR%\.venv"
set "PYTHON_BIN=%VENV_DIR%\Scripts\python.exe"
set "PIP_BIN=%VENV_DIR%\Scripts\pip.exe"

echo.
echo ============================== 脚本自述 ==============================
echo 当前脚本：%~f0
echo 核心用途：生成 JobsRemoteHost 的 Windows exe；也支持 run-app / self-test 开发参数。
echo 构建产物按本机年月日时分秒保存到 dist/YYYY.MM.DD HH-mm-ss/（例如 2020.06.04 12-23-21），同次构建共用一个时间目录。
echo 打包前清理旧 dist；成功后打开产物目录并启动本机 EXE。
echo 影响范围：在 JobsRemoteHost 内准备 .venv、tools、build，产物写入根目录 dist；缺失时下载 cloudflared.exe。
echo 输出目录：%OUTPUT_DIR%
echo ======================================================================
echo.
pause

call :check_python || exit /b 1
if /I "%MODE%"=="build-exe" (
  call :prepare_python_environment || exit /b 1
  call :prepare_cloudflared || exit /b 1
  call :run_self_test || exit /b 1
  call :build_exe || exit /b 1
  call :copy_exe || exit /b 1
  exit /b 0
)
if /I "%MODE%"=="run-app" goto run_app_mode
if /I "%MODE%"=="self-test" goto self_test_mode
echo 未知参数：%MODE%。可用参数：build-exe / run-app / self-test
exit /b 1

:run_app_mode
call :prepare_python_environment || exit /b 1
"%PYTHON_BIN%" "%PROJECT_DIR%\JobsRemoteHost.py"
exit /b %ERRORLEVEL%

:self_test_mode
call :prepare_python_environment || exit /b 1
call :run_self_test
exit /b %ERRORLEVEL%

:check_python
py -3.11 -c "import sys" >nul 2>nul
if %ERRORLEVEL%==0 (
  set "SYSTEM_PY=py -3.11"
  exit /b 0
)
python -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)" >nul 2>nul
if %ERRORLEVEL%==0 (
  set "SYSTEM_PY=python"
  exit /b 0
)
echo 未找到 Python 3.11+，请先安装 Python 3.11 或更新版本。
exit /b 1

:prepare_python_environment
cd /d "%PROJECT_DIR%" || exit /b 1
if not exist "%PYTHON_BIN%" (
  echo 创建 Python 虚拟环境：%VENV_DIR%
  %SYSTEM_PY% -m venv "%VENV_DIR%" || exit /b 1
)
"%PYTHON_BIN%" -c "import mss, PIL, pynput, pystray, PyInstaller" >nul 2>nul
if errorlevel 1 (
  call :confirm_required_install "Missing project dependencies" || exit /b 1
  "%PIP_BIN%" install -r "%PROJECT_DIR%\requirements-build.txt" || exit /b 1
  "%PYTHON_BIN%" -c "import mss, PIL, pynput, pystray, PyInstaller" || exit /b 1
)
exit /b 0

:prepare_cloudflared
set "TOOLS_DIR=%PROJECT_DIR%\tools"
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if exist "%TOOLS_DIR%\cloudflared.exe" (
  echo cloudflared.exe 已存在：%TOOLS_DIR%\cloudflared.exe
  exit /b 0
)
set "CF_ARCH=amd64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "CF_ARCH=arm64"
set "CF_URL=https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-%CF_ARCH%.exe"
echo 下载 cloudflared.exe：%CF_URL%
call :confirm_required_install "Missing cloudflared; network download required" || exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%CF_URL%' -OutFile '%TOOLS_DIR%\cloudflared.exe'" || exit /b 1
exit /b 0

:run_self_test
cd /d "%PROJECT_DIR%" || exit /b 1
"%PYTHON_BIN%" "%PROJECT_DIR%\JobsRemoteHost.py" --self-test
exit /b %ERRORLEVEL%

:build_exe
cd /d "%PROJECT_DIR%" || exit /b 1
"%PYTHON_BIN%" "%PROJECT_DIR%\scripts\artifact_shortcuts.py" --root "%OUTER_DIR%" --clear || exit /b 1
fsutil reparsepoint query "%DIST_ROOT%" >nul 2>nul
if not errorlevel 1 exit /b 1
if exist "%DIST_ROOT%" rmdir /s /q "%DIST_ROOT%"
if exist "%DIST_ROOT%" exit /b 1
set "BUILD_STAMP="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy.MM.dd HH-mm-ss'"') do set "BUILD_STAMP=%%T"
if not defined BUILD_STAMP exit /b 1
set "OUTPUT_DIR=%DIST_ROOT%\%BUILD_STAMP%"
echo Build time (YYYY.MM.DD HH-mm-ss): %BUILD_STAMP%
echo 开始 PyInstaller 打包
"%PYTHON_BIN%" -m PyInstaller --noconfirm --clean --distpath "%OUTPUT_DIR%" "%PROJECT_DIR%\JobsRemoteHost.spec" || exit /b 1
if not exist "%OUTPUT_DIR%\JobsRemoteHost.exe" (
  echo 未找到构建产物：%OUTPUT_DIR%\JobsRemoteHost.exe
  exit /b 1
)
exit /b 0

:copy_exe
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
copy /Y "%OUTPUT_DIR%\JobsRemoteHost.exe" "%OUTPUT_DIR%\JobsRemoteHost-Windows.exe" >nul || exit /b 1
echo exe 已生成：%OUTPUT_DIR%\JobsRemoteHost-Windows.exe
"%PYTHON_BIN%" "%PROJECT_DIR%\scripts\artifact_shortcuts.py" --root "%OUTER_DIR%" "%OUTPUT_DIR%\JobsRemoteHost-Windows.exe" || exit /b 1
start "" explorer.exe "%OUTPUT_DIR%"
start "" /D "%OUTPUT_DIR%" "%OUTPUT_DIR%\JobsRemoteHost-Windows.exe"
exit /b 0

:confirm_required_install
rem ReadLine 保留空格，并把 EOF 当成取消。
powershell -NoProfile -Command "[Console]::Write('%~1 (Enter to install; any character to cancel): '); $answer = [Console]::ReadLine(); if ($null -eq $answer -or $answer.Length -gt 0) { exit 1 }; exit 0"
if errorlevel 1 (
  echo Dependency installation cancelled. Stopping current task.
  exit /b 1
)
exit /b 0
