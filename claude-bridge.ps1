# =============================================================
#  Claude Bridge v2.1 - Full Windows Control
#  Run this script to allow Claude to control your Windows PC.
#
#  Command JSON fields:
#    type          : "shell" | "script" | "search" | "screenshot"
#    command       : PowerShell expression (shell type)
#    script        : filename of .ps1 in the Claude folder (script type)
#    screenshot    : true/false — capture screen after command
#    restore_focus : true/false — bring Claude/Cowork back to foreground
#    close_after   : process name to kill after command (e.g. "SystemSettings")
#
#  Files:
#    claude-command.json  — Claude writes commands here
#    claude-result.json   — Bridge writes results here
#    claude-screenshot.png — Screenshot (if requested)
# =============================================================

$bridgeDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$commandFile    = Join-Path $bridgeDir "claude-command.json"
$resultFile     = Join-Path $bridgeDir "claude-result.json"
$logFile        = Join-Path $bridgeDir "claude-bridge.log"
$screenshotFile = Join-Path $bridgeDir "claude-screenshot.png"

# ── Logging ───────────────────────────────────────────────────
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp  $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

# ── Result writer ─────────────────────────────────────────────
function Write-Result {
    param($Status, $Output, $Err, $Cmd, $Type, $Screenshot = $false)
    @{
        status     = $Status
        output     = $Output
        error      = $Err
        command    = $Cmd
        type       = $Type
        screenshot = $Screenshot
        timestamp  = (Get-Date -Format "o")
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $resultFile -Encoding UTF8
}

# ── Screenshot ────────────────────────────────────────────────
function Take-Screenshot {
    param($Path)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $screen   = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap   = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
        return $true
    } catch {
        Write-Log "Screenshot failed: $_"
        return $false
    }
}

# ── Focus restore — bring Claude/Cowork window to foreground ──
function Restore-ClaudeFocus {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinFocus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
}
"@ -ErrorAction SilentlyContinue

        # Try common Claude/Cowork window titles
        $titles = @("Claude", "Cowork", "Claude - Cowork", "Anthropic")
        foreach ($title in $titles) {
            $hwnd = [WinFocus]::FindWindow([NullString]::Value, $title)
            if ($hwnd -ne [IntPtr]::Zero) {
                [WinFocus]::ShowWindow($hwnd, 9)      # SW_RESTORE
                [WinFocus]::SetForegroundWindow($hwnd)
                Write-Log "Focus restored to: $title"
                return
            }
        }

        # Fallback: try partial title match via process windows
        $proc = Get-Process | Where-Object {
            $_.MainWindowTitle -match 'Claude|Cowork|Anthropic'
        } | Select-Object -First 1

        if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
            [WinFocus]::ShowWindow($proc.MainWindowHandle, 9)
            [WinFocus]::SetForegroundWindow($proc.MainWindowHandle)
            Write-Log "Focus restored to: $($proc.MainWindowTitle)"
        } else {
            Write-Log "Could not find Claude/Cowork window to restore focus."
        }
    } catch {
        Write-Log "Restore-Focus error: $_"
    }
}

# ── Close a process by name ───────────────────────────────────
function Close-AfterCommand {
    param($ProcessName)
    if (-not $ProcessName) { return }
    try {
        $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($procs) {
            $procs | Stop-Process -Force
            Write-Log "Closed process: $ProcessName"
        }
    } catch {
        Write-Log "Could not close $ProcessName : $_"
    }
}

# ── Post-command cleanup (screenshot → close → focus) ─────────
function Invoke-Cleanup {
    param($TakeScreenshot, $CloseAfter, $RestoreFocus)

    $didScreenshot = $false
    if ($TakeScreenshot) {
        Start-Sleep -Milliseconds 800    # let UI settle
        $didScreenshot = Take-Screenshot -Path $screenshotFile
    }

    if ($CloseAfter) {
        Start-Sleep -Milliseconds 400
        Close-AfterCommand -ProcessName $CloseAfter
    }

    if ($RestoreFocus) {
        Start-Sleep -Milliseconds 300
        Restore-ClaudeFocus
    }

    return $didScreenshot
}

# ── Command handlers ──────────────────────────────────────────
function Invoke-ShellCommand {
    param($cmd, $takeScreenshot, $closeAfter, $restoreFocus)
    try {
        $output = & powershell.exe -NoProfile -NonInteractive -Command $cmd 2>&1 | Out-String
        $status = "success"; $err = ""
    } catch {
        $output = ""; $err = $_.Exception.Message; $status = "error"
    }
    $shot = Invoke-Cleanup -TakeScreenshot $takeScreenshot -CloseAfter $closeAfter -RestoreFocus $restoreFocus
    Write-Result -Status $status -Output $output.Trim() -Err $err -Cmd $cmd -Type "shell" -Screenshot $shot
}

