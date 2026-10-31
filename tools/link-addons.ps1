# Junction every folder in addons\ into the WoW AddOns directory.
# Usage: .\tools\link-addons.ps1 -AddOnsPath "C:\Path\To\WoW\Interface\AddOns"
param(
    [Parameter(Mandatory = $true)][string]$AddOnsPath
)

$repoAddons = Join-Path $PSScriptRoot "..\addons" | Resolve-Path

if (-not (Test-Path $AddOnsPath)) {
    throw "AddOns path not found: $AddOnsPath"
}

Get-ChildItem $repoAddons -Directory | ForEach-Object {
    $link = Join-Path $AddOnsPath $_.Name
    if (Test-Path $link) {
        Write-Host "Skipping $($_.Name) (already exists)"
    } else {
        New-Item -ItemType Junction -Path $link -Target $_.FullName | Out-Null
        Write-Host "Linked $($_.Name)"
    }
}
