# 管理者権限チェック（非管理者でも起動可能、一部機能が制限される）
$script:isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$form = New-Object System.Windows.Forms.Form
$form.Text          = if ($script:isAdmin) { "プロセス & サービス モニター [管理者]" } else { "プロセス & サービス モニター [非管理者 — 一部機能制限]" }
$form.ClientSize    = New-Object System.Drawing.Size(880, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize   = New-Object System.Drawing.Size(700, 460)

# ================================================================
# 状態変数
# ================================================================
$script:prevSnapshot = @{}
$script:logicalCores = [System.Environment]::ProcessorCount
if ($script:logicalCores -lt 1) { $script:logicalCores = 1 }
$script:procSortCol  = 2;  $script:procSortAsc = $false
$script:svcSortCol   = 0;  $script:svcSortAsc  = $true

# ================================================================
# プロセスデータ取得（CPU% = 2サンプル差分 / 経過秒 / コア数）
# ================================================================
function Get-ProcessData {
    $now        = [DateTime]::Now
    $procs      = Get-Process -ErrorAction SilentlyContinue
    $result     = [System.Collections.Generic.List[PSCustomObject]]::new()
    $newSnapshot = @{}

    foreach ($p in $procs) {
        $cpuPct = 0.0
        $cpuNow = $p.CPU
        $prev   = $script:prevSnapshot[$p.Id]
        if ($prev -and $null -ne $cpuNow) {
            $elapsed = ($now - $prev.Time).TotalSeconds
            if ($elapsed -gt 0) {
                $cpuPct = [math]::Max(0, [math]::Round(
                    ($cpuNow - $prev.CPU) / $elapsed / $script:logicalCores * 100, 1))
            }
        }
        $user = try { $p.UserName ?? "" } catch { "" }
        $result.Add([PSCustomObject]@{
            Name  = $p.ProcessName
            PID   = $p.Id
            CPU   = $cpuPct
            MemMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
            User  = $user
            Proc  = $p
        })
        if ($null -ne $cpuNow) {
            $newSnapshot[$p.Id] = @{ CPU = $cpuNow; Time = $now }
        }
    }

    $script:prevSnapshot = $newSnapshot
    $result | Sort-Object CPU -Descending | Select-Object -First 100
}

# ================================================================
# サービスデータ取得
# ================================================================
function Get-ServiceData([bool]$runningOnly) {
    $svcs = Get-Service -ErrorAction SilentlyContinue
    if ($runningOnly) { $svcs = $svcs | Where-Object { $_.Status -eq 'Running' } }
    $svcs | Sort-Object Name
}

# ================================================================
# TabControl
# ================================================================
$tabCtrl = New-Object System.Windows.Forms.TabControl
$tabCtrl.Dock = "Fill"
$form.Controls.Add($tabCtrl)

$tabProc = New-Object System.Windows.Forms.TabPage; $tabProc.Text = "プロセス"
$tabSvc  = New-Object System.Windows.Forms.TabPage; $tabSvc.Text  = "サービス"
$tabCtrl.TabPages.AddRange(@($tabProc, $tabSvc))

# ================================================================
# プロセスタブ — ツールバー
# ================================================================
$pnlProcBar = New-Object System.Windows.Forms.Panel
$pnlProcBar.Dock = "Top"; $pnlProcBar.Height = 36

$lblInterval = New-Object System.Windows.Forms.Label
$lblInterval.Text = "更新間隔:"
$lblInterval.Location = New-Object System.Drawing.Point(8, 10); $lblInterval.AutoSize = $true

$cboInterval = New-Object System.Windows.Forms.ComboBox
$cboInterval.DropDownStyle = "DropDownList"; $cboInterval.Width = 72
$cboInterval.Location = New-Object System.Drawing.Point(74, 7)
@("1秒","3秒","5秒","10秒") | ForEach-Object { $cboInterval.Items.Add($_) | Out-Null }
$cboInterval.SelectedIndex = 1

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "更新"; $btnRefresh.Width = 60
$btnRefresh.Location = New-Object System.Drawing.Point(156, 6)

$btnKill = New-Object System.Windows.Forms.Button
$btnKill.Text = "強制終了"; $btnKill.Width = 80
$btnKill.Location = New-Object System.Drawing.Point(226, 6)

$pnlProcBar.Controls.AddRange(@($lblInterval, $cboInterval, $btnRefresh, $btnKill))

# ================================================================
# プロセスタブ — ListView
# ================================================================
$lvProc = New-Object System.Windows.Forms.ListView
$lvProc.Dock = "Fill"; $lvProc.View = "Details"
$lvProc.FullRowSelect = $true; $lvProc.GridLines = $true
$lvProc.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Clickable
$lvProc.Font = New-Object System.Drawing.Font("Meiryo UI", 9)
$lvProc.Columns.Add("プロセス名",        170) | Out-Null
$lvProc.Columns.Add("プロセスID",         90) | Out-Null
$lvProc.Columns.Add("CPU使用率(%)",      100) | Out-Null
$lvProc.Columns.Add("メモリ使用量(MB)",  130) | Out-Null
$lvProc.Columns.Add("実行ユーザー",      180) | Out-Null

$tlpProc = New-Object System.Windows.Forms.TableLayoutPanel
$tlpProc.Dock = "Fill"; $tlpProc.RowCount = 2; $tlpProc.ColumnCount = 1
$tlpProc.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36))) | Out-Null
$tlpProc.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$tlpProc.Controls.Add($pnlProcBar, 0, 0)
$tlpProc.Controls.Add($lvProc, 0, 1)
$tabProc.Controls.Add($tlpProc)