function Invoke-ScriptFile {
    param($scriptName, $takeScreenshot, $closeAfter, $restoreFocus)
    $scriptPath = Join-Path $bridgeDir $scriptName
    if (-not (Test-Path $scriptPath)) {
        Write-Result -Status "error" -Output "" -Err "Script not found: $scriptPath" -Cmd $scriptName -Type "script"
        return
    }
    try {
        $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath 2>&1 | Out-String
        $status = "success"; $err = ""
    } catch {
        $output = ""; $err = $_.Exception.Message; $status = "error"
    }
    $shot = Invoke-Cleanup -TakeScreenshot $takeScreenshot -CloseAfter $closeAfter -RestoreFocus $restoreFocus
    Write-Result -Status $status -Output $output.Trim() -Err $err -Cmd $scriptName -Type "script" -Screenshot $shot
}

function Invoke-FileSearch {
    param($searchData)
    $root       = if ($searchData.root)       { $searchData.root }       else { "C:\" }
    $pattern    = if ($searchData.pattern)    { $searchData.pattern }    else { "*" }
    $extension  = if ($searchData.extension)  { $searchData.extension }  else { "" }
    $maxResults = if ($searchData.maxResults) { $searchData.maxResults } else { 50 }
    try {
        if ($extension) {
            $results = Get-ChildItem -Path $root -Filter "*$extension" -Recurse -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -like "*$pattern*" } |
                       Select-Object -First $maxResults |
                       Select-Object FullName, Name, LastWriteTime, Length
        } else {
            $results = Get-ChildItem -Path $root -Filter "*$pattern*" -Recurse -ErrorAction SilentlyContinue |
                       Select-Object -First $maxResults |
                       Select-Object FullName, Name, LastWriteTime, Length
        }
        Write-Result -Status "success" -Output ($results | ConvertTo-Json -Depth 3) -Err "" -Cmd "search:$pattern" -Type "search"
    } catch {
        Write-Result -Status "error" -Output "" -Err $_.Exception.Message -Cmd "search:$pattern" -Type "search"
    }
}

function Invoke-Screenshot {
    param($restoreFocus)
    $ok = Take-Screenshot -Path $screenshotFile
    if ($restoreFocus) { Start-Sleep -Milliseconds 300; Restore-ClaudeFocus }
    if ($ok) { Write-Result -Status "success" -Output "Screenshot saved." -Err "" -Cmd "screenshot" -Type "screenshot" -Screenshot $true }
    else      { Write-Result -Status "error"   -Output "" -Err "Screenshot failed." -Cmd "screenshot" -Type "screenshot" }
}

# ── Startup ───────────────────────────────────────────────────
Clear-Content -Path $logFile -ErrorAction SilentlyContinue
Write-Log "Claude Bridge v2.1 started."
Write-Log "Bridge folder : $bridgeDir"
Write-Log "Press Ctrl+C to stop."
Write-Log "----------------------------------------------------"
Write-Result -Status "ready" -Output "Claude Bridge v2.1 is running." -Err "" -Cmd "" -Type "ready"

# ── Main loop ─────────────────────────────────────────────────
while ($true) {
    if (Test-Path $commandFile) {
        try {
            $raw  = Get-Content -Path $commandFile -Raw -Encoding UTF8
            $data = $raw | ConvertFrom-Json
            Remove-Item $commandFile -Force -ErrorAction SilentlyContinue

            $type          = if ($data.type)           { $data.type }                       else { "shell" }
            $screenshot    = if ($null -ne $data.screenshot)    { [bool]$data.screenshot }  else { $false }
            $restoreFocus  = if ($null -ne $data.restore_focus) { [bool]$data.restore_focus } else { $false }
            $closeAfter    = if ($data.close_after)    { $data.close_after }                else { $null }

            Write-Log "Command [type=$type restore=$restoreFocus close=$closeAfter]: $($data.command)$($data.script)"

            switch ($type) {
                "shell"      { Invoke-ShellCommand -cmd $data.command -takeScreenshot $screenshot -closeAfter $closeAfter -restoreFocus $restoreFocus }
                "script"     { Invoke-ScriptFile   -scriptName $data.script -takeScreenshot $screenshot -closeAfter $closeAfter -restoreFocus $restoreFocus }
                "search"     { Invoke-FileSearch   -searchData $data }
                "screenshot" { Invoke-Screenshot   -restoreFocus $restoreFocus }
                default      { Invoke-ShellCommand -cmd $data.command -takeScreenshot $screenshot -closeAfter $closeAfter -restoreFocus $restoreFocus }
            }

            Write-Log "Done."
        } catch {
            Write-Log "Parse error: $_"
            Write-Result -Status "error" -Output "" -Err "Failed to parse command: $_" -Cmd "" -Type "unknown"
            Remove-Item $commandFile -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds 300
}
