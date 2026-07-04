$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$userPlugins = Join-Path $env:APPDATA "REAPER\UserPlugins"
$dllPath = Join-Path $root "build\windows-msvc-x64\bin\reaper_tk_native_helper.dll"
$installPath = Join-Path $userPlugins "reaper_tk_native_helper.dll"

function Find-CMake {
  $pathCmake = Get-Command cmake -ErrorAction SilentlyContinue
  if ($pathCmake) { return $pathCmake.Source }

  $localCmake = Join-Path $root "tools\cmake\bin\cmake.exe"
  if (Test-Path $localCmake) { return $localCmake }

  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $vswhere) {
    $vsPaths = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    foreach ($vsPath in $vsPaths) {
      $vsCmake = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
      if (Test-Path $vsCmake) { return $vsCmake }
    }
  }

  return $null
}

$cmake = Find-CMake
if (-not $cmake) {
  throw "cmake.exe is niet gevonden. Installeer Visual Studio Build Tools met de C++ workload of installeer CMake handmatig. CMake Tools in VS Code is alleen de UI-laag."
}

Push-Location $root
try {
  & $cmake --preset windows-msvc-x64
  if ($LASTEXITCODE -ne 0) { throw "CMake configure faalde met exitcode $LASTEXITCODE" }

  & $cmake --build --preset windows-msvc-x64-release
  if ($LASTEXITCODE -ne 0) { throw "CMake build faalde met exitcode $LASTEXITCODE" }

  if (-not (Test-Path $dllPath)) {
    throw "DLL niet gevonden: $dllPath"
  }

  New-Item -ItemType Directory -Path $userPlugins -Force | Out-Null
  Copy-Item $dllPath $installPath -Force
  Write-Output "Installed: $installPath"
  Write-Output "Restart REAPER to load the extension."
}
finally {
  Pop-Location
}
