@echo off
setlocal
set "CODE_ROOT=%~dp0.."
if defined DESIGN_ROOT (
  set "RESOLVED_DESIGN_ROOT=%DESIGN_ROOT%"
) else (
  set "RESOLVED_DESIGN_ROOT=%CODE_ROOT%\..\learning-notes\game\design\law-thief"
)
set "SCRIPT=%RESOLVED_DESIGN_ROOT%\tools\design_context.py"
if not exist "%SCRIPT%" (
  echo DESIGN_TOOL_MISSING %SCRIPT% 1>&2
  echo Set DESIGN_ROOT to the local game\design\law-thief directory. 1>&2
  exit /b 2
)
where py >nul 2>nul
if errorlevel 1 goto try_python
py -3 "%SCRIPT%" --design-root "%RESOLVED_DESIGN_ROOT%" --code-root "%CODE_ROOT%" %*
exit /b %ERRORLEVEL%
:try_python
where python >nul 2>nul
if errorlevel 1 goto no_python
python "%SCRIPT%" --design-root "%RESOLVED_DESIGN_ROOT%" --code-root "%CODE_ROOT%" %*
exit /b %ERRORLEVEL%
:no_python
echo Python 3 is required. 1>&2
exit /b 2
