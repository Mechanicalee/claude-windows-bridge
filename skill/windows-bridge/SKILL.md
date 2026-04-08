---
name: windows-bridge
description: >
  Use this skill whenever the user asks Claude to do ANYTHING on their Windows PC â open apps
  like Excel, Word, Notepad, or any program; run system commands; check what's running; manage
  files via Windows Explorer; change settings; tweak display/sound/power settings; search for
  files; create or edit documents; click buttons or interact with app UIs; or generally control
  their computer. This skill gives Claude real Windows control through a file-based bridge the
  user has set up. Trigger this skill any time the user says things like "open Excel", "launch
  Word", "close that app", "click the OK button", "type in the search box", "what processes are
  running", "find that file", "change my display settings", or any request implying interaction
  with Windows or desktop apps. Don't attempt Windows tasks without reading this skill first.
---

# Windows Bridge v3.0

The user has a PowerShell bridge running on their Windows PC that gives Claude full control.
You write structured JSON commands to a shared folder â bridge executes â writes results and
an optional screenshot back â you read them and decide next steps.

## File locations

All bridge files live in the user's mounted Claude folder. Resolve dynamically if unsure:

```bash
ls /sessions/*/mnt/Claude/
```

Typical path: `/sessions/cool-determined-volta/mnt/Claude/`

