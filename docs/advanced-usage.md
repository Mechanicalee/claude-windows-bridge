# Advanced Usage

## Office COM Automation

PowerShell can control Word and Excel directly via COM objects, giving Claude full programmatic
access to create and edit Office documents.

### Create a Word document

Save this as `create-doc.ps1` in your Claude folder, then ask Claude to run it:

```powershell
$word = New-Object -ComObject Word.Application
$word.Visible = $true
$doc = $word.Documents.Add()

# Add a heading
$range = $doc.Range()
$range.Style = "Heading 1"
$range.Text = "My Document"
$range.Collapse(0)   # collapse to end

# Add body text
$range.Text = "`nCreated by Claude via Windows Bridge."
$doc.SaveAs("C:\Users\YourName\Documents\claude-doc.docx")
```

### Create an Excel workbook with data and a chart

```powershell
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $true
$wb = $xl.Workbooks.Add()
$ws = $wb.Sheets.Item(1)

# Write headers and data
$ws.Cells.Item(1,1) = "Month";  $ws.Cells.Item(1,2) = "Sales"
$ws.Cells.Item(2,1) = "Jan";    $ws.Cells.Item(2,2) = 12000
$ws.Cells.Item(3,1) = "Feb";    $ws.Cells.Item(3,2) = 15000
$ws.Cells.Item(4,1) = "Mar";    $ws.Cells.Item(4,2) = 13500

# Add a chart
$chart = $ws.Shapes.AddChart2(-1, 51).Chart   # xlColumnClustered
$chart.SetSourceData($ws.Range("A1:B4"))

$wb.SaveAs("C:\Users\YourName\Documents\sales.xlsx")
$xl.Quit()
```

---

## Network Traffic Capture (Wireshark/tshark)

Requires [Wireshark](https://www.wireshark.org/) to be installed.

### List available interfaces
```json
{ "type": "shell", "command": "& 'C:\\Program Files\\Wireshark\\tshark.exe' -D 2>&1 | Out-String" }
```

### Capture 30 seconds of traffic on Wi-Fi (usually interface 5)
```json
{ "type": "shell", "command": "& 'C:\\Program Files\\Wireshark\\tshark.exe' -i 5 -a duration:30 -w 'C:\\Users\\YourName\\Documents\\Claude\\capture.pcapng' 2>&1 | Out-String" }
```

### Extract DNS queries from a capture
```json
{ "type": "shell", "command": "& 'C:\\Program Files\\Wireshark\\tshark.exe' -r 'C:\\Users\\YourName\\Documents\\Claude\\capture.pcapng' -Y 'dns.flags.response==0' -T fields -e 'dns.qry.name' 2>&1 | Sort-Object -Unique | Out-String" }
```

### Extract HTTPS hostnames (SNI)
```json
{ "type": "shell", "command": "& 'C:\\Program Files\\Wireshark\\tshark.exe' -r 'C:\\Users\\YourName\\Documents\\Claude\\capture.pcapng' -Y 'tls.handshake.extensions_server_name' -T fields -e 'tls.handshake.extensions_server_name' 2>&1 | Sort-Object -Unique | Out-String" }
```

---

## Display & System Settings

### Get current screen resolution
```json
{ "type": "shell", "command": "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::PrimaryScreen | Select-Object Bounds,WorkingArea | Out-String" }
```

### Change display scaling (DPI)
Open the Settings UI and let Claude read the screenshot:
```json
{ "type": "shell", "command": "Start-Process ms-settings:display", "screenshot": true, "restore_focus": true, "close_after": "SystemSettings" }
```

### Get system specs
```json
{ "type": "shell", "command": "Get-ComputerInfo | Select-Object OsName,OsVersion,TotalPhysicalMemory,CsProcessors | Out-String" }
```

### Set power plan to High Performance
```json
{ "type": "shell", "command": "powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c; 'Power plan set to High Performance'" }
```

### List all power plans
```json
{ "type": "shell", "command": "powercfg /list" }
```

---

## Performance Monitoring

The repo includes scripts to measure bridge performance impact:

- `perf-monitor.ps1` — logs system CPU and bridge process memory every 500ms
- `launch-monitor.ps1` — starts the monitor as an independent background process
- `perf-report.ps1` — reads the CSV and generates an idle vs. active comparison report

### Running a performance test

1. Start the monitor: ask Claude to run `launch-monitor.ps1`
2. Let it idle for 15 seconds
3. Ask Claude to run several commands (the active phase)
4. Wait for the 50-second monitor window to finish
5. Ask Claude to run `perf-report.ps1` — it writes `perf-report.txt` with the results

---

## Auto-start the bridge on login

1. Press `Win + R`, type `shell:startup`, press Enter
2. Right-click in the folder → New → Shortcut
3. Point it to `Start-Bridge.bat`
4. The bridge launches silently every time you log in

To run the bridge completely hidden (no terminal window), create a `.vbs` launcher:

```vbscript
' start-bridge-hidden.vbs
Dim WShell
Set WShell = CreateObject("WScript.Shell")
WShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Users\YourName\Documents\Claude\claude-bridge.ps1""", 0, False
```

Put this `.vbs` file in your startup folder instead of the `.bat` file.
