# 管理者権限で再起動
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process pwsh -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text          = "プロセス & サービス モニター"
$form.ClientSize    = New-Object System.Drawing.Size(880, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize   = New-Object System.Drawing.Size(700, 460)

# ================================================================
# 状態変数
# ================================================================
$script:prevSnapshot = @{}   # key:PID, value:@{CPU=double;Time=DateTime}
$script:logicalCores = [int](Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).NumberOfLogicalProcessors
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
        $result.Add([PSCustomObject]@{
            Name  = $p.ProcessName
            PID   = $p.Id
            CPU   = $cpuPct
            MemMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
            User  = try { $p.UserName } catch { "" }
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

[void]$form.ShowDialog()