# ================================================================
# サービスタブ — ツールバー
# ================================================================
$pnlSvcBar = New-Object System.Windows.Forms.Panel
$pnlSvcBar.Dock = "Top"; $pnlSvcBar.Height = 36

$chkRunning = New-Object System.Windows.Forms.CheckBox
$chkRunning.Text = "実行中のみ"
$chkRunning.Location = New-Object System.Drawing.Point(8, 9); $chkRunning.AutoSize = $true

$btnSvcStart = New-Object System.Windows.Forms.Button
$btnSvcStart.Text = "開始"; $btnSvcStart.Width = 60
$btnSvcStart.Location = New-Object System.Drawing.Point(110, 6)

$btnSvcStop = New-Object System.Windows.Forms.Button
$btnSvcStop.Text = "停止"; $btnSvcStop.Width = 60
$btnSvcStop.Location = New-Object System.Drawing.Point(180, 6)

$pnlSvcBar.Controls.AddRange(@($chkRunning, $btnSvcStart, $btnSvcStop))

# ================================================================
# サービスタブ — ListView
# ================================================================
$lvSvc = New-Object System.Windows.Forms.ListView
$lvSvc.Dock = "Fill"; $lvSvc.View = "Details"
$lvSvc.FullRowSelect = $true; $lvSvc.GridLines = $true
$lvSvc.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Clickable
$lvSvc.Font = New-Object System.Drawing.Font("Meiryo UI", 9)
$lvSvc.Columns.Add("サービス名",    200) | Out-Null
$lvSvc.Columns.Add("表示名(説明)", 290) | Out-Null
$lvSvc.Columns.Add("稼働状態",      90) | Out-Null
$lvSvc.Columns.Add("起動タイプ",   120) | Out-Null

$tlpSvc = New-Object System.Windows.Forms.TableLayoutPanel
$tlpSvc.Dock = "Fill"; $tlpSvc.RowCount = 2; $tlpSvc.ColumnCount = 1
$tlpSvc.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36))) | Out-Null
$tlpSvc.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$tlpSvc.Controls.Add($pnlSvcBar, 0, 0)
$tlpSvc.Controls.Add($lvSvc, 0, 1)
$tabSvc.Controls.Add($tlpSvc)

