# =============================================================
#  Claude Bridge v3.0 - Full Windows Control + UI Automation
#  Run this script to allow Claude to control your Windows PC.
#
#  Command types:
#    shell      — PowerShell one-liner
#    script     — Run a .ps1 file from the Claude folder
#    search     — Find files on the PC
#    screenshot — Capture screen immediately
#    ui_find    — List interactive UI elements in a window
#    ui_click   — Click a UI element by name, automation ID, or coordinates
#    ui_type    — Type text into a UI element or the active focus
#    ui_tree    — Dump the full UI automation tree of a window
#
#  Shared fields (all types):
#    screenshot    : true/false — capture screen after command
#    restore_focus : true/false — bring Claude/Cowork back to foreground
#    close_after   : process name to kill after command
#
#  Files:
#    claude-command.json   — Claude writes commands here
#    claude-result.json    — Bridge writes results here
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

# ── Native Win32 types (defined once at startup) ──────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class NativeWin {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int cButtons, int dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    public const int SW_RESTORE = 9;
    public const int MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const int MOUSEEVENTF_LEFTUP   = 0x0004;
    public static void LeftClick(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTDOWN, x, y, 0, 0);
        System.Threading.Thread.Sleep(30);
        mouse_event(MOUSEEVENTF_LEFTUP,   x, y, 0, 0);
    }
}
"@ -ErrorAction SilentlyContinue

# ── UIAutomation assembly loading ─────────────────────────────
$script:uiaLoaded = $false
function Ensure-UIAutomation {
    if ($script:uiaLoaded) { return $true }
    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        Add-Type -AssemblyName UIAutomationTypes  -ErrorAction Stop
        $script:uiaLoaded = $true
        Write-Log "UIAutomation loaded."
        return $true
    } catch {
        Write-Log "UIAutomation load failed: $_"
        return $false
    }
}

