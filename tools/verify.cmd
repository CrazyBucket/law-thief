@echo off
setlocal
bash -lc "cd ""$(wslpath '%CD%')"" && bash ./tools/verify %*"
exit /b %ERRORLEVEL%
