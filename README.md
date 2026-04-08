# Claude Windows Bridge

Give Claude full control of your Windows PC through a lightweight file-based bridge.

Claude writes commands to a shared folder → a PowerShell watcher executes them → results
(and optional screenshots) are written back → Claude reads and reacts. No server, no cloud
relay, no special software — just PowerShell and a shared folder.

---

## What it enables

- **Open any app** — Excel, Word, Notepad, Settings, or any installed program
- **Run PowerShell** — arbitrary commands, scripts, system queries
- **Search files** — find anything on your PC by name, type, or location
- **Office automation** — create/edit Word docs and Excel sheets via COM
- **Network capture** — integrate with Wireshark/tshark for traffic analysis
- **Screenshots** — Claude sees your screen after each action and reacts intelligently
- **Focus restore** — Claude automatically brings itself back to the foreground after opening windows

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1+ (built-in on Windows 10/11)
- [Claude desktop app (Cowork)](https://claude.ai) with a Pro, Max, Team or Enterprise plan
- A folder shared between Claude (Cowork) and your PC — your Claude workspace folder

---

## Setup (5 minutes)

### Step 1 — Copy the bridge files

Copy `claude-bridge.ps1` and `Start-Bridge.bat` into your Claude workspace folder
(the folder you selected when setting up Cowork — typically something like
`Documents\Claude`).

### Step 2 — Install the skill

In the Claude desktop app:
1. Open the `skill/` folder in this repo
2. Double-click `windows-bridge.skill` to install it
   *(or drag it into the Claude app)*

This teaches Claude how to use the bridge in every future session — no setup needed again.

### Step 3 — Start the bridge

Double-click **`Start-Bridge.bat`**.

A terminal window opens and shows:
```
Claude Bridge v2.1 started.
Bridge folder: C:\Users\...\Documents\Claude
Press Ctrl+C to stop.
```

Keep this window open (minimise it). Claude now has Windows control.

### Step 4 — Talk to Claude

Start a new Claude session and just ask:

> *"Open Excel"*
> *"Find all PDF files in my Documents folder"*
> *"What are the top 10 processes using CPU right now?"*
> *"Open Word and create a new document called Meeting Notes"*
> *"Show me my display settings"*

Claude will use the bridge automatically.

---

## How it works

```
Claude (Cowork)                    Your Windows PC
──────────────                     ────────────────
Write claude-command.json    →     Bridge watches for the file
                                   Bridge executes the command
Read claude-result.json      ←     Bridge writes result + screenshot
Read claude-screenshot.png   ←     (if screenshot was requested)
```

The bridge polls for new commands every 300ms — typical round-trip latency is under 1 second.

### Command format

```json
{
  "type": "shell",
  "command": "Start-Process winword",
  "screenshot": true,
  "restore_focus": true,
  "close_after": "SystemSettings"
}
```

| Field | Values | Description |
|-------|--------|-------------|
| `type` | `shell`, `script`, `search`, `screenshot` | Command type |
| `command` | PowerShell expression | For `shell` type |
| `script` | filename.ps1 | For `script` type — must be in the Claude folder |
| `screenshot` | `true`/`false` | Capture screen after command |
| `restore_focus` | `true`/`false` | Bring Claude window back to foreground |
| `close_after` | process name | Kill this process after command (e.g. `"SystemSettings"`) |

For file search:
```json
{
  "type": "search",
  "root": "C:\\Users\\Lee\\Documents",
  "pattern": "invoice",
  "extension": ".xlsx",
  "maxResults": 30
}
```

---

## Performance impact

Tested on a typical Windows 11 machine over 150 samples (50s monitoring window):

| Metric | Idle | Active |
|--------|------|--------|
| System CPU | 8.18% | 9.28% |
| Bridge memory | 95.59 MB | 95.62 MB |
| CPU overhead | — | +1.1% |

**Verdict:** The bridge is safe to leave running all day. CPU overhead during active use is
under 2%, and memory usage is flat. Child PowerShell processes spin up briefly per command
then exit immediately.

---

## File reference

```
claude-windows-bridge/
├── README.md                     This file
├── claude-bridge.ps1             The bridge watcher script
├── Start-Bridge.bat              Double-click to launch
├── skill/
│   └── windows-bridge/
│       └── SKILL.md              Claude skill — install this
└── docs/
    ├── advanced-usage.md         COM automation, tshark, display settings
    └── troubleshooting.md        Common issues and fixes
```

---

## Auto-start on login (optional)

To have the bridge start automatically when you log in:

1. Press `Win + R`, type `shell:startup`, press Enter
2. Create a shortcut to `Start-Bridge.bat` in the folder that opens
3. The bridge will now launch silently on every login

---

## Security notes

- The bridge executes **any PowerShell** Claude writes to `claude-command.json`
- Claude (via Anthropic) will always confirm before destructive actions
- The shared folder should only be accessible to your user account
- Do not share your Claude workspace folder publicly
- You can stop the bridge instantly by closing the `Start-Bridge.bat` terminal window

---

## Extending the bridge

The bridge is intentionally simple — one file, one loop. To extend it:

- **Add a new command type:** add a case to the `switch` block in `claude-bridge.ps1`
- **Add persistent state:** write/read additional JSON files in the bridge folder
- **Add GUI automation:** integrate [AutoHotkey](https://www.autohotkey.com/) scripts called
  from PowerShell for click-level UI control
- **Update the skill:** edit `skill/windows-bridge/SKILL.md` and reinstall the `.skill` file

Pull requests welcome!

---

## Contributing

1. Fork this repo
2. Make your changes
3. Test with the performance monitor (`docs/advanced-usage.md`)
4. Open a PR with a description of what you changed and why

---

## Licence

MIT — do whatever you like with it.
