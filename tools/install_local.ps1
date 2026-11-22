<#
.SYNOPSIS
    Installs Beast Lore Plus from this repository into the WoW Forever AddOns folder.

.DESCRIPTION
    1. Makes sure Libs\ exists in the repo (it is git-ignored; the packager fills it for releases).
       Missing libraries are copied from other addons already installed in the Forever AddOns folder
       (LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0). LibStub picks the newest
       copy at run time, so any recent version works.
    2. Copies only the addon's files (TOC, Lua, Data, Media, Libs, LICENSE) into
       <AddOns>\BeastLorePlus, replacing that one folder. Other addons are never touched.
       With -Junction it links the folder to the repo instead (edits show after /reload), but then
       the repo's tools\ and docs are visible to the game too (harmless).

.PARAMETER AddOns
    The Forever AddOns folder. Default: E:\Blizzard\World of Warcraft\_forever_\Interface\AddOns

.PARAMETER Junction
    Create a directory junction instead of copying.

.PARAMETER DryRun
    Show what would happen without changing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\install_local.ps1
    powershell -ExecutionPolicy Bypass -File tools\install_local.ps1 -Junction
#>
[CmdletBinding()]
param(
    [string]$AddOns = 'E:\Blizzard\World of Warcraft\_forever_\Interface\AddOns',
    [switch]$Junction,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$name = 'BeastLorePlus'

if (-not ($AddOns -match '\\Interface\\AddOns\\?$') -or -not (Test-Path $AddOns)) {
    throw "Refusing: '$AddOns' is not an existing ...\Interface\AddOns folder."
}
$dest = Join-Path $AddOns $name

# --- 1. Libraries -----------------------------------------------------------------
$libs = @(
    @{ Dir = 'LibStub';              File = 'LibStub.lua' },
    @{ Dir = 'CallbackHandler-1.0';  File = 'CallbackHandler-1.0.lua' },
    @{ Dir = 'LibDataBroker-1.1';    File = 'LibDataBroker-1.1.lua' },
    @{ Dir = 'LibDBIcon-1.0';        File = 'LibDBIcon-1.0.lua' }
)
foreach ($lib in $libs) {
    $target = Join-Path $repo "Libs\$($lib.Dir)\$($lib.File)"
    if (Test-Path $target) { continue }
    $found = Get-ChildItem -Path $AddOns -Recurse -Filter $lib.File -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "$dest\*" } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $found) {
        Write-Warning "$($lib.File) not found in any installed addon; the minimap button will be missing."
        continue
    }
    Write-Host "Lib: $($lib.File) <- $($found.FullName)"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        Copy-Item $found.FullName $target
    }
}

# --- 2. Install -------------------------------------------------------------------
if (Test-Path $dest) {
    $item = Get-Item $dest -Force
    $isLink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    Write-Host "Replacing existing $dest $(if ($isLink) { '(junction)' })"
    if (-not $DryRun) {
        if ($isLink) { $item.Delete() } else { Remove-Item -Recurse -Force $dest }
    }
}

if ($Junction) {
    Write-Host "Junction: $dest -> $repo"
    if (-not $DryRun) { New-Item -ItemType Junction -Path $dest -Target $repo | Out-Null }
} else {
    $items = @('BeastLorePlus.toc', 'LICENSE', 'Data', 'Media', 'Libs') +
        (Get-ChildItem -Path $repo -Filter '*.lua' -File | ForEach-Object { $_.Name })
    foreach ($i in $items) {
        $src = Join-Path $repo $i
        if (-not (Test-Path $src)) { Write-Warning "missing $i"; continue }
        Write-Host "Copy: $i"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Item -Recurse -Force $src (Join-Path $dest $i)
        }
    }
}
Write-Host ($(if ($DryRun) { 'Dry run: nothing changed.' } else { "Installed to $dest. /reload in game." }))
