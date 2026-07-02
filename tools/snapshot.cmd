@echo off
setlocal
bash -lc "cd ""$(wslpath '%CD%')"" && bash ./tools/snapshot %*"
exit /b %ERRORLEVEL%
