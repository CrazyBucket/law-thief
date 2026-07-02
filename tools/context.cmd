@echo off
setlocal
bash -lc "cd ""$(wslpath '%CD%')"" && bash ./tools/context %*"
exit /b %ERRORLEVEL%
