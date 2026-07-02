@echo off
setlocal
bash -lc "cd ""$(wslpath '%CD%')"" && bash ./tools/coverage %*"
exit /b %ERRORLEVEL%