# ================================================================
# ステータスバー
# ================================================================
$statusBar   = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "起動中..."
$statusBar.Items.Add($statusLabel) | Out-Null
$form.Controls.Add($statusBar)

# ================================================================
# プロセス ListView 更新
# ================================================================
function Update-ProcListView {
    $data = Get-ProcessData
    $lvProc.BeginUpdate(); $lvProc.Items.Clear()
    foreach ($d in $data) {
        $item = New-Object System.Windows.Forms.ListViewItem($d.Name)
        $item.SubItems.Add($d.PID.ToString())       | Out-Null
        $item.SubItems.Add("$($d.CPU) %")           | Out-Null
        $item.SubItems.Add($d.MemMB.ToString("N1")) | Out-Null
        $item.SubItems.Add($d.User ?? "")           | Out-Null
        $item.Tag = $d
        if ($d.CPU -ge 20) {
            $item.BackColor = [System.Drawing.Color]::FromArgb(255, 200, 200)
        } elseif ($d.CPU -ge 5) {
            $item.BackColor = [System.Drawing.Color]::FromArgb(255, 230, 180)
        }
        $lvProc.Items.Add($item) | Out-Null
    }
    $lvProc.EndUpdate()
}

# プロセス列ソート
$lvProc.Add_ColumnClick({
    param($s, $e)
    if ($script:procSortCol -eq $e.Column) { $script:procSortAsc = -not $script:procSortAsc }
    else { $script:procSortCol = $e.Column; $script:procSortAsc = $false }
    $items  = @($lvProc.Items | ForEach-Object { $_ })
    $sorted = switch ($script:procSortCol) {
        0 { $items | Sort-Object { $_.Text }                                           -Descending:(-not $script:procSortAsc) }
        1 { $items | Sort-Object { [int]$_.SubItems[1].Text }                          -Descending:(-not $script:procSortAsc) }
        2 { $items | Sort-Object { [double]($_.SubItems[2].Text -replace ' %', '') }   -Descending:(-not $script:procSortAsc) }
        3 { $items | Sort-Object { [double]$_.SubItems[3].Text }                       -Descending:(-not $script:procSortAsc) }
        4 { $items | Sort-Object { $_.SubItems[4].Text }                               -Descending:(-not $script:procSortAsc) }
    }
    $lvProc.BeginUpdate(); $lvProc.Items.Clear()
    $sorted | ForEach-Object { $lvProc.Items.Add($_) | Out-Null }
    $lvProc.EndUpdate()
})

# 強制終了
$btnKill.Add_Click({
    if ($lvProc.SelectedItems.Count -eq 0) { return }
    $d   = $lvProc.SelectedItems[0].Tag
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "$($d.Name) (PID: $($d.PID)) を強制終了しますか？",
        "確認", "YesNo", "Warning")
    if ($ans -eq "Yes") {
        if (-not $script:isAdmin) {
            [System.Windows.Forms.MessageBox]::Show("管理者権限が必要です。管理者として実行してください。", "権限不足", "OK", "Warning")
            return
        }
        try   { Stop-Process -Id $d.PID -Force -ErrorAction Stop }
        catch { [System.Windows.Forms.MessageBox]::Show("終了できません:`n$_", "エラー", "OK", "Error") }
        Update-ProcListView
    }
})

# ================================================================
# サービス ListView 更新
# ================================================================
function Update-SvcListView {
    $svcs = Get-ServiceData $chkRunning.Checked
    $lvSvc.BeginUpdate(); $lvSvc.Items.Clear()
    foreach ($s in $svcs) {
        $item = New-Object System.Windows.Forms.ListViewItem($s.Name)
        $item.SubItems.Add($s.DisplayName)          | Out-Null
        $item.SubItems.Add($s.Status.ToString())    | Out-Null
        $item.SubItems.Add($s.StartType.ToString()) | Out-Null
        $item.Tag = $s.Name
        if ($s.Status -eq 'Running') { $item.ForeColor = [System.Drawing.Color]::DarkGreen }
        $lvSvc.Items.Add($item) | Out-Null
    }
    $lvSvc.EndUpdate()
}