# ── Screenshot ────────────────────────────────────────────────
function Take-Screenshot {
    param($Path)
    try {
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

# ── Focus restore ─────────────────────────────────────────────
function Restore-ClaudeFocus {
    try {
        $titles = @("Claude", "Cowork", "Claude - Cowork", "Anthropic")
        foreach ($title in $titles) {
            $hwnd = [NativeWin]::FindWindow([NullString]::Value, $title)
            if ($hwnd -ne [IntPtr]::Zero) {
                [NativeWin]::ShowWindow($hwnd, [NativeWin]::SW_RESTORE)
                [NativeWin]::SetForegroundWindow($hwnd)
                Write-Log "Focus restored to: $title"
                return
            }
        }
        $proc = Get-Process | Where-Object {
            $_.MainWindowTitle -match 'Claude|Cowork|Anthropic'
        } | Select-Object -First 1
        if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
            [NativeWin]::ShowWindow($proc.MainWindowHandle, [NativeWin]::SW_RESTORE)
            [NativeWin]::SetForegroundWindow($proc.MainWindowHandle)
            Write-Log "Focus restored to: $($proc.MainWindowTitle)"
        } else {
            Write-Log "Could not find Claude/Cowork window."
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
        if ($procs) { $procs | Stop-Process -Force; Write-Log "Closed: $ProcessName" }
    } catch { Write-Log "Could not close $ProcessName : $_" }
}

# ── Post-command cleanup ──────────────────────────────────────
function Invoke-Cleanup {
    param($TakeScreenshot, $CloseAfter, $RestoreFocus)
    $didScreenshot = $false
    if ($TakeScreenshot) {
        Start-Sleep -Milliseconds 800
        $didScreenshot = Take-Screenshot -Path $screenshotFile
    }
    if ($CloseAfter) { Start-Sleep -Milliseconds 400; Close-AfterCommand -ProcessName $CloseAfter }
    if ($RestoreFocus) { Start-Sleep -Milliseconds 300; Restore-ClaudeFocus }
    return $didScreenshot
}

# ── Standard command handlers ─────────────────────────────────
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

# ── UI Automation helpers ─────────────────────────────────────

# Map friendly type names to ControlType objects
function Get-ControlTypeObj {
    param($typeName)
    if (-not $typeName) { return $null }
    $map = @{
        "Button"      = [System.Windows.Automation.ControlType]::Button
        "CheckBox"    = [System.Windows.Automation.ControlType]::CheckBox
        "ComboBox"    = [System.Windows.Automation.ControlType]::ComboBox
        "Edit"        = [System.Windows.Automation.ControlType]::Edit
        "Hyperlink"   = [System.Windows.Automation.ControlType]::Hyperlink
        "Image"       = [System.Windows.Automation.ControlType]::Image
        "List"        = [System.Windows.Automation.ControlType]::List
        "ListItem"    = [System.Windows.Automation.ControlType]::ListItem
        "Menu"        = [System.Windows.Automation.ControlType]::Menu
        "MenuBar"     = [System.Windows.Automation.ControlType]::MenuBar
        "MenuItem"    = [System.Windows.Automation.ControlType]::MenuItem
        "RadioButton" = [System.Windows.Automation.ControlType]::RadioButton
        "ScrollBar"   = [System.Windows.Automation.ControlType]::ScrollBar
        "Slider"      = [System.Windows.Automation.ControlType]::Slider
        "Spinner"     = [System.Windows.Automation.ControlType]::Spinner
        "Tab"         = [System.Windows.Automation.ControlType]::Tab
        "TabItem"     = [System.Windows.Automation.ControlType]::TabItem
        "Text"        = [System.Windows.Automation.ControlType]::Text
        "ToolBar"     = [System.Windows.Automation.ControlType]::ToolBar
        "Tree"        = [System.Windows.Automation.ControlType]::Tree
        "TreeItem"    = [System.Windows.Automation.ControlType]::TreeItem
        "DataGrid"    = [System.Windows.Automation.ControlType]::DataGrid
        "DataItem"    = [System.Windows.Automation.ControlType]::DataItem
        "Document"    = [System.Windows.Automation.ControlType]::Document
        "SplitButton" = [System.Windows.Automation.ControlType]::SplitButton
        "Window"      = [System.Windows.Automation.ControlType]::Window
        "Pane"        = [System.Windows.Automation.ControlType]::Pane
        "Group"       = [System.Windows.Automation.ControlType]::Group
        "Table"       = [System.Windows.Automation.ControlType]::Table
        "Separator"   = [System.Windows.Automation.ControlType]::Separator
        "Custom"      = [System.Windows.Automation.ControlType]::Custom
    }
    return $map[$typeName]
}

# Find top-level window element by title (exact, then partial match)
function Find-WindowElement {
    param($windowTitle)
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    if (-not $windowTitle) { return $root }

    # Exact match
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $windowTitle)
    $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if ($win) { return $win }

    # Partial match
    $allWindows = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $allWindows) {
        if ($w.Current.Name -match [regex]::Escape($windowTitle)) { return $w }
    }
    return $null
}

# Serialise a single element to a plain object
function Format-Element {
    param($el)
    $r = $el.Current.BoundingRectangle
    return @{
        name          = $el.Current.Name
        type          = $el.Current.ControlType.ProgrammaticName -replace "ControlType\.", ""
        automation_id = $el.Current.AutomationId
        rect          = @([int]$r.Left, [int]$r.Top, [int]$r.Right, [int]$r.Bottom)
        enabled       = $el.Current.IsEnabled
        visible       = (-not $el.Current.IsOffscreen)
    }
}

# Locate a specific element by name or automation_id within a window
function Find-TargetElement {
    param($data)
    $root = Find-WindowElement -windowTitle $data.window_title
    if (-not $root) { return $null }

    # Prefer automation_id (most stable)
    if ($data.automation_id) {
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $data.automation_id)
        $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
        if ($el) { return $el }
    }

    # Name match, optionally filtered by control type
    if ($data.element_name) {
        $nameCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $data.element_name)
        $ctObj = Get-ControlTypeObj -typeName $data.control_type
        if ($ctObj) {
            $typeCond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ctObj)
            $cond = New-Object System.Windows.Automation.AndCondition($nameCond, $typeCond)
        } else {
            $cond = $nameCond
        }
        $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
        if ($el) { return $el }

        # Partial name fallback
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($e in $all) {
            if ($e.Current.Name -match [regex]::Escape($data.element_name)) { return $e }
        }
    }
    return $null
}

