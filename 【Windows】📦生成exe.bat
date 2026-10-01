@echo off
rem Jobs: forward to the maintained builder, which shows the intro and asks for confirmation.
call "%~dp0JobsRemoteHost\【Windows】📦生成exe.bat" %*
exit /b %ERRORLEVEL%
