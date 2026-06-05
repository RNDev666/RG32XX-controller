# latency_clock.ps1 - big millisecond counter for glass-to-glass latency tests.
#
# Usage:
#   1. .\latency_clock.ps1            # opens a window titled "MSCLOCK"
#   2. .\stream.ps1 -WindowTitle MSCLOCK
#   3. Photograph the PC monitor and the RG35XX together; the difference
#      between the two readouts is the end-to-end video latency.
#
# Close the window or Ctrl+C to stop.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form              = New-Object System.Windows.Forms.Form
$form.Text         = 'MSCLOCK'                       # exact title for gdigrab
$form.Width        = 640
$form.Height       = 480
$form.BackColor    = [System.Drawing.Color]::Black
$form.TopMost      = $true
$form.StartPosition = 'CenterScreen'

$label           = New-Object System.Windows.Forms.Label
$label.Dock      = 'Fill'
$label.TextAlign = 'MiddleCenter'
$label.ForeColor = [System.Drawing.Color]::Lime
$label.Font      = New-Object System.Drawing.Font('Consolas', 72, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($label)

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Forms timers clamp to ~15ms, but a camera captures both screens at one
# instant, so 15ms granularity is fine for reading a 100ms+ delta.
$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = 1
$timer.Add_Tick({ $label.Text = '{0:00000}' -f [int]$sw.Elapsed.TotalMilliseconds })
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
