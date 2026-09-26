@echo off
setlocal
rem PongTang bitstream build for Tang Console 138K.
rem Finds gw_sh from ANY Gowin installation (no hardcoded version):
rem   1. gw_sh on PATH   2. %GOWIN_HOME%   3. newest C:\Gowin\Gowin_* / D:\Gowin\Gowin_*

cd /d "%~dp0"
echo Build directory: %CD%
if exist "VERSION" (
    set /p PONGTANG_REV=<VERSION
) else (
    set PONGTANG_REV=unknown-old-package
)
echo PongTang package revision: %PONGTANG_REV%
if not exist "build.tcl" (
    echo ERROR: build.tcl not found in %CD%.
    echo Unzip the package so that buildall.bat and build.tcl are in the same folder.
    pause
    exit /b 1
)

set "GWSH="
rem Primary: known installation (Gowin Standard V1.9.12.04, 64-bit)
if exist "C:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe" set "GWSH=C:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe"
where gw_sh >nul 2>&1
if %errorlevel% equ 0 (
    for /f "delims=" %%i in ('where gw_sh') do set "GWSH=%%i"
)
if not defined GWSH if defined GOWIN_HOME (
    if exist "%GOWIN_HOME%\IDE\bin\gw_sh.exe" set "GWSH=%GOWIN_HOME%\IDE\bin\gw_sh.exe"
)
if not defined GWSH (
    for /d %%d in ("C:\Gowin\Gowin_*" "D:\Gowin\Gowin_*") do (
        if exist "%%d\IDE\bin\gw_sh.exe" set "GWSH=%%d\IDE\bin\gw_sh.exe"
    )
)
if not defined GWSH (
    echo ERROR: gw_sh not found. Install Gowin EDA Standard, then either
    echo   - add its IDE\bin to PATH, or
    echo   - set GOWIN_HOME, or
    echo   - install under C:\Gowin.
    pause
    exit /b 1
)

echo Using %GWSH%
echo.
echo Running Gowin build - this takes several minutes, please wait...
echo DO NOT CLOSE this window. Full transcript goes to build.log
"%GWSH%" build.tcl > build.log 2>&1
set BUILD_ERR=%errorlevel%
if %BUILD_ERR% neq 0 (
    echo.
    echo BUILD FAILED with error %BUILD_ERR%.
    echo.
    echo ============ ERROR lines from build.log ============
    findstr /n /I "ERROR" build.log
    echo ====================================================
    echo ^(full transcript: %CD%\build.log -- upload it to GitHub if asked^)
    pause
    exit /b %BUILD_ERR%
)

dir impl\pnr\pongtang_console138k.bin impl\pnr\pongtang_console138k.fs
echo.
echo Done. Copy impl\pnr\pongtang_console138k.bin to microSD as cores\pongtang.bin
pause