# Recursively build element tree (used by ui_tree)
function Build-ElementTree {
    param($element, [int]$depth = 0, [int]$maxDepth = 5)
    if ($depth -gt $maxDepth) { return $null }
    $r = $element.Current.BoundingRectangle
    $node = [ordered]@{
        name          = $element.Current.Name
        type          = $element.Current.ControlType.ProgrammaticName -replace "ControlType\.", ""
        automation_id = $element.Current.AutomationId
        rect          = @([int]$r.Left, [int]$r.Top, [int]$r.Right, [int]$r.Bottom)
        enabled       = $element.Current.IsEnabled
        children      = @()
    }
    try {
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $child  = $walker.GetFirstChild($element)
        while ($child) {
            $childNode = Build-ElementTree -element $child -depth ($depth + 1) -maxDepth $maxDepth
            if ($childNode) { $node.children += $childNode }
            $child = $walker.GetNextSibling($child)
        }
    } catch {}
    return $node
}

# ── UI Automation command handlers ────────────────────────────

# ui_find — list interactive elements in a window
# Fields: window_title (opt), control_type (opt), max_results (opt, default 50)
function Invoke-UIFind {
    param($data)
    if (-not (Ensure-UIAutomation)) {
        Write-Result -Status "error" -Output "" -Err "UIAutomation unavailable." -Cmd "ui_find" -Type "ui_find"; return
    }
    try {
        $root = Find-WindowElement -windowTitle $data.window_title
        if (-not $root -and $data.window_title) {
            Write-Result -Status "error" -Output "" -Err "Window not found: $($data.window_title)" -Cmd "ui_find" -Type "ui_find"; return
        }

        $ctObj = Get-ControlTypeObj -typeName $data.control_type
        $cond  = if ($ctObj) {
            New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ctObj)
        } else {
            [System.Windows.Automation.Condition]::TrueCondition
        }

        $scope      = if ($data.window_title) { [System.Windows.Automation.TreeScope]::Descendants } `
                      else                    { [System.Windows.Automation.TreeScope]::Children }
        $elements   = $root.FindAll($scope, $cond)
        $maxResults = if ($data.max_results) { [int]$data.max_results } else { 50 }

        $results = @()
        $n = 0
        foreach ($el in $elements) {
            if ($n -ge $maxResults) { break }
            # Skip invisible/offscreen elements unless caller asked for all
            if ($el.Current.IsOffscreen -and -not $data.include_offscreen) { continue }
            $results += Format-Element -el $el
            $n++
        }

        $shot = Invoke-Cleanup -TakeScreenshot ([bool]$data.screenshot) -CloseAfter $data.close_after -RestoreFocus ([bool]$data.restore_focus)
        Write-Result -Status "success" -Output ($results | ConvertTo-Json -Depth 5 -Compress) -Err "" -Cmd "ui_find" -Type "ui_find" -Screenshot $shot
    } catch {
        Write-Result -Status "error" -Output "" -Err $_.Exception.Message -Cmd "ui_find" -Type "ui_find"
    }
}

# ui_click — click a UI element or raw screen coordinates
# Fields:
#   element_name (opt)   — name label of the element
#   automation_id (opt)  — AutomationId of the element
#   control_type (opt)   — narrow search to this type (e.g. "Button")
#   window_title (opt)   — scope search to this window
#   coordinates (opt)    — [x, y] pixel coords (skips element search)
function Invoke-UIClick {
    param($data)

    # ── Raw coordinate click (no UIAutomation needed) ──────────
    if ($data.coordinates) {
        $x = [int]$data.coordinates[0]
        $y = [int]$data.coordinates[1]
        [NativeWin]::LeftClick($x, $y)
        $shot = Invoke-Cleanup -TakeScreenshot ([bool]$data.screenshot) -CloseAfter $data.close_after -RestoreFocus ([bool]$data.restore_focus)
        Write-Result -Status "success" -Output "Clicked at [$x, $y]." -Err "" -Cmd "ui_click" -Type "ui_click" -Screenshot $shot
        return
    }

    # ── Element-based click ────────────────────────────────────
    if (-not (Ensure-UIAutomation)) {
        Write-Result -Status "error" -Output "" -Err "UIAutomation unavailable." -Cmd "ui_click" -Type "ui_click"; return
    }
    try {
        $el = Find-TargetElement -data $data
        if (-not $el) {
            $target = if ($data.element_name) { $data.element_name } `
                      elseif ($data.automation_id) { $data.automation_id } else { "(unknown)" }
            Write-Result -Status "error" -Output "" -Err "Element not found: $target" -Cmd "ui_click" -Type "ui_click"
            return
        }

        # Prefer InvokePattern — works for buttons without moving the mouse
        $invokePattern = $null
        try { $invokePattern = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern) } catch {}

        if ($invokePattern) {
            $invokePattern.Invoke()
            $msg = "Invoked: '$($el.Current.Name)'"
        } else {
            # Fall back to physical click at element centre
            $r  = $el.Current.BoundingRectangle
            $cx = [int]($r.Left + $r.Width  / 2)
            $cy = [int]($r.Top  + $r.Height / 2)
            [NativeWin]::LeftClick($cx, $cy)
            $msg = "Clicked '$($el.Current.Name)' at [$cx, $cy]"
        }

        $shot = Invoke-Cleanup -TakeScreenshot ([bool]$data.screenshot) -CloseAfter $data.close_after -RestoreFocus ([bool]$data.restore_focus)
        Write-Result -Status "success" -Output $msg -Err "" -Cmd "ui_click" -Type "ui_click" -Screenshot $shot
    } catch {
        Write-Result -Status "error" -Output "" -Err $_.Exception.Message -Cmd "ui_click" -Type "ui_click"
    }
}

