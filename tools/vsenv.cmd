@echo off
rem Sets up the MSVC environment of the newest Visual Studio with C++ tools
rem (found through vswhere), unless a developer prompt is already active.
rem Usage: tools\vsenv.cmd [x64|arm64]  :: target architecture, default: the host's.
rem On an ARM64 host the native ARM64 tools are used; on an x64 host ARM64 is
rem cross-compiled with the "x64_arm64" (amd64_arm64) toolset.
if defined VCToolsInstallDir exit /b 0
set "TARGET=%~1"
if "%TARGET%"=="" (
    if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (set "TARGET=arm64") else (set "TARGET=x64")
)
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (echo vswhere.exe not found: install Visual Studio with "Desktop development with C++" & exit /b 1)
if /i "%TARGET%"=="arm64" (set "VCCOMP=Microsoft.VisualStudio.Component.VC.Tools.ARM64") else (set "VCCOMP=Microsoft.VisualStudio.Component.VC.Tools.x86.x64")
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -prerelease -products * -requires %VCCOMP% -property installationPath`) do set "VSINSTALL=%%i"
if not defined VSINSTALL (echo No Visual Studio with C++ tools for %TARGET% found: add the component in Visual Studio Installer & exit /b 1)
if /i not "%TARGET%"=="arm64" (
    call "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
    exit /b 0
)
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    if exist "%VSINSTALL%\VC\Auxiliary\Build\vcvarsarm64.bat" (
        call "%VSINSTALL%\VC\Auxiliary\Build\vcvarsarm64.bat" >nul || exit /b 1
    ) else (
        call "%VSINSTALL%\VC\Auxiliary\Build\vcvarsall.bat" arm64 >nul || exit /b 1
    )
) else (
    call "%VSINSTALL%\VC\Auxiliary\Build\vcvarsall.bat" x64_arm64 >nul || exit /b 1
)