| File | Purpose |
|------|---------|
| `claude-command.json` | You write commands here |
| `claude-result.json` | You read results from here |
| `claude-screenshot.png` | Screen capture after command (if requested) |
| `claude-bridge.ps1` | Bridge script (don't modify while running) |
| `Start-Bridge.bat` | User double-clicks to start/restart the bridge |

---

## Step 1 â Always check the bridge first

Read `claude-result.json`. If `status` is `"ready"` or shows a recent result, the bridge is
running. If missing or stale, tell the user:

> "Please double-click **Start-Bridge.bat** in your Claude folder to start the bridge."

---

## Step 2 â Send a command

Write `claude-command.json` using the `Write` tool. All commands share these optional fields:

| Field | Type | Purpose |
|-------|------|---------|
| `screenshot` | bool | Capture screen after command (default: false) |
| `restore_focus` | bool | Bring Claude/Cowork window back to foreground after command (default: false) |
| `close_after` | string | Process name to kill after command, e.g. `"SystemSettings"` |

**Always set `restore_focus: true` for any command that opens a UI window.**

---

## Command types

### Type: `shell` â PowerShell one-liner
```json
{
  "type": "shell",
  "command": "Start-Process ms-settings:display",
  "screenshot": true,
  "restore_focus": true,
  "close_after": "SystemSettings"
}
```

### Type: `script` â Run a .ps1 file from the Claude folder
Write the script first with the `Write` tool, then execute it:
```json
{
  "type": "script",
  "script": "my-task.ps1",
  "screenshot": true,
  "restore_focus": true
}
```

### Type: `search` â Find files on the PC
```json
{
  "type": "search",
  "root": "C:\\Users\\Lee\\Documents",
  "pattern": "invoice",
  "extension": ".docx",
  "maxResults": 20
}
```
`root` defaults to `C:\`. Returns JSON array with FullName, Name, LastWriteTime, Length.

### Type: `screenshot` â Capture screen immediately
```json
{
  "type": "screenshot",
  "restore_focus": true
}
```

---

## UI Automation commands (v3.0)

These commands use the Windows UIAutomation API to find and interact with UI elements
semantically â by name, control type, or automation ID â rather than by pixel coordinates.
This is far more reliable than screenshot-and-guess. Use these for any task that involves
clicking buttons, filling forms, navigating menus, or reading UI state.

### Recommended workflow for UI interaction

1. **Open the app** with a `shell` command + `screenshot: true`
2. **Discover the UI** with `ui_find` (lists all interactive elements)
3. **Interact** with `ui_click` or `ui_type` using element names from step 2
4. **Verify** with `screenshot: true` on the interaction command

---

### Type: `ui_find` â List UI elements in a window

Returns a JSON array of interactive elements. Use this before clicking to discover what's
available and find exact element names.

```json
{
  "type": "ui_find",
  "window_title": "Notepad",
  "screenshot": false
}
```

Filter by control type to reduce noise:
```json
{
  "type": "ui_find",
  "window_title": "Save As",
  "control_type": "Button"
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `window_title` | string | Window to search (partial match OK). Omit to search all windows. |
| `control_type` | string | Optional filter: `"Button"`, `"Edit"`, `"CheckBox"`, `"ComboBox"`, `"MenuItem"`, `"TabItem"`, `"ListItem"`, `"Slider"`, `"RadioButton"`, `"Text"`, etc. |
| `max_results` | int | Max elements to return (default: 50) |
| `include_offscreen` | bool | Include offscreen elements (default: false) |

**Returns** â array of element objects:
```json
[
  { "name": "Save", "type": "Button", "automation_id": "1", "rect": [120, 45, 200, 70], "enabled": true, "visible": true },
  { "name": "Cancel", "type": "Button", "automation_id": "2", "rect": [210, 45, 290, 70], "enabled": true, "visible": true }
]
```

`rect` is `[left, top, right, bottom]` in screen pixels.

---

### Type: `ui_click` â Click a UI element

Clicks by element name or automation ID. Prefers `InvokePattern` (reliable, no mouse move
needed) and falls back to a physical click at the element's centre. Also supports raw
coordinate clicks when UIAutomation isn't needed.

**Click by element name:**
```json
{
  "type": "ui_click",
  "window_title": "Save As",
  "element_name": "Save",
  "screenshot": true
}
```

**Click by automation ID (most stable â use when available):**
```json
{
  "type": "ui_click",
  "window_title": "Save As",
  "automation_id": "1",
  "screenshot": true
}
```

**Narrow by control type to avoid ambiguity:**
```json
{
  "type": "ui_click",
  "window_title": "Notepad",
  "element_name": "File",
  "control_type": "MenuItem",
  "screenshot": true
}
```

**Raw coordinate click (no UIAutomation â use as last resort):**
```json
{
  "type": "ui_click",
  "coordinates": [640, 400],
  "screenshot": true
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `element_name` | string | Name label of the element to click |
| `automation_id` | string | AutomationId (from `ui_find` results) â preferred |
| `control_type` | string | Optional type filter to disambiguate |
| `window_title` | string | Scope search to this window |
| `coordinates` | [x, y] | Raw pixel coordinates (skips element search) |

---

### Type: `ui_type` â Type text into a UI element

Finds an element, focuses it, and types text. Uses `ValuePattern.SetValue()` when available
(direct, no SendKeys escaping needed) or falls back to `SendKeys`.

**Type into a named field:**
```json
{
  "type": "ui_type",
  "window_title": "Save As",
  "element_name": "File name",
  "text": "my-document.docx",
  "screenshot": true
}
```

**Clear existing content first:**
```json
{
  "type": "ui_type",
  "window_title": "Notepad",
  "element_name": "Text Editor",
  "text": "Hello from Claude!",
  "clear_first": true,
  "screenshot": true
}
```

**Type into whatever is currently focused (no element lookup):**
```json
{
  "type": "ui_type",
  "text": "Hello!",
  "screenshot": true
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `text` | string | Text to type (required) |
| `element_name` | string | Focus this element first |
| `automation_id` | string | Focus this element first (preferred) |
| `window_title` | string | Scope element search |
| `clear_first` | bool | Select-all + delete before typing (default: false) |

> **Note on special characters with SendKeys fallback:** Characters like `+`, `^`, `%`, `~`,
> `{`, `}`, `(`, `)` are SendKeys control sequences. If typing into a field that doesn't
> support `ValuePattern`, escape them: `{+}`, `{^}`, etc. The `ValuePattern` path (preferred)
> has no such restrictions.

---

### Type: `ui_tree` â Dump the UI element tree

Returns the full UIAutomation control tree for a window as nested JSON. Use this to
understand an unfamiliar UI's structure before deciding how to interact with it.

```json
{
  "type": "ui_tree",
  "window_title": "Notepad"
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `window_title` | string | Window to dump (partial match OK) |
| `max_depth` | int | Tree depth limit (default: 5, max: 8) |

> For complex windows (Office, browsers), `ui_find` is faster and less verbose than `ui_tree`.
> Use `ui_tree` only when you need to understand the full structure.

---

## Step 3 â Read the result

After writing the command, wait ~1â2 seconds then read the result. Use `Bash` with `cat`
rather than the `Read` tool (which caches and returns stale data):

```bash
sleep 2 && cat /sessions/cool-determined-volta/mnt/Claude/claude-result.json
```

Result format:
```json
{
  "status": "success",
  "output": "...",
  "error": "",
  "command": "...",
  "type": "ui_click",
  "screenshot": true,
  "timestamp": "2026-04-08T13:00:00"
}
```

If `"screenshot": true` in the result, read the image to verify what happened:
```
Read tool â /sessions/cool-determined-volta/mnt/Claude/claude-screenshot.png
```

If `status` is `"error"`, report the error and suggest a fix.
If the timestamp matches the previous result, wait another second and retry (still processing).
Retry up to 5 times before giving up.

---

## UX rules â always follow these

1. **Prefer `ui_click` / `ui_type` over raw shell + SendKeys** for any UI interaction.
   UIAutomation is reliable across window positions and screen resolutions.

2. **Run `ui_find` before clicking** when the window is unfamiliar or has multiple elements
   with similar names. Get the exact name/automation_id first.

3. **Restore focus after every UI action.** Any command that opens a window must include
   `"restore_focus": true` so the user can see Claude's progress.

4. **Close temporary windows when done.** Use `close_after` for Settings, dialogs, and
   helper windows. Common process names: `"SystemSettings"`, `"notepad"`, `"Calculator"`.

5. **Always take a screenshot after opening an app** to confirm it launched.

6. **Confirm before destructive actions.** Deleting files, shutting down, killing system
   processes â always ask the user first.

7. **One step at a time for multi-step workflows.** Send a command, read the result,
   inspect the screenshot, then send the next command.

---

## Common tasks â ready to use

### Open apps
```json
{ "type": "shell", "command": "Start-Process winword", "screenshot": true, "restore_focus": true }
{ "type": "shell", "command": "Start-Process excel",   "screenshot": true, "restore_focus": true }
{ "type": "shell", "command": "Start-Process notepad", "screenshot": true, "restore_focus": true }
```

### Discover what's in a window
```json
{ "type": "ui_find", "window_title": "Notepad", "control_type": "Button" }
{ "type": "ui_find", "window_title": "Save As" }
{ "type": "ui_tree", "window_title": "Control Panel", "max_depth": 3 }
```

### Click UI elements
```json
{ "type": "ui_click", "window_title": "Save As", "element_name": "Save", "screenshot": true }
{ "type": "ui_click", "window_title": "Notepad", "element_name": "File", "control_type": "MenuItem" }
{ "type": "ui_click", "window_title": "Notepad", "automation_id": "MenuBar", "screenshot": true }
```

### Fill in text fields
```json
{ "type": "ui_type", "window_title": "Save As", "element_name": "File name", "text": "report.docx", "screenshot": true }
{ "type": "ui_type", "window_title": "Notepad", "element_name": "Text Editor", "text": "Hello!", "clear_first": true }
```

### Settings pages
```json
{ "type": "shell", "command": "Start-Process ms-settings:display",    "screenshot": true, "restore_focus": true, "close_after": "SystemSettings" }
{ "type": "shell", "command": "Start-Process ms-settings:sound",      "screenshot": true, "restore_focus": true, "close_after": "SystemSettings" }
{ "type": "shell", "command": "Start-Process ms-settings:power-sleep","screenshot": true, "restore_focus": true, "close_after": "SystemSettings" }
```

### System info
```json
{ "type": "shell", "command": "Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name,CPU,WorkingSet | Out-String" }
{ "type": "shell", "command": "Get-PSDrive C | Select-Object Used,Free | Out-String" }
{ "type": "shell", "command": "Get-ComputerInfo | Select-Object OsName,TotalPhysicalMemory | Out-String" }
```

### Create Word doc with content (COM automation)
```powershell
# create-doc.ps1 â save to Claude folder first
$word = New-Object -ComObject Word.Application
$word.Visible = $true
$doc = $word.Documents.Add()
$doc.Range().Text = "Hello from Claude!"
$doc.SaveAs("C:\Users\Lee\Documents\claude-doc.docx")
```
```json
{ "type": "script", "script": "create-doc.ps1", "screenshot": true, "restore_focus": true }
```

### File search
```json
{ "type": "search", "root": "C:\\Users\\Lee", "pattern": "budget", "extension": ".xlsx", "maxResults": 20 }
```

---

## Working with files Claude created

```json
{ "type": "shell", "command": "Start-Process 'C:\\Users\\Lee\\Documents\\Claude\\myfile.docx'", "screenshot": true, "restore_focus": true }
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `claude-result.json` not updating | Bridge stopped â ask user to restart `Start-Bridge.bat` |
| `restore_focus` not working | Check `Get-Process \| Where MainWindowTitle -match 'Claude'` |
| Script not found | Confirm script saved to Claude folder before running |
| `ui_find` returns empty | Window title may not match â try partial title or omit it |
| `ui_click` element not found | Run `ui_find` first to get exact name; try `ui_tree` for structure |
| `ui_type` special chars wrong | Use `ValuePattern` path (set element_name/automation_id); or escape SendKeys chars |
| UIAutomation unavailable | Very rare â requires .NET Framework (built-in on Win 10/11) |
| Office COM fails | Office may not be installed or COM automation blocked by policy |