# ui_type — type text into a UI element or the currently focused field
# Fields:
#   text (required)      — text to type
#   element_name (opt)   — focus this element first
#   automation_id (opt)  — focus this element first (preferred over element_name)
#   window_title (opt)   — scope element search
#   clear_first (opt)    — select-all + delete before typing (default: false)
function Invoke-UIType {
    param($data)
    $text = if ($data.text) { [string]$data.text } else { "" }

    # ── If an element is specified, locate and focus it ────────
    if ($data.element_name -or $data.automation_id) {
        if (-not (Ensure-UIAutomation)) {
            Write-Result -Status "error" -Output "" -Err "UIAutomation unavailable." -Cmd "ui_type" -Type "ui_type"; return
        }
        try {
            $el = Find-TargetElement -data $data
            if (-not $el) {
                $target = if ($data.element_name) { $data.element_name } else { $data.automation_id }
                Write-Result -Status "error" -Output "" -Err "Element not found: $target" -Cmd "ui_type" -Type "ui_type"
                return
            }

            # Try ValuePattern — directly sets value, no SendKeys escaping needed
            $vp = $null
            try { $vp = $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern) } catch {}

            if ($vp -and -not $vp.Current.IsReadOnly) {
                if ($data.clear_first) { $vp.SetValue("") }
                $vp.SetValue($text)
                $shot = Invoke-Cleanup -TakeScreenshot ([bool]$data.screenshot) -CloseAfter $data.close_after -RestoreFocus ([bool]$data.restore_focus)
                Write-Result -Status "success" -Output "Set value on '$($el.Current.Name)': $text" -Err "" -Cmd "ui_type" -Type "ui_type" -Screenshot $shot
                return
            }

            # Fall back: click to focus the element
            $r  = $el.Current.BoundingRectangle
            $cx = [int]($r.Left + $r.Width  / 2)
            $cy = [int]($r.Top  + $r.Height / 2)
            [NativeWin]::LeftClick($cx, $cy)
            Start-Sleep -Milliseconds 150
        } catch {
            Write-Result -Status "error" -Output "" -Err $_.Exception.Message -Cmd "ui_type" -Type "ui_type"; return
        }
    }

    # ── SendKeys to active focus ───────────────────────────────
    try {
        if ($data.clear_first) {
            [System.Windows.Forms.SendKeys]::SendWait("^a")
            Start-Sleep -Milliseconds 80
            [System.Windows.Forms.SendKeys]::SendWait("{DELETE}")
            Start-Sleep -Milliseconds 80
        }
        [System.Windows.Forms.SendKeys]::SendWait($text)
        $shot = Invoke-Cleanup -TakeScreenshot ([bool]$data.screenshot) -CloseAfter $data.close_after -RestoreFocus ([bool]$data.restore_focus)
        Write-Result -Status "success" -Output "Typed: $text" -Err "" -Cmd "ui_type" -Type "ui_type" -Screenshot $shot
    } catch {
        Write-Result -Status "error" -Output "" -Err $_.Exception.Message -Cmd "ui_type" -Type "ui_type"
    }
}

