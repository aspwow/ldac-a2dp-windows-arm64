@echo off
rem Configure and build the user-mode parts (CMake + Ninja from Visual Studio) and run the tests.
rem Usage: build.cmd [x64|arm64]  :: target architecture, default: the host's.
rem x64 builds into build\, arm64 into build_arm64\ (so both can sit side by side).
setlocal
set "TARGET=%~1"
if "%TARGET%"=="" (
    if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (set "TARGET=arm64") else (set "TARGET=x64")
)
set "BDIR=%~dp0build"
if /i "%TARGET%"=="arm64" set "BDIR=%~dp0build_arm64"
call "%~dp0tools\vsenv.cmd" %TARGET% || exit /b 1
cmake -S "%~dp0." -B "%BDIR%" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo || exit /b 1
cmake --build "%BDIR%" || exit /b 1
rem unit tests only run when the host can execute the produced binaries:
rem arm64 binaries built on an x64 machine cannot run there.
if /i "%TARGET%"=="arm64" if /i not "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    echo tests skipped: arm64 binaries do not run on an %PROCESSOR_ARCHITECTURE% host
    exit /b 0
)
ctest --test-dir "%BDIR%" --output-on-failure
