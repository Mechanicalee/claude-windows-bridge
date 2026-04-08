---
name: windows-bridge
description: >
  Use this skill whenever the user asks Claude to do ANYTHING on their Windows PC — open apps
  like Excel, Word, Notepad, or any program; run system commands; check what's running; manage
  files via Windows Explorer; change settings; tweak display/sound/power settings; search for
  files; create or edit documents; or generally control their computer. This skill gives Claude
  real Windows control through a file-based bridge the user has set up. Trigger this skill any
  time the user says things like "open Excel", "launch Word", "close that app", "what processes
  are running", "find that file", "change my display settings", "create a new document", "run
  this on my PC", "can you open...", or any request implying interaction with Windows or desktop
  apps. Don't attempt Windows tasks without reading this skill first.
---

# Windows Bridge v2.1

The user has a PowerShell bridge running on their Windows PC that gives Claude full control.
You write structured JSON commands to a shared folder → bridge executes → writes results and
an optional screenshot back → you read them and decide next steps.

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

## Step 1 — Always check the bridge first

Read `claude-result.json`. If `status` is `"ready"` or shows a recent result, the bridge is
running. If missing or stale, tell the user:

> "Please double-click **Start-Bridge.bat** in your Claude folder to start the bridge."

---

## Step 2 — Send a command

Write `claude-command.json` using the `Write` tool. All commands share these optional fields:

| Field | Type | Purpose |
|-------|------|---------|
| `screenshot` | bool | Capture screen after command (default: false) |
| `restore_focus` | bool | Bring Claude/Cowork window back to foreground after command (default: false) |
| `close_after` | string | Process name to kill after command, e.g. `"SystemSettings"` |

**Always set `restore_focus: true` for any command that opens a UI window** — this brings
Claude back to the foreground so the user can see progress. Always set `close_after` for
temporary windows (Settings, dialogs) once you've finished with them.

### Type: `shell` — PowerShell one-liner
```json
{
  "type": "shell",
  "command": "Start-Process ms-settings:display",
  "screenshot": true,
  "restore_focus": true,
  "close_after": "SystemSettings"
}
```

### Type: `script` — Run a .ps1 file from the Claude folder
Write the script first with the `Write` tool, then execute it:
```json
{
  "type": "script",
  "script": "my-task.ps1",
  "screenshot": true,
  "restore_focus": true
}
```

### Type: `search` — Find files on the PC
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

### Type: `screenshot` — Capture screen immediately
```json
{
  "type": "screenshot",
  "restore_focus": true
}
```

---

## Step 3 — Read the result