# ui_tree — dump the UIAutomation control tree for a window
# Fields:
#   window_title (opt)  — target window (defaults to entire desktop)
#   max_depth (opt)     — tree depth limit (default 5, max 8)
function Invoke-UITree {
    param($data)
    if (-not (Ensure-UIAutomation)) {
        Write-Result -Status "error" -Output "" -Err "UIAutomation unavailable." -Cmd "ui_tree" -Type "ui_tree"; return
    }
    try {
        $root = Find-WindowElement -windowTitle $data.window_title
        if (-not $root -and $data.window_title) {
            Write-Result -Status "error" -Output "" -Err "Window not found: $($data.window_title)" -Cmd "ui_tree" -Type "ui_tree"; return
        }
        $maxDepth = [Math]::Min((if ($data.max_depth) { [int]$data.max_depth } else { 5 }), 8)
        $tree     = Build-ElementTree -element $root -depth 0 -maxDepth $maxDepth
        Write-Result -Status "success" -Output ($tree | ConvertTo-Json -Depth 20 -Compress) -Err "" -Cmd "ui_tree" -Type "ui_tree"
    } catch {
        Write-Result -Status "error" -Output "" -Err $_.Exception.Message -Cmd "ui_tree" -Type "ui_tree"
    }
}

# ── Startup ───────────────────────────────────────────────────
Clear-Content -Path $logFile -ErrorAction SilentlyContinue
Write-Log "Claude Bridge v3.0 started."
Write-Log "Bridge folder : $bridgeDir"
Write-Log "Press Ctrl+C to stop."
Write-Log "----------------------------------------------------"
Write-Result -Status "ready" -Output "Claude Bridge v3.0 is running." -Err "" -Cmd "" -Type "ready"

# ── Main loop ─────────────────────────────────────────────────
while ($true) {
    if (Test-Path $commandFile) {
        try {
            $raw  = Get-Content -Path $commandFile -Raw -Encoding UTF8
            $data = $raw | ConvertFrom-Json
            Remove-Item $commandFile -Force -ErrorAction SilentlyContinue

            $type = if ($data.type) { $data.type } else { "shell" }
            Write-Log "Command [type=$type]: $($data.command)$($data.script)$($data.element_name)$($data.automation_id)"

            switch ($type) {
                "shell"      { Invoke-ShellCommand -cmd $data.command -takeScreenshot ([bool]$data.screenshot) -closeAfter $data.close_after -restoreFocus ([bool]$data.restore_focus) }
                "script"     { Invoke-ScriptFile   -scriptName $data.script -takeScreenshot ([bool]$data.screenshot) -closeAfter $data.close_after -restoreFocus ([bool]$data.restore_focus) }
                "search"     { Invoke-FileSearch   -searchData $data }
                "screenshot" { Invoke-Screenshot   -restoreFocus ([bool]$data.restore_focus) }
                "ui_find"    { Invoke-UIFind        -data $data }
                "ui_click"   { Invoke-UIClick       -data $data }
                "ui_type"    { Invoke-UIType        -data $data }
                "ui_tree"    { Invoke-UITree        -data $data }
                default      { Invoke-ShellCommand -cmd $data.command -takeScreenshot ([bool]$data.screenshot) -closeAfter $data.close_after -restoreFocus ([bool]$data.restore_focus) }
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
