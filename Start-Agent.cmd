@echo off
setlocal EnableExtensions
call "%~dp0portable\start.cmd" %*
exit /b %ERRORLEVEL%
