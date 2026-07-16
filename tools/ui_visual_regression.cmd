@echo off
setlocal
bash -lc "cd ""$(wslpath '%CD%')"" && bash ./tools/ui_visual_regression %*"
exit /b %ERRORLEVEL%
