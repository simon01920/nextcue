# Rebuild every NextCue 3D asset (models, GLBs, plates, renders).
#   powershell -ExecutionPolicy Bypass -File blender/build.ps1 [-- build.py options]
# Examples:
#   blender/build.ps1                       # full rebuild
#   blender/build.ps1 --only cassette --quick
#   blender/build.ps1 --preview cassette --quick
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$BuildArgs)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Blender {
  if ($env:BLENDER -and (Test-Path $env:BLENDER)) { return $env:BLENDER }
  $cmd = Get-Command blender -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $roots = @("$env:ProgramFiles\Blender Foundation", "${env:ProgramFiles(x86)}\Steam\steamapps\common\Blender")
  foreach ($r in $roots) {
    if (Test-Path $r) {
      $hit = Get-ChildItem $r -Recurse -Filter blender.exe -Depth 2 -ErrorAction SilentlyContinue |
             Sort-Object FullName -Descending | Select-Object -First 1
      if ($hit) { return $hit.FullName }
    }
  }
  throw "blender.exe not found. Set `$env:BLENDER to its full path."
}

$blender = Find-Blender
$log = Join-Path $here "_cache\build.log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
Write-Host "Using $blender"
# Windows PowerShell turns every stderr line of a native exe into an error
# record; with "Stop" the first warning would abort the build mid-way.
$ErrorActionPreference = "Continue"
& $blender --background --factory-startup --python (Join-Path $here "build.py") -- @BuildArgs 2>&1 |
  ForEach-Object { "$_" } | Tee-Object -FilePath $log
exit $LASTEXITCODE
