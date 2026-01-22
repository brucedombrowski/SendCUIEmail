@echo off
REM SendCUIEmail - Decrypt .Locked files
REM Drag .Locked files onto this batch file, or run from command line

setlocal EnableDelayedExpansion

REM Check for PowerShell
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell is not available on this system.
    pause
    exit /b 1
)

REM Build argument list for PowerShell
set "ARGS="
:argloop
if "%~1"=="" goto endargs
set "ARGS=!ARGS! "%~1""
shift
goto argloop
:endargs

REM If no arguments, show usage
if "!ARGS!"=="" (
    echo.
    echo SendCUIEmail - File Decryption Tool
    echo ====================================
    echo.
    echo Usage:
    echo   - Drag .Locked files onto Decrypt.bat
    echo   - Or run: Decrypt.bat file1.pdf.Locked file2.docx.Locked
    echo.
    echo Output:
    echo   - Creates decrypted files with .Locked extension removed
    echo.
    pause
    exit /b 1
)

REM Run PowerShell script with execution policy bypass
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Decrypt.ps1" !ARGS!

pause
