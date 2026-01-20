# ==========================================
# Manul Programming Language Installer (Windows)
# ==========================================

$ErrorActionPreference = "Stop"

# Configuration
$ManulVersion = "0.0.1-alpha"
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
Write-Host "Verifying system compatibility..."

# 1a. Architecture Check
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
    Write-Yellow "Note: Native Windows Arm64 binary not available. Installing x64 binary (runs via Emulation)."
    $AssetName = "manul-windows-amd64.zip"
    
    # On Arm64 Windows, we still install the x64 Redistributable for the emulated binary
    $VcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $VcRegKey = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
} else {
    Write-Red "Error: Architecture $Arch is not supported."
    exit 1
}

# 1b. OS Version Check
# Minimums: Windows 10 or Server 2022
try {
    $OsInfo = Get-CimInstance Win32_OperatingSystem
    $MajorVer = [System.Environment]::OSVersion.Version.Major
    $BuildNum = [System.Environment]::OSVersion.Version.Build
    $ProductType = $OsInfo.ProductType # 1 = Client (Workstation), 2/3 = Server

    if ($ProductType -eq 1) {
        # Client: Windows 10 (Major 10)
        if ($MajorVer -lt 10) {
            Write-Red "Error: Manul requires Windows 10 or newer."
            Write-Red "Detected: $($OsInfo.Caption)"
            exit 1
        }
    } else {
        # Server: Windows Server 2016 (Build 14393+)
        if ($BuildNum -lt 14393) {
            Write-Red "Error: Manul requires Windows Server 2016 or newer."
            Write-Red "Detected: $($OsInfo.Caption) (Build $BuildNum)"
            exit 1
        }
    }
    Write-Green "System ($($OsInfo.Caption)) is supported."

} catch {
    Write-Yellow "Warning: Could not strictly verify OS version. Proceeding anyway."
}

# -----------------------------------------------------------------------------
# 1.5. Detect Region (GitHub vs Gitee)
# -----------------------------------------------------------------------------
$BaseDomain = "github.com"
Write-Host "Detecting region to select best mirror..."

function Test-IsChina {
    # 1. Environment Variable Override
    if ($env:REGION -eq "CN") { return $true }

    # 2. Network Connectivity Check (The "Google vs Baidu" test)
    # Helper to check connectivity with strict timeout
    $CheckUrl = { param($Url)
        try {
            $Request = [System.Net.WebRequest]::Create($Url)
            $Request.Method = "HEAD" # Head is faster than GET
            $Request.Timeout = 2000  # 2000ms = 2 seconds
            $Response = $Request.GetResponse()
            $Response.Close()
            return $true
        } catch {
            return $false
        }
    }

    # Try to connect to Google. If fails, check Baidu.
    if (-not (&$CheckUrl "https://www.google.com")) {
        # Google failed, check Baidu to confirm internet works and we are in CN
        if (&$CheckUrl "https://www.baidu.com") {
            return $true
        }
    }

    return $false
}

if (Test-IsChina) {
    Write-Yellow "China region detected (CN). Switching to Gitee mirror."
    $BaseDomain = "gitee.com"
} else {
    Write-Host "Using default mirror ($BaseDomain)."
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
    Write-Yellow "Action Required: Restart your terminal to use the 'manul' command."
} else {
    Write-Blue "You can run 'manul' immediately."
}