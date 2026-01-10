# ==========================================
# Manul Programming Language Installer (Windows)
# ==========================================

$ErrorActionPreference = "Stop"

# Configuration
$ManulVersion = "0.0.1"
$Repo = "manul-language/manul"
$InstallDir = "$env:USERPROFILE\.manul"
$BinDir = "$InstallDir\bin"

# Colors for Output
function Write-Green ($text) { Write-Host $text -ForegroundColor Green }
function Write-Red ($text) { Write-Host $text -ForegroundColor Red }
function Write-Blue ($text) { Write-Host $text -ForegroundColor Cyan }
function Write-Yellow ($text) { Write-Host $text -ForegroundColor Yellow }

Write-Blue "Starting Manul Installer (v$ManulVersion)..."

# -----------------------------------------------------------------------------
# 1. Detect OS & Arch
# -----------------------------------------------------------------------------
$Arch = $env:PROCESSOR_ARCHITECTURE
$AssetName = ""

if ($Arch -eq "AMD64") {
    $AssetName = "manul-windows-amd64.zip"
} elseif ($Arch -eq "ARM64") {
    # Assuming arm64 support exists in your release assets
    $AssetName = "manul-windows-arm64.zip"
} else {
    Write-Red "Error: Architecture $Arch is not supported."
    exit 1
}

$DownloadUrl = "https://github.com/$Repo/releases/download/$ManulVersion/$AssetName"

# -----------------------------------------------------------------------------
# 2. Pre-Check: Stop existing services to release file locks
# -----------------------------------------------------------------------------
# Unlike Linux, Windows cannot overwrite running executables.
Write-Host "Checking for running processes..."
$RunningProcess = Get-Process -Name "manul-server" -ErrorAction SilentlyContinue
if ($RunningProcess) {
    Write-Yellow "Stopping running manul-server..."
    Stop-Process -Name "manul-server" -Force
}

# -----------------------------------------------------------------------------
# 3. Download & Extract
# -----------------------------------------------------------------------------
$TempDir = [System.IO.Path]::GetTempPath()
$ZipFile = Join-Path $TempDir $AssetName
$ExtractDir = Join-Path $TempDir "manul_extract"

Write-Host "Downloading " -NoNewline; Write-Blue $AssetName
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile -UseBasicParsing
    Write-Host " [OK]"
} catch {
    Write-Red "`nError downloading file: $_"
    exit 1
}

Write-Host "Extracting files..."
if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
Expand-Archive -Path $ZipFile -DestinationPath $ExtractDir -Force

# Handle nested folder logic (if zip contains root folder)
$SourceDir = $ExtractDir
$SubItems = Get-ChildItem -Path $ExtractDir
if ($SubItems.Count -eq 1 -and $SubItems[0].PSIsContainer) {
    $SourceDir = $SubItems[0].FullName
}

# -----------------------------------------------------------------------------
# 4. Install Files
# -----------------------------------------------------------------------------
Write-Host "Installing to $InstallDir..."

# Clean old install
if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
}

# Create directory and copy
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path "$SourceDir\*" -Destination $InstallDir -Recurse

# Cleanup Temp
Remove-Item $ZipFile -Force
Remove-Item $ExtractDir -Recurse -Force

# -----------------------------------------------------------------------------
# 5. Configure Shell (Environment Variable)
# -----------------------------------------------------------------------------
Write-Host "Configuring shell environment..."

# Get current User PATH
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathToAdd = $BinDir

if ($CurrentPath -split ';' -notcontains $PathToAdd) {
    Write-Blue "Adding $PathToAdd to User PATH..."
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$PathToAdd", "User")
    $EnvUpdateRequired = $true
} else {
    Write-Green "Path already configured."
    $EnvUpdateRequired = $false
}

# -----------------------------------------------------------------------------
# 6. Configure Service (Scheduled Task)
# -----------------------------------------------------------------------------
# On Windows, we use a User Scheduled Task to mimic systemd --user / LaunchAgents
Write-Host "Configuring " -NoNewline; Write-Blue "manul-server" -NoNewline; Write-Host " as a background task..."

$TaskName = "ManulLanguageServer"
$ExePath = "$BinDir\manul-server.exe"

if (Test-Path $ExePath) {
    # Unregister existing if present
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    # Create new task action (Start the server)
    # We use a trick with powershell Start-Process -WindowStyle Hidden if the exe is a console app
    # Or purely point to the exe if it handles its own windowing.
    $Action = New-ScheduledTaskAction -Execute $ExePath

    # Trigger at user logon
    $Trigger = New-ScheduledTaskTrigger -AtLogOn

    # Register the task (RunLevel Limited is fine for user space, doesn't need admin)
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Description "Manul Language Server" | Out-Null

    # Start it now
    Start-ScheduledTask -TaskName $TaskName
    Write-Green "Service configured and started."
} else {
    Write-Red "Warning: manul-server.exe not found in bin directory."
}

# -----------------------------------------------------------------------------
# 7. Completion
# -----------------------------------------------------------------------------
Write-Host ""
Write-Green "Manul installed successfully!"
Write-Host "Service is running as user: $env:USERNAME"

if ($EnvUpdateRequired) {
    Write-Yellow "Action Required: Restart your terminal (PowerShell/CMD) to use the 'manul' command."
} else {
    Write-Blue "You can run 'manul' immediately."
}