<#
.SYNOPSIS
  Builds the LDAC A2DP installation package: build\package\LdacA2dp-<version>-<arch>\
  and the same as a .zip.

.DESCRIPTION
  1. service and tests (build.cmd), Release driver (build_driver.cmd Release) for the
     chosen architecture;
  2. test-signs the driver (tools\stand\sign-driver.ps1) unless -NoSign;
  3. publishes the settings utility as one self-contained exe for the same
     architecture (the target machine may have no .NET 10);
  4. lays out installer\* next to them, writes version.txt (the driver's
     DriverVer version) and zips the folder.

  The package is architecture-specific: an ARM64 package (driver .sys, ldacsvc.exe,
  LdacConfig.exe all ARM64) installs only on an ARM64 machine; install.ps1 checks this.

.PARAMETER Arch
  x64 | arm64 | host (default: the architecture of the build machine).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\package\make-package.ps1 -Arch arm64
#>
param(
    [ValidateSet('x64', 'arm64', 'host')] [string] $Arch = 'host',
    [switch] $NoSign
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
if ($Arch -eq 'host') {
    $Arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
}
$platform = if ($Arch -eq 'arm64') { 'ARM64' } else { 'x64' }   # msbuild spelling
function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Run($exe, [string[]] $argv) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) { throw "$exe $($argv -join ' ') failed ($LASTEXITCODE)" }
}

Step "Service and tests ($Arch)"
Run cmd.exe @('/c', "`"$root\build.cmd`" $Arch")
Step "Driver (Release $platform)"
Run cmd.exe @('/c', "`"$root\build_driver.cmd`" Release $platform")
$svcOut = if ($Arch -eq 'arm64') { 'build_arm64' } else { 'build' }
$drv = Join-Path $root "build\LdacA2dp\$platform\Release\LdacA2dp"
if (-not $NoSign) {
    Step 'Test signature'
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\tools\stand\sign-driver.ps1" -Configuration Release -Platform $platform
    if ($LASTEXITCODE -ne 0) { throw 'sign-driver.ps1 failed' }
}

Step "Settings utility (self-contained single exe, $Arch)"
$pub = Join-Path $root "build\LdacConfig-publish-$Arch"
Run dotnet @('publish', "$root\ui\LdacConfig", '-c', 'Release', '-r', "win-$Arch", '--self-contained', 'true',
             '-p:PublishSingleFile=true', '-p:IncludeNativeLibrariesForSelfExtract=true', '-p:EnableCompressionInSingleFile=true', '-o', $pub, '--nologo')

$version = ((Select-String -Path "$drv\LdacA2dp.inf" -Pattern '^DriverVer\s*=\s*[^,]+,\s*(\S+)').Matches[0].Groups[1].Value)
$name = "LdacA2dp-$version-$Arch"
$out = Join-Path $root "build\package\$name"
Step "Layout $out"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$out\driver" | Out-Null
foreach ($f in 'LdacA2dp.inf', 'LdacA2dp.sys', 'ldaca2dp.cat', 'LdacA2dpTest.cer') {
    if (Test-Path "$drv\$f") { Copy-Item "$drv\$f" "$out\driver" }
}
Copy-Item "$root\$svcOut\ldacsvc.exe" $out
Copy-Item "$pub\LdacConfig.exe" $out
Copy-Item "$root\installer\*" $out
Set-Content -Path "$out\version.txt" -Value $version -Encoding ascii
Set-Content -Path "$out\arch.txt" -Value $Arch -Encoding ascii

$zip = "$out.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$out\*" -DestinationPath $zip
Step 'Done'
Get-ChildItem $out -Recurse -File | Select-Object @{ n = 'File'; e = { $_.FullName.Substring($out.Length + 1) } }, Length | Format-Table -AutoSize
Write-Host "Package: $zip ($([int]((Get-Item $zip).Length / 1MB)) MB)"