# 実行中のみフィルタ
$chkRunning.Add_CheckedChanged({ Update-SvcListView })

# サービス列ソート
$lvSvc.Add_ColumnClick({
    param($s, $e)
    if ($script:svcSortCol -eq $e.Column) { $script:svcSortAsc = -not $script:svcSortAsc }
    else { $script:svcSortCol = $e.Column; $script:svcSortAsc = $true }
    $items  = @($lvSvc.Items | ForEach-Object { $_ })
    $sorted = $items | Sort-Object { $_.SubItems[$e.Column].Text } -Descending:(-not $script:svcSortAsc)
    $lvSvc.BeginUpdate(); $lvSvc.Items.Clear()
    $sorted | ForEach-Object { $lvSvc.Items.Add($_) | Out-Null }
    $lvSvc.EndUpdate()
})

# サービス開始
$btnSvcStart.Add_Click({
    if ($lvSvc.SelectedItems.Count -eq 0) { return }
    if (-not $script:isAdmin) { [System.Windows.Forms.MessageBox]::Show("管理者権限が必要です。", "権限不足", "OK", "Warning"); return }
    $name = $lvSvc.SelectedItems[0].Tag
    try   { Start-Service -Name $name -ErrorAction Stop; Update-SvcListView }
    catch { [System.Windows.Forms.MessageBox]::Show("開始できません:`n$_", "エラー", "OK", "Error") }
})

# サービス停止
$btnSvcStop.Add_Click({
    if ($lvSvc.SelectedItems.Count -eq 0) { return }
    $name = $lvSvc.SelectedItems[0].Tag
    $ans  = [System.Windows.Forms.MessageBox]::Show(
        "$name を停止しますか？", "確認", "YesNo", "Warning")
    if ($ans -eq "Yes") {
        if (-not $script:isAdmin) { [System.Windows.Forms.MessageBox]::Show("管理者権限が必要です。", "権限不足", "OK", "Warning"); return }
        try   { Stop-Service -Name $name -Force -ErrorAction Stop; Update-SvcListView }
        catch { [System.Windows.Forms.MessageBox]::Show("停止できません:`n$_", "エラー", "OK", "Error") }
    }
})

# ================================================================
# タイマー
# ================================================================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000

$intervalMap = @{ "1秒" = 1000; "3秒" = 3000; "5秒" = 5000; "10秒" = 10000 }

$cboInterval.Add_SelectedIndexChanged({
    $timer.Interval = $intervalMap[$cboInterval.SelectedItem]
})

$timer.Add_Tick({
    if ($tabCtrl.SelectedTab -eq $tabProc) { Update-ProcListView } else { Update-SvcListView }
    $statusLabel.Text = "最終更新: $([DateTime]::Now.ToString('HH:mm:ss'))  プロセス数: $($lvProc.Items.Count)"
})

$btnRefresh.Add_Click({
    if ($tabCtrl.SelectedTab -eq $tabProc) { Update-ProcListView } else { Update-SvcListView }
    $statusLabel.Text = "最終更新: $([DateTime]::Now.ToString('HH:mm:ss'))  プロセス数: $($lvProc.Items.Count)"
})

$form.Add_FormClosing({ $timer.Stop(); $timer.Dispose() })

# ================================================================
# 初回データ取得 & タイマー開始
# ================================================================
try {
    Update-ProcListView
    Update-SvcListView
    $statusLabel.Text = "最終更新: $([DateTime]::Now.ToString('HH:mm:ss'))  プロセス数: $($lvProc.Items.Count)"
    $timer.Start()
    [void]$form.ShowDialog()
} catch {
    [System.Windows.Forms.MessageBox]::Show("エラー:`n$_`n`n$($_.ScriptStackTrace)", "procmon", "OK", "Error")
}