After writing the command, wait ~1–2 seconds then read the result. Use `Bash` with `cat`
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
  "type": "shell",
  "screenshot": true,
  "timestamp": "2026-04-08T13:00:00"
}
```

If `"screenshot": true` in the result, read the image to see what happened on screen:

```
Read tool → /sessions/cool-determined-volta/mnt/Claude/claude-screenshot.png
```

If `status` is `"error"`, report the error and suggest a fix.
If the timestamp matches the previous result, wait another second and try again (still
processing). Retry up to 5 times before giving up.

---

## UX rules — always follow these

1. **Restore focus after every UI action.** Any command that opens a window
   (`Start-Process`, settings, apps) must include `"restore_focus": true` so the user can
   see Claude's progress without switching windows manually.

2. **Close temporary windows when done.** Settings pages, dialogs, and helper windows
   should be closed with `close_after` once you've finished with them. Common process names:
   - Windows Settings: `"SystemSettings"`
   - Notepad: `"notepad"`
   - Calculator: `"Calculator"`
   - File Explorer: `"explorer"` (use carefully — closes all Explorer windows)

3. **Always take a screenshot after opening an app.** This confirms it launched and lets
   you verify the state before proceeding with further commands.

4. **Confirm before destructive actions.** Deleting files, shutting down, killing system
   processes — always ask the user first.

5. **One step at a time for multi-step workflows.** Send a command, read the result,
   inspect the screenshot, then send the next command. Don't batch irreversible actions.

---

## Common tasks — ready to use

### Open apps (always restore focus)
```json
{ "type": "shell", "command": "Start-Process winword", "screenshot": true, "restore_focus": true }
{ "type": "shell", "command": "Start-Process excel",   "screenshot": true, "restore_focus": true }
{ "type": "shell", "command": "Start-Process notepad", "screenshot": true, "restore_focus": true }
{ "type": "shell", "command": "Start-Process 'C:\\path\\to\\file.xlsx'", "screenshot": true, "restore_focus": true }
```

### Check and close Settings pages
```json
{ "type": "shell", "command": "Start-Process ms-settings:display",    "screenshot": true, "restore_focus": true, "close_after": "SystemSettings" }
{ "type": "shell", "command": "Start-Process ms-settings:sound",      "screenshot": true, "restore_focus": true, "close_after": "SystemSettings" }
{ "type": "shell", "command": "Start-Process ms-settings:power-sleep","screenshot": true, "restore_focus": true, "close_after": "SystemSettings" }
```

### System info (no UI — no restore needed)
```json
{ "type": "shell", "command": "Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name,CPU,WorkingSet | Out-String" }
{ "type": "shell", "command": "Get-PSDrive C | Select-Object Used,Free | Out-String" }
{ "type": "shell", "command": "Get-ComputerInfo | Select-Object OsName,TotalPhysicalMemory | Out-String" }
{ "type": "shell", "command": "Get-NetAdapter | Select-Object Name,Status,LinkSpeed | Out-String" }
```

### Create Word doc with content (COM automation)
Write a script, then run it:
```powershell
# create-doc.ps1 — save to Claude folder first
$word = New-Object -ComObject Word.Application
$word.Visible = $true
$doc = $word.Documents.Add()
$doc.Range().Text = "Hello from Claude!"
$doc.SaveAs("C:\Users\Lee\Documents\claude-doc.docx")
```
```json
{ "type": "script", "script": "create-doc.ps1", "screenshot": true, "restore_focus": true }
```

### Create Excel workbook with data
```powershell
# create-sheet.ps1
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $true
$wb = $xl.Workbooks.Add()
$ws = $wb.Sheets.Item(1)
$ws.Cells.Item(1,1) = "Name"; $ws.Cells.Item(1,2) = "Value"
$ws.Cells.Item(2,1) = "Claude"; $ws.Cells.Item(2,2) = 42
$wb.SaveAs("C:\Users\Lee\Documents\claude-sheet.xlsx")
```

### File search
```json
{ "type": "search", "root": "C:\\Users\\Lee", "pattern": "budget", "extension": ".xlsx", "maxResults": 20 }
```

### Network traffic capture (requires Wireshark/tshark installed)
```json
{ "type": "shell", "command": "& 'C:\\Program Files\\Wireshark\\tshark.exe' -i 5 -a duration:15 -w 'C:\\Users\\Lee\\Documents\\Claude\\capture.pcapng' 2>&1 | Out-String" }
```

---

## Working with files Claude created

Claude can create `.docx`, `.xlsx`, `.pptx` and other files using its own file skills and
save them to the Claude folder. To open one on Windows:
```json
{ "type": "shell", "command": "Start-Process 'C:\\Users\\Lee\\Documents\\Claude\\myfile.docx'", "screenshot": true, "restore_focus": true }
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `claude-result.json` not updating | Bridge stopped — ask user to restart `Start-Bridge.bat` |
| `restore_focus` not working | Claude window title may differ — check `Get-Process \| Where MainWindowTitle -match 'Claude'` |
| Script not found error | Confirm script was saved to the Claude folder before running |
| Long-running command timeout | Warn user, use tshark/etc with duration limits |
| Office COM fails | Office may not be installed or COM automation blocked by policy |
