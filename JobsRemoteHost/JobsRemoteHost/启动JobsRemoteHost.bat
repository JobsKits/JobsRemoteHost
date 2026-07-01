@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%PROJECT_DIR%\..") do set "OUTER_DIR=%%~fI"
if "%JOBS_REMOTE_HOST_OUTPUT_DIR%"=="" (
  set "OUTPUT_DIR=%OUTER_DIR%"
) else (
  set "OUTPUT_DIR=%JOBS_REMOTE_HOST_OUTPUT_DIR%"
)
set "MODE=%~1"
if "%MODE%"=="" set "MODE=build-exe"
set "VENV_DIR=%PROJECT_DIR%\.venv"
set "PYTHON_BIN=%VENV_DIR%\Scripts\python.exe"
set "PIP_BIN=%VENV_DIR%\Scripts\pip.exe"

echo.
echo ============================== 脚本自述 ==============================
echo 当前脚本：%~f0
echo 核心用途：生成 JobsRemoteHost 的 Windows exe；内层也保留开发用源码启动参数。
echo 影响范围：会在当前工程内创建 .venv、tools、build、dist，并下载 cloudflared.exe。
echo 输出目录：%OUTPUT_DIR%
echo ======================================================================
echo.
if not "%JOBS_REMOTE_HOST_CONFIRMED%"=="1" (
  pause
)

call :check_python || exit /b 1
if /I "%MODE%"=="build-exe" (
  call :prepare_python_environment || exit /b 1
  call :prepare_cloudflared || exit /b 1
  call :run_self_test || exit /b 1
  call :build_exe || exit /b 1
  call :copy_exe || exit /b 1
  exit /b 0
)
if /I "%MODE%"=="run-app" (
  call :prepare_python_environment || exit /b 1
  "%PYTHON_BIN%" "%PROJECT_DIR%\JobsRemoteHost.py"
  exit /b %ERRORLEVEL%
)
if /I "%MODE%"=="self-test" (
  call :prepare_python_environment || exit /b 1
  call :run_self_test
  exit /b %ERRORLEVEL%
)
echo 未知参数：%MODE%。可用参数：build-exe / run-app / self-test
exit /b 1

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
echo 安装运行与打包依赖
"%PIP_BIN%" install --upgrade pip wheel setuptools || exit /b 1
"%PIP_BIN%" install -r "%PROJECT_DIR%\requirements-build.txt" || exit /b 1
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
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%CF_URL%' -OutFile '%TOOLS_DIR%\cloudflared.exe'" || exit /b 1
exit /b 0

:run_self_test
cd /d "%PROJECT_DIR%" || exit /b 1
"%PYTHON_BIN%" "%PROJECT_DIR%\JobsRemoteHost.py" --self-test
exit /b %ERRORLEVEL%

:build_exe
cd /d "%PROJECT_DIR%" || exit /b 1
echo 开始 PyInstaller 打包
"%PYTHON_BIN%" -m PyInstaller --noconfirm --clean "%PROJECT_DIR%\JobsRemoteHost.spec" || exit /b 1
if not exist "%PROJECT_DIR%\dist\JobsRemoteHost.exe" (
  echo 未找到 dist\JobsRemoteHost.exe
  exit /b 1
)
exit /b 0

:copy_exe
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
copy /Y "%PROJECT_DIR%\dist\JobsRemoteHost.exe" "%OUTPUT_DIR%\JobsRemoteHost-Windows.exe" >nul || exit /b 1
echo exe 已生成：%OUTPUT_DIR%\JobsRemoteHost-Windows.exe
exit /b 0
