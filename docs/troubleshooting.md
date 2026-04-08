# Troubleshooting

## Bridge not responding

**Symptom:** `claude-result.json` timestamp doesn't update after sending a command.

**Fixes:**
1. Check the `Start-Bridge.bat` terminal window is still open
2. Look at `claude-bridge.log` in your Claude folder for error messages
3. Close and restart `Start-Bridge.bat`
4. Make sure the Claude folder path in the `.bat` file matches your actual folder

---

## "Execution policy" error when starting the bridge

**Symptom:** Terminal shows a red error about execution policy.

**Fix:** The `.bat` file already includes `-ExecutionPolicy Bypass`. If you're running
`claude-bridge.ps1` directly, run it as:
```
powershell.exe -ExecutionPolicy Bypass -File claude-bridge.ps1
```

---

## `restore_focus` not bringing Claude to the foreground

**Symptom:** Settings or another app stays on top after a command.

**Cause:** The bridge searches for windows with "Claude", "Cowork", or "Anthropic" in the
title. If your window has a different title, it won't be found.

**Fix:** Ask Claude to run this to find the right title:
```json
{ "type": "shell", "command": "Get-Process | Where-Object { $_.MainWindowTitle } | Select-Object Name,MainWindowTitle | Out-String" }
```
Then update the `$titles` array in `claude-bridge.ps1` with your actual window title.

---

## Office COM automation fails

**Symptom:** Script errors like "cannot create COM object" or "ActiveX component can't create object".

**Fixes:**
1. Ensure Microsoft Office is installed (not just Office Online)
2. Try running the script manually in PowerShell to see the full error
3. Some Group Policy settings block COM automation — check with your IT admin if on a work PC

---

## Screenshot is black or blank

**Symptom:** `claude-screenshot.png` exists but is all black.

**Cause:** Usually happens with certain display configurations (multiple monitors, HDR, or
hardware acceleration).

**Fix:** Increase the settle delay in `claude-bridge.ps1` by changing `Start-Sleep -Milliseconds 800`
to `1500` in the `Invoke-Cleanup` function.

---

## Commands are slow

**Symptom:** Responses take 5+ seconds.

**Cause:** Each command spawns a new `powershell.exe` child process, which has a startup cost
of ~1–2 seconds. This is normal. For faster repeated commands, batch them into a single
script file and use the `script` type.

---

## Bridge uses too much memory

**Symptom:** `claude-bridge.ps1` process grows over time.

**Fix:** Restart the bridge. The watcher loop itself is very small (~95 MB) but PowerShell
can accumulate memory over many hours. Restarting takes 2 seconds and resets it cleanly.

---

## Claude can't find a file it should be able to find

**Symptom:** File search returns empty results even though the file exists.

**Fixes:**
1. Check the `root` path — make sure it's correct and uses `\\` for backslashes in JSON
2. The search uses `Get-ChildItem -Recurse` which skips folders it doesn't have permission to access
3. Try a broader search: remove the `extension` field and use just `pattern`
4. Some system and hidden folders are excluded by default — add `-Force` to `Get-ChildItem`
   in `claude-bridge.ps1` if you need to search hidden files
