@echo off
rem Build the KMDF driver: build_driver.cmd Debug|Release [x64|ARM64]. Needs the WDK (10.0.26100 or later,
rem with ACX 1.1) and the "Windows Driver Kit" Visual Studio component; for the ARM64 platform also the
rem "VC++ ARM64 build tools" component. Default platform: the host's (an ARM64 machine builds ARM64 drivers).
setlocal
set "CFG=%~1"
if "%CFG%"=="" set "CFG=Debug"
set "PLAT=%~2"
if "%PLAT%"=="" (
    if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (set "PLAT=ARM64") else (set "PLAT=x64")
)
set "VSARCH=x64"
if /i "%PLAT%"=="ARM64" set "VSARCH=arm64"
call "%~dp0tools\vsenv.cmd" %VSARCH% || exit /b 1
msbuild "%~dp0driver\LdacA2dp\LdacA2dp.vcxproj" -nologo -v:minimal -p:Configuration=%CFG% -p:Platform=%PLAT% %3 %4 %5
