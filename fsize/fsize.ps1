Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- フォーム ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Folder Size Viewer"
$form.Size = New-Object System.Drawing.Size(900, 650)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(700, 500)

# --- 上部パネル（2行） ---
$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = "Top"
$topPanel.Height = 80

# 1行目: ドライブ選択 + スキャン
$lblDrive = New-Object System.Windows.Forms.Label
$lblDrive.Text = "ドライブ:"
$lblDrive.Location = New-Object System.Drawing.Point(10, 13)
$lblDrive.AutoSize = $true

$cboDrive = New-Object System.Windows.Forms.ComboBox
$cboDrive.Location = New-Object System.Drawing.Point(70, 10)
$cboDrive.Width = 110
$cboDrive.DropDownStyle = "DropDownList"
[System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | ForEach-Object {
    $cboDrive.Items.Add($_.Name) | Out-Null
}
if ($cboDrive.Items.Count -gt 0) { $cboDrive.SelectedIndex = 0 }

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "スキャン"
$btnScan.Location = New-Object System.Drawing.Point(195, 8)
$btnScan.Width = 80

$lblProgress = New-Object System.Windows.Forms.Label
$lblProgress.Location = New-Object System.Drawing.Point(290, 13)
$lblProgress.AutoSize = $true
$lblProgress.ForeColor = [System.Drawing.Color]::Gray

# 2行目: 上へ + パスバー
$btnUp = New-Object System.Windows.Forms.Button
$btnUp.Text = "↑ 上へ"
$btnUp.Location = New-Object System.Drawing.Point(10, 44)
$btnUp.Width = 75
$btnUp.Enabled = $false

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(93, 45)
$txtPath.Width = 790
$txtPath.ReadOnly = $true
$txtPath.BackColor = [System.Drawing.SystemColors]::Window
$txtPath.Anchor = [System.Windows.Forms.AnchorStyles]::Top `
    -bor [System.Windows.Forms.AnchorStyles]::Left `
    -bor [System.Windows.Forms.AnchorStyles]::Right

$topPanel.Controls.AddRange(@($lblDrive, $cboDrive, $btnScan, $lblProgress, $btnUp, $txtPath))

# パスバーをフォームリサイズに追従させる
$form.Add_Resize({
    $txtPath.Width = $form.ClientSize.Width - $txtPath.Left - 10
})

# --- ListView ---
$listView = New-Object System.Windows.Forms.ListView
$listView.Dock = "Fill"
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.Font = New-Object System.Drawing.Font("Consolas", 10)
$listView.Cursor = [System.Windows.Forms.Cursors]::Default

$listView.Columns.Add("フォルダ",   400) | Out-Null
$listView.Columns.Add("サイズ",     130) | Out-Null
$listView.Columns.Add("ファイル数", 100) | Out-Null
$listView.Columns.Add("割合",       100) | Out-Null

# --- ステータスバー ---
$statusBar   = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "ドライブを選択して「スキャン」をクリックしてください"
$statusBar.Items.Add($statusLabel) | Out-Null

$form.Controls.Add($listView)
$form.Controls.Add($topPanel)
$form.Controls.Add($statusBar)

# --- 状態変数 ---
$script:currentPath = ""
$script:rootPath    = ""
$script:sortCol     = 1
$script:sortAsc     = $false

# --- ヘルパー ---
function Format-Size([long]$bytes) {
    if ($bytes -ge 1TB) { return "{0:N2} TB" -f ($bytes / 1TB) }
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Get-FolderInfo([string]$path) {
    $size = [long]0; $count = 0
    try {
        Get-ChildItem -Path $path -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $size += $_.Length; $count++ }
    } catch {}
    [PSCustomObject]@{ Size = $size; Count = $count }
}

# --- ListView 再描画 ---
function Update-ListView([System.Collections.Generic.List[PSCustomObject]]$results, [long]$totalSize) {
    $listView.BeginUpdate()
    $listView.Items.Clear()
    $sorted = $results | Sort-Object Size -Descending
    foreach ($r in $sorted) {
        $pct  = if ($totalSize -gt 0) { [math]::Round($r.Size / $totalSize * 100, 1) } else { 0 }
        $item = New-Object System.Windows.Forms.ListViewItem($r.ShortName)
        $item.SubItems.Add((Format-Size $r.Size)) | Out-Null
        $item.SubItems.Add($r.Count.ToString())   | Out-Null
        $item.SubItems.Add("$pct %")              | Out-Null
        $item.Tag = $r
        if ($pct -ge 20) { $item.BackColor = [System.Drawing.Color]::FromArgb(255, 200, 200) }
        elseif ($pct -ge 10) { $item.BackColor = [System.Drawing.Color]::FromArgb(255, 230, 180) }
        $listView.Items.Add($item) | Out-Null
    }
    $listView.EndUpdate()
}

# --- スキャン本体 ---
function Invoke-Scan([string]$path) {
    $btnScan.Enabled = $false
    $btnUp.Enabled   = $false
    $listView.Items.Clear()
    $txtPath.Text    = $path
    $statusLabel.Text = "スキャン中..."
    $form.Refresh()

    $folders   = Get-ChildItem -Path $path -Directory -Force -ErrorAction SilentlyContinue
    $results   = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalSize = [long]0

    foreach ($folder in $folders) {
        $lblProgress.Text = "スキャン中: $($folder.Name)"
        [System.Windows.Forms.Application]::DoEvents()
        $info = Get-FolderInfo $folder.FullName
        $results.Add([PSCustomObject]@{
            FullName  = $folder.FullName
            ShortName = $folder.Name
            Size      = $info.Size
            Count     = $info.Count
        })
        $totalSize += $info.Size
    }

    Update-ListView $results $totalSize

    $script:currentPath = $path
    $btnUp.Enabled      = ($path -ne $script:rootPath)
    $lblProgress.Text   = ""
    $btnScan.Enabled    = $true
    $statusLabel.Text   = "完了  合計: $(Format-Size $totalSize)  フォルダ数: $($results.Count)   ダブルクリックで下位フォルダへ"
}

# --- ソート（列ヘッダークリック） ---
$listView.Add_ColumnClick({
    param($s, $e)
    if ($script:sortCol -eq $e.Column) { $script:sortAsc = -not $script:sortAsc }
    else { $script:sortCol = $e.Column; $script:sortAsc = $false }

    $items  = @($listView.Items | ForEach-Object { $_ })
    $sorted = switch ($script:sortCol) {
        0 { $items | Sort-Object { $_.Text }                                         -Descending:(-not $script:sortAsc) }
        1 { $items | Sort-Object { [long]($_.Tag.Size) }                             -Descending:(-not $script:sortAsc) }
        2 { $items | Sort-Object { [int]$_.SubItems[2].Text }                        -Descending:(-not $script:sortAsc) }
        3 { $items | Sort-Object { [double]($_.SubItems[3].Text -replace ' %', '') } -Descending:(-not $script:sortAsc) }
    }
    $listView.BeginUpdate()
    $listView.Items.Clear()
    $sorted | ForEach-Object { $listView.Items.Add($_) | Out-Null }
    $listView.EndUpdate()
})

# --- ダブルクリックで下位フォルダへ ---
$listView.Add_DoubleClick({
    if ($listView.SelectedItems.Count -eq 0) { return }
    $folderPath = $listView.SelectedItems[0].Tag.FullName
    if (Test-Path $folderPath -PathType Container) {
        Invoke-Scan $folderPath
    }
})

# --- ↑ 上へ ---
$btnUp.Add_Click({
    $parent = Split-Path $script:currentPath -Parent
    if ($parent -and (Test-Path $parent)) {
        Invoke-Scan $parent
    }
})

# --- スキャンボタン（ルートから再スキャン） ---
$btnScan.Add_Click({
    $drive = $cboDrive.SelectedItem
    if (-not $drive) { return }
    $script:rootPath = $drive
    Invoke-Scan $drive
})

[void]$form.ShowDialog()
