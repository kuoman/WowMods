# Zip each addon (or one named addon) into dist\.
# Usage: .\tools\package.ps1 [-Name Gatherer]
param(
    [string]$Name
)

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null

$addons = Get-ChildItem (Join-Path $root "addons") -Directory
if ($Name) { $addons = $addons | Where-Object Name -eq $Name }

foreach ($addon in $addons) {
    $zip = Join-Path $dist "$($addon.Name).zip"
    if (Test-Path $zip) { Remove-Item $zip }
    Compress-Archive -Path $addon.FullName -DestinationPath $zip
    Write-Host "Created $zip"
}
