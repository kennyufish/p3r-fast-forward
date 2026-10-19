# P3R_FastForward settings window. Writes settings.txt; Scripts/main.lua polls it every 500 ms.
# Saved as UTF-8 with BOM so Windows PowerShell 5.1 reads the Chinese labels correctly.
Add-Type -AssemblyName System.Windows.Forms
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'P3R_FastForward_GUI', [ref]$created)
if (-not $created) { exit } # one window only; F8 pressed again while open does nothing

$file = Join-Path $PSScriptRoot 'settings.txt'
$rates = '1.0', '1.5', '2.0', '5.0' # must match RATES in Scripts/main.lua
$script:last = $null

$form = New-Object Windows.Forms.Form -Property @{
    Text = 'P3R 加速'; FormBorderStyle = 'FixedToolWindow'; TopMost = $true
    StartPosition = 'Manual'; Location = '40,40'; ClientSize = '220,150'
}
$radios = @{}
$x = 10
foreach ($rate in $rates) {
    $radio = New-Object Windows.Forms.RadioButton -Property @{ Text = "${rate}x"; Location = "$x,10"; Width = 50 }
    $form.Controls.Add($radio)
    $radios[$rate] = $radio
    $x += 52
}
function New-Check($text, $y) {
    $check = New-Object Windows.Forms.CheckBox -Property @{ Text = $text; Location = "10,$y"; Width = 200 }
    $form.Controls.Add($check)
    $check
}
$chkGame = New-Check '加速游戏' 40
$chkSfx = New-Check '加速声音（语音/音效）' 65
$chkPitch = New-Check '修正声调（1.5x / 2x）' 90
$status = New-Object Windows.Forms.Label -Property @{ Location = '10,120'; Width = 200; Text = 'F6 切倍速 / F8 重开本窗口' }
$form.Controls.Add($status)

function Save-Settings {
    $rate = $rates | Where-Object { $radios[$_].Checked }
    $text = "rate=$rate`ngame=$([int]$chkGame.Checked)`nsfx=$([int]$chkSfx.Checked)`npitch=$([int]$chkPitch.Checked)`n"
    try { [IO.File]::WriteAllText($file, $text); $script:last = $text }
    catch { $status.Text = '写入失败: ' + $_.Exception.Message }
}
function Read-Settings {
    try { $text = [IO.File]::ReadAllText($file) } catch { return }
    if ($text -eq $script:last) { return }
    $map = @{}
    foreach ($m in [regex]::Matches($text, '(\w+)=([\d.]+)')) { $map[$m.Groups[1].Value] = $m.Groups[2].Value }
    if ($rates -notcontains $map['rate']) { return } # partial write; retry next tick
    $script:last = $text
    # Setting Checked in code does not raise Click, so this does not loop back into Save-Settings.
    $radios[$map['rate']].Checked = $true
    $chkGame.Checked = $map['game'] -eq '1'
    $chkSfx.Checked = $map['sfx'] -eq '1'
    $chkPitch.Checked = $map['pitch'] -ne '0' # absent in v0.5.0 files; main.lua defaults it on too
}
foreach ($control in @($radios.Values) + $chkGame, $chkSfx, $chkPitch) { $control.Add_Click({ Save-Settings }) }

$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 500 }
$timer.Add_Tick({
    Read-Settings # picks up F6 presses, which main.lua writes to the same file
    if (-not (Get-Process P3R -ErrorAction SilentlyContinue)) { $form.Close() }
})
Read-Settings
$timer.Start()
[void]$form.ShowDialog()
$mutex.ReleaseMutex()
