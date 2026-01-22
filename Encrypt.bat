@echo off
REM SendCUIEmail - Encrypt files for secure transmission
REM Drag files/folders onto this batch file, or run from command line

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
    echo SendCUIEmail - File Encryption Tool
    echo ====================================
    echo.
    echo Usage:
    echo   - Drag files or folders onto Encrypt.bat
    echo   - Or run: Encrypt.bat file1.pdf file2.docx
    echo   - Or run: Encrypt.bat "C:\Folder\To\Encrypt"
    echo.
    echo Output:
    echo   - Creates .Locked files alongside originals
    echo   - Generates README.md with decryption instructions
    echo.
    pause
    exit /b 1
)

REM Run PowerShell script with execution policy bypass
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Encrypt.ps1" !ARGS!

pause
