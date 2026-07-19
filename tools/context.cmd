@echo off
setlocal
call "%~dp0design.cmd" find %*
exit /b %ERRORLEVEL%
