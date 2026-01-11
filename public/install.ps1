# ==========================================
# Manul Programming Language Installer (Windows)
# ==========================================

$ErrorActionPreference = "Stop"

# Configuration
$ManulVersion = "0.0.1"
$RepoPath = "wizardleeen/manul"
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
$VcRedistUrl = ""
$VcRegKey = ""

if ($Arch -eq "AMD64") {
    $AssetName = "manul-windows-amd64.zip"
    # Link for Visual Studio 2015-2022 Redistributable (x64)
    $VcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $VcRegKey = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
} elseif ($Arch -eq "ARM64") {
    $AssetName = "manul-windows-arm64.zip"
    # Link for Visual Studio 2015-2022 Redistributable (ARM64)
    $VcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.arm64.exe"
    $VcRegKey = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\arm64"
} else {
    Write-Red "Error: Architecture $Arch is not supported."
    exit 1
}

# -----------------------------------------------------------------------------
# 1.5. Detect Region (GitHub vs Gitee)
# -----------------------------------------------------------------------------
$BaseDomain = "github.com"
Write-Host "Detecting region to select best mirror..."

try {
    # We use .NET WebRequest to enforce a strict timeout (2 seconds)
    # Standard Invoke-RestMethod in PS 5.1 doesn't support short timeouts well
    $Request = [System.Net.WebRequest]::Create("https://ipapi.co/country_code")
    $Request.Timeout = 10000
    $Response = $Request.GetResponse()
    $Stream = $Response.GetResponseStream()
    $Reader = New-Object System.IO.StreamReader($Stream)
    $CountryCode = $Reader.ReadToEnd().Trim()

    # Cleanup
    $Reader.Close()
    $Response.Close()

    if ($CountryCode -eq "CN") {
        Write-Yellow "China region detected (CN). Switching to Gitee mirror."
        $BaseDomain = "gitee.com"
    } else {
        Write-Host "Using default mirror ($BaseDomain)."
    }
} catch {
    # If API fails or times out, default to GitHub
    Write-Host "Region detection skipped or timed out. Using default mirror ($BaseDomain)."
}

$DownloadUrl = "https://$BaseDomain/$RepoPath/releases/download/$ManulVersion/$AssetName"

# -----------------------------------------------------------------------------
# 2. Check Prerequisites (Visual C++ Redistributable)
# -----------------------------------------------------------------------------
Write-Host "Checking system prerequisites..."
$VcInstalled = Test-Path $VcRegKey

if (-not $VcInstalled) {
    Write-Yellow "Visual C++ Redistributable is missing. Installing..."

    $VcTempFile = Join-Path $env:TEMP "vc_redist_installer.exe"

    Write-Host "Downloading VC++ Redistributable..."
    try {
        Invoke-WebRequest -Uri $VcRedistUrl -OutFile $VcTempFile -UseBasicParsing
    } catch {
        Write-Red "Failed to download VC++ Redistributable. Please install it manually."
        exit 1
    }

    Write-Blue "Requesting permission to install VC++ Redistributable..."
    Write-Host "(A User Account Control (UAC) prompt may appear)"

    try {
        # Arguments: /install /passive (show progress bar but no user interaction) /norestart
        $Process = Start-Process -FilePath $VcTempFile -ArgumentList "/install", "/passive", "/norestart" -PassThru -Wait -Verb RunAs

        # Check exit codes: 0 = Success, 3010 = Success (Reboot Required)
        if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
            Write-Green "VC++ Redistributable installed successfully."
        } else {
            Write-Red "VC++ installation failed with exit code: $($Process.ExitCode)"
            Write-Red "Please install 'Visual C++ Redistributable 2015-2022' manually."
            exit 1
        }
    } catch {
        Write-Red "Installation cancelled or failed. Admin privileges are required for VC++ installation."
        exit 1
    } finally {
        if (Test-Path $VcTempFile) { Remove-Item $VcTempFile -Force }
    }
} else {
    Write-Green "Visual C++ Redistributable is already installed."
}

# -----------------------------------------------------------------------------
# 3. Pre-Check: Stop existing services to release file locks
# -----------------------------------------------------------------------------
# Unlike Linux, Windows cannot overwrite running executables.
Write-Host "Checking for running processes..."
$RunningProcess = Get-Process -Name "manul-server" -ErrorAction SilentlyContinue
if ($RunningProcess) {
    Write-Yellow "Stopping running manul-server..."
    Stop-Process -Name "manul-server" -Force
}

# -----------------------------------------------------------------------------
# 4. Download & Extract
# -----------------------------------------------------------------------------
$TempDir = $env:TEMP
$ZipFile = Join-Path $TempDir $AssetName
$ExtractDir = Join-Path $TempDir "manul_extract"

Write-Host "Downloading from " -NoNewline; Write-Blue $BaseDomain -NoNewline; Write-Host ": $AssetName"
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile -UseBasicParsing
    Write-Host "Download Complete."
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
# 5. Install Files
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
# 6. Configure Shell (Environment Variable)
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
# 7. Configure Service (Scheduled Task)
# -----------------------------------------------------------------------------
Write-Host "Configuring " -NoNewline; Write-Blue "manul-server" -NoNewline; Write-Host " as a hidden background task..."

$TaskName = "ManulLanguageServer"
$ExePath = "$BinDir\manul-server.exe"
$VbsPath = "$BinDir\manul-launcher.vbs"

if (Test-Path $ExePath) {
    # 1. Create a VBScript shim. This is required to force the window to be hidden completely.
    # WshShell.Run args: path, 0 (hide window), False (don't wait)
    $VbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """$ExePath""", 0, False
"@
    Set-Content -Path $VbsPath -Value $VbsContent -Force

    # 2. Unregister existing task if present
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    # 3. Create Action: Use wscript.exe (GUI script host) to run the VBS
    # This prevents the black console window from flashing.
    $Action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument """$VbsPath"""

    # 4. Trigger: Run at Logon
    $Trigger = New-ScheduledTaskTrigger -AtLogOn

    # 5. Settings: Battery friendly + Infinite execution
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0

    # 6. Register the task
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Manul Language Server" | Out-Null

    # Start it now
    Start-ScheduledTask -TaskName $TaskName
    Write-Green "Service configured and started."
} else {
    Write-Red "Warning: manul-server.exe not found in bin directory."
}

# -----------------------------------------------------------------------------
# 8. Completion
# -----------------------------------------------------------------------------
Write-Host ""
Write-Green "Manul installed successfully!"
Write-Host "Service is running as user: $env:USERNAME"

if ($EnvUpdateRequired) {
    Write-Yellow "Action Required: Restart your terminal (PowerShell/CMD) to use the 'manul' command."
} else {
    Write-Blue "You can run 'manul' immediately."
}