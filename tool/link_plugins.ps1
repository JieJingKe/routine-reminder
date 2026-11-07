$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$deps = Get-Content (Join-Path $root '.flutter-plugins-dependencies') -Raw | ConvertFrom-Json
$target = Join-Path $root 'windows\flutter\ephemeral\.plugin_symlinks'
foreach ($p in $deps.plugins.windows) {
  $link = Join-Path $target $p.name
  if (Test-Path $link) { (Get-Item $link).Delete() }
  New-Item -ItemType Junction -Path $link -Target $p.path.TrimEnd('\') | Out-Null
  Write-Output "$($p.name) -> $($p.path)"
}
