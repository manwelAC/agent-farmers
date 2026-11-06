param([string]$OutputDirectory = 'dist')
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $outputRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $OutputDirectory))
    if (-not $outputRoot.StartsWith($PSScriptRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Build output must remain inside this project.' }
    $destination = Join-Path $outputRoot 'Agent Farmers'
    $existingApp = Join-Path $destination 'Agent Farmers.exe'
    if (Test-Path -LiteralPath $existingApp) {
        try { $probe = [IO.File]::Open($existingApp, 'Open', 'ReadWrite', 'None'); $probe.Dispose() }
        catch { throw 'Close the running Agent Farmers app, or choose a new output directory before building.' }
    }
    & .\.venv\Scripts\python.exe -m PyInstaller --noconfirm --clean --distpath $outputRoot --onedir --windowed --name 'Agent Farmers' --add-data 'core/wsl_bridge.py;core' --collect-all aiohttp launch.py
    if ($LASTEXITCODE -ne 0) { throw 'Python application packaging failed.' }
    $godot = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '.tools\godot') -Filter '*win64.exe' | Select-Object -First 1
    if (-not $godot) { throw 'Portable Godot runtime is missing.' }
    Copy-Item -LiteralPath $godot.FullName -Destination (Join-Path $destination 'godot.exe') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'desktop') -Destination $destination -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $destination -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD_PARTY_NOTICES.md') -Destination $destination -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'licenses') -Destination $destination -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs') -Destination $destination -Recurse -Force
    Write-Output ('Portable folder: '+$destination)
} finally { Pop-Location }
