# vmcreate リファクタリング実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `vmcreate-gui.ps1` の355行超のクリックハンドラを5つの関数に分解し、可読性・保守性を向上させる。機能・動作は変更しない。

**Architecture:** 単一ファイル構成を維持しつつ、`Add-Row` 直後に「ヘルパー関数」セクションを新設し、そこに全ての新規関数と移動した `Write-Log` を集約する。クリックハンドラは各関数を順番に呼ぶだけの薄い存在になる。

**Tech Stack:** PowerShell 7+, System.Windows.Forms, System.Drawing

---

## ファイル構成

- Modify: `vmcreate\vmcreate-gui.ps1`
- Delete: `vmcreate\1vmcreate-gui.ps1`

---

### Task 1: 旧バージョンファイルを削除する

**Files:**
- Delete: `vmcreate\1vmcreate-gui.ps1`

- [ ] **Step 1: ファイルを削除する**

```powershell
Remove-Item -Path 'D:\prj\vmcreate\1vmcreate-gui.ps1' -Force
```

- [ ] **Step 2: コミット**

```bash
git rm vmcreate/1vmcreate-gui.ps1
git commit -m "chore(vmcreate): remove old revision 1vmcreate-gui.ps1"
```

---

### Task 2: ヘルパー関数セクションを新設し `Write-Log` と `Get-NicParams` を追加する

**Files:**
- Modify: `vmcreate\vmcreate-gui.ps1`

`Add-Row` 関数 (line 28–39) の直後に新セクションを挿入し、`Write-Log` をそこへ移動、`Get-NicParams` を追加する。既存の `Write-Log` 定義 (line 366–373) は削除する。

- [ ] **Step 1: `Add-Row` 直後に新セクションを挿入する**

`vmcreate-gui.ps1` の `$y.Value += 32` の行 (Add-Row の末尾) の直後、`# ============================================================` (Tab1の見出し) の直前に以下を挿入する。

```powershell

# ============================================================
# ヘルパー関数
# ============================================================
function Write-Log($msg, [System.Drawing.Color]$color = [System.Drawing.Color]::White) {
    $rtbLog.SelectionStart  = $rtbLog.TextLength
    $rtbLog.SelectionLength = 0
    $rtbLog.SelectionColor  = $color
    $rtbLog.AppendText("$msg`n")
    $rtbLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-NicParams {
    param(
        [int]$NICCount,
        [bool]$UseStaticIP
    )
    $switches = @()
    $ipList   = @()
    for ($i = 0; $i -lt $NICCount; $i++) {
        $switches += "$($script:nicControls[$i].Switch.SelectedItem)"
        if ($UseStaticIP) {
            $ip  = $script:nicControls[$i].IP.Text.Trim()
            $pfx = [int]$script:nicControls[$i].Prefix.Value
            $dns = $script:nicControls[$i].DNS.Text.Trim()
            $gw  = $script:nicControls[$i].GW.Text.Trim()
            if ($ip) { $ipList += @{ IP = $ip; Prefix = $pfx; DNS = $dns; GW = $gw; NICIndex = $i } }
        }
    }
    $macs = @()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    for ($i = 0; $i -lt $NICCount; $i++) {
        $b = New-Object byte[] 3
        $rng.GetBytes($b)
        $macs += "00155D" + (($b | ForEach-Object { '{0:X2}' -f $_ }) -join '')
    }
    $rng.Dispose()
    return @{ Switches = $switches; IPList = $ipList; Macs = $macs }
}

```

- [ ] **Step 2: 旧 `Write-Log` 定義を削除する**

`vmcreate-gui.ps1` から以下のブロックを削除する（元の line 366–373 付近、`# ログヘルパー` セクション全体）:

```powershell
# ============================================================
# ログヘルパー
# ============================================================
function Write-Log($msg, [System.Drawing.Color]$color = [System.Drawing.Color]::White) {
    $rtbLog.SelectionStart  = $rtbLog.TextLength
    $rtbLog.SelectionLength = 0
    $rtbLog.SelectionColor  = $color
    $rtbLog.AppendText("$msg`n")
    $rtbLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}
```

- [ ] **Step 3: 構文チェック**

```powershell
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'D:\prj\vmcreate\vmcreate-gui.ps1', [ref]$null, [ref]$errs)
if ($errs.Count -eq 0) { "OK" } else { $errs }
```

期待出力: `OK`

- [ ] **Step 4: コミット**

```bash
git add vmcreate/vmcreate-gui.ps1
git commit -m "refactor(vmcreate): add helper section, move Write-Log, add Get-NicParams"
```

---

### Task 3: `New-UnattendXml` を抽出してクリックハンドラのXML生成を置き換える

**Files:**
- Modify: `vmcreate\vmcreate-gui.ps1`

- [ ] **Step 1: `Get-NicParams` 関数の直後に `New-UnattendXml` を追加する**

ヘルパー関数セクション内（`Get-NicParams` の閉じ括弧 `}` の直後）に挿入:

```powershell

function New-UnattendXml {
    param(
        [string]$VMName,
        [string]$AdminPass,
        [bool]$UseAutoLogon
    )
    $autoLogonXml = ""
    if ($UseAutoLogon) {
        $autoLogonXml = @"
            <AutoLogon>
                <Password><Value>$AdminPass</Value></Password>
                <Enabled>true</Enabled>
                <Username>Administrator</Username>
                <LogonCount>99</LogonCount>
            </AutoLogon>
"@
    }
    return @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ComputerName>$VMName</ComputerName>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>0411:E0010411</InputLocale>
            <SystemLocale>ja-JP</SystemLocale>
            <UILanguage>ja-JP</UILanguage>
            <UserLocale>ja-JP</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE><HideEULAPage>true</HideEULAPage></OOBE>
            <UserAccounts>
                <AdministratorPassword><Value>$AdminPass</Value></AdministratorPassword>
            </UserAccounts>
            <TimeZone>Tokyo Standard Time</TimeZone>
            $autoLogonXml
        </component>
    </settings>
    <settings pass="generalize">
        <component name="Microsoft-Windows-PnpSysprep" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DoNotCleanUpNonPresentDevices>true</DoNotCleanUpNonPresentDevices>
            <PersistAllDeviceInstalls>true</PersistAllDeviceInstalls>
        </component>
    </settings>
</unattend>
"@
}
```

- [ ] **Step 2: クリックハンドラ内のXML生成ブロックを置き換える**

クリックハンドラ内の以下のブロック（`$autoLogonXml = ""` から `$xml | Out-File ...` まで）を:

```powershell
        Write-Log "応答ファイル作成..." ([System.Drawing.Color]::Cyan)
        $autoLogonXml = ""
        if ($UseAutoLogon) {
            $autoLogonXml = @"
            <AutoLogon>
                <Password><Value>$AdminPass</Value></Password>
                <Enabled>true</Enabled>
                <Username>Administrator</Username>
                <LogonCount>99</LogonCount>
            </AutoLogon>
"@
        }

        $xml = @"
<?xml version="1.0" encoding="utf-8"?>
...（長い here-string）...
"@
        $xml | Out-File -Encoding UTF8 -FilePath $answerFile
        Write-Log "   保存: $answerFile" ([System.Drawing.Color]::LightGreen)
```

以下に置き換える:

```powershell
        Write-Log "応答ファイル作成..." ([System.Drawing.Color]::Cyan)
        $xml = New-UnattendXml -VMName $VMName -AdminPass $AdminPass -UseAutoLogon $UseAutoLogon
        $xml | Out-File -Encoding UTF8 -FilePath $answerFile
        Write-Log "   保存: $answerFile" ([System.Drawing.Color]::LightGreen)
```

- [ ] **Step 3: 構文チェック**

```powershell
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'D:\prj\vmcreate\vmcreate-gui.ps1', [ref]$null, [ref]$errs)
if ($errs.Count -eq 0) { "OK" } else { $errs }
```

期待出力: `OK`

- [ ] **Step 4: コミット**

```bash
git add vmcreate/vmcreate-gui.ps1
git commit -m "refactor(vmcreate): extract New-UnattendXml"
```

---

### Task 4: `New-GuestSetupScript` を抽出してスクリプト組み立て処理を置き換える

**Files:**
- Modify: `vmcreate\vmcreate-gui.ps1`

この関数は `@{ Script = string; Phase2 = string }` を返す。`Script` が空文字なら配置不要。`Phase2` が空でなければ `setup2.ps1` として書き出す。

- [ ] **Step 1: `New-UnattendXml` の直後に `New-GuestSetupScript` を追加する**

```powershell

function New-GuestSetupScript {
    param([hashtable]$p)
    $parts = @()
    $phase2Script = ""

    $featureNames = @()
    if ($p.RoleHyperV)  { $featureNames += "Hyper-V" }
    if ($p.RoleCluster) { $featureNames += "Failover-Clustering" }

    # --- 静的 IP 設定 ---
    if ($p.UseStaticIP -and $p.NicIPList.Count -gt 0) {
        $ipCmds = "Start-Sleep -Seconds 5"
        foreach ($e in $p.NicIPList) {
            $macWin = ($p.NicMacs[$e.NICIndex] -replace '(..)(..)(..)(..)(..)(..)', '$1-$2-$3-$4-$5-$6').ToUpper()
            $ipCmds += "`n`$adapter = Get-NetAdapter | Where-Object { `$_.MacAddress -eq '$macWin' }"
            $ipCmds += "`nif (`$adapter) {"
            $gwParam = if ($e.GW) { " -DefaultGateway '$($e.GW)'" } else { "" }
            $ipCmds += "`n    New-NetIPAddress -InterfaceAlias `$adapter.Name -IPAddress '$($e.IP)' -PrefixLength $($e.Prefix)$gwParam -ErrorAction SilentlyContinue"
            if ($e.DNS) {
                $ipCmds += "`n    Set-DnsClientServerAddress -InterfaceAlias `$adapter.Name -ServerAddresses '$($e.DNS)' -ErrorAction SilentlyContinue"
            }
            $ipCmds += "`n}"
        }
        $parts += $ipCmds
    }

    # --- iSCSI ターゲット ---
    if ($p.RoleiSCSITarget) {
        $parts += @"
Install-WindowsFeature -Name FS-iSCSITarget-Server -IncludeManagementTools
`$diskDir = Split-Path '$($p.ISCSIDiskPath)' -Parent
if (-not (Test-Path `$diskDir)) { New-Item -ItemType Directory -Path `$diskDir -Force | Out-Null }
New-IscsiVirtualDisk -Path '$($p.ISCSIDiskPath)' -Size $($p.ISCSIDiskGB)GB
`$ids = '$($p.ISCSIInitIPs)'.Split(',') | ForEach-Object { "IPAddress:`$(`$_.Trim())" }
New-IscsiServerTarget -TargetName '$($p.ISCSITargetName)' -InitiatorIds `$ids
Add-IscsiVirtualDiskTargetMapping -TargetName '$($p.ISCSITargetName)' -Path '$($p.ISCSIDiskPath)'
"@
    }

    # --- iSCSI イニシエーター ---
    if ($p.RoleiSCSIInit) {
        $parts += @"
Start-Service -Name MSiSCSI
Set-Service -Name MSiSCSI -StartupType Automatic
`$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt `$deadline) {
    `$tentative = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { `$_.PrefixOrigin -eq 'Manual' -and `$_.AddressState -eq 'Tentative' }
    if (-not `$tentative) { break }
    Start-Sleep -Seconds 2
}
New-IscsiTargetPortal -TargetPortalAddress '$($p.ISCSIPortalIP)'
`$target = Get-IscsiTarget | Where-Object { `$_.IsConnected -eq `$false } | Select-Object -First 1
if (`$target) { Connect-IscsiTarget -NodeAddress `$target.NodeAddress -IsPersistent `$true }
"@
    }

    # --- IIS ---
    if ($p.RoleIIS) {
        $parts += "Install-WindowsFeature -Name Web-Server -IncludeManagementTools"
    }

    # --- Windows Server バックアップ ---
    if ($p.RoleBackup) {
        $parts += "Install-WindowsFeature -Name Windows-Server-Backup"
    }

    # --- ドメイン参加あり + Hyper-V/Cluster: Phase2 で features をインストール ---
    if ($featureNames.Count -gt 0 -and $p.ADRole -ne 0) {
        $featStr = $featureNames -join ','
        $parts += 'schtasks /Create /TN "VMSetupPhase2" /TR "powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\setup2.ps1 >> C:\Windows\Setup\Scripts\setup2.log 2>&1" /SC ONSTART /RU SYSTEM /RL HIGHEST /F'
        $phase2Script = @"
schtasks /Delete /TN "VMSetupPhase2" /F 2>`$null
Start-Transcript -Path 'C:\Windows\Setup\Scripts\setup2.log' -Append -ErrorAction SilentlyContinue
Install-WindowsFeature -Name $featStr -IncludeManagementTools -Restart:`$false
shutdown /r /f /t 5
"@
    }

    # --- AD ロール ---
    switch ($p.ADRole) {
        1 {
            $parts += @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Restart:`$false
Import-Module ADDSDeployment
`$safePwd = ConvertTo-SecureString '$($p.DSRMPass)' -AsPlainText -Force
Install-ADDSForest ``
    -DomainName '$($p.Domain)' ``
    -SafeModeAdministratorPassword `$safePwd ``
    -InstallDNS ``
    -Force
"@
        }
        2 {
            $parts += @"
Start-Sleep -Seconds 60
`$password   = ConvertTo-SecureString '$($p.DomainAdminPass)' -AsPlainText -Force
`$credential = New-Object PSCredential('$($p.DomainAdmin)', `$password)
Add-Computer -DomainName '$($p.Domain)' -Credential `$credential -Restart -Force
"@
        }
        3 {
            $parts += @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Restart:`$false
Import-Module ADDSDeployment
`$domCred = New-Object PSCredential('$($p.DomainAdmin)', (ConvertTo-SecureString '$($p.DomainAdminPass)' -AsPlainText -Force))
`$dsrmPwd = ConvertTo-SecureString '$($p.DSRMPass)' -AsPlainText -Force
Install-ADDSDomainController ``
    -DomainName '$($p.Domain)' ``
    -Credential `$domCred ``
    -SafeModeAdministratorPassword `$dsrmPwd ``
    -InstallDns:`$true ``
    -NoGlobalCatalog:`$false ``
    -NoRebootOnCompletion:`$false ``
    -Force
"@
        }
    }

    # --- ドメイン参加なし + Hyper-V/Cluster: Phase1 で直接インストール ---
    if ($featureNames.Count -gt 0 -and $p.ADRole -eq 0) {
        $parts += "Install-WindowsFeature -Name $($featureNames -join ',') -IncludeManagementTools -Restart:`$false"
        $parts += "shutdown /r /f /t 5"
    }

    return @{ Script = ($parts -join "`n`n"); Phase2 = $phase2Script }
}
```

- [ ] **Step 2: クリックハンドラ内のスクリプト配置ブロックを置き換える**

クリックハンドラ内の以下のブロック全体（`if ($UseStaticIP -or $ADRole -ne 0 -or ...)` から `Write-Log "   スクリプト配置完了"` まで）を削除し、`$scriptParams` ハッシュテーブルと新しい呼び出しコードに置き換える。

削除するブロック（line 524–658 付近）:
```powershell
        if ($UseStaticIP -or $ADRole -ne 0 -or $RoleHyperV -or $RoleCluster -or $RoleiSCSITarget -or $RoleiSCSIInit -or $RoleIIS -or $RoleBackup) {
            Write-Log "セットアップスクリプト配置中..." ([System.Drawing.Color]::Cyan)
            $scriptsDir = "${vhdDrive}:\Windows\Setup\Scripts"
            New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
            "@echo off`r`npowershell.exe -ExecutionPolicy Bypass -File ""C:\Windows\Setup\Scripts\setup.ps1"" >> ""C:\Windows\Setup\Scripts\setup.log"" 2>&1" |
                Out-File -Encoding ASCII -FilePath "$scriptsDir\SetupComplete.cmd"

            $scriptParts = @()

            $featureNames = @()
            if ($RoleHyperV)  { $featureNames += "Hyper-V" }
            if ($RoleCluster) { $featureNames += "Failover-Clustering" }
            $hasFeatures = $featureNames.Count -gt 0

            # --- IP 設定 (MAC ベース) ---
            if ($UseStaticIP -and $nicIPList.Count -gt 0) {
                $ipCmds = "Start-Sleep -Seconds 5"
                foreach ($e in $nicIPList) {
                    $macWin = ($nicMacs[$e.NICIndex] -replace '(..)(..)(..)(..)(..)(..)', '$1-$2-$3-$4-$5-$6').ToUpper()
                    $ipCmds += "`n`$adapter = Get-NetAdapter | Where-Object { `$_.MacAddress -eq '$macWin' }"
                    $ipCmds += "`nif (`$adapter) {"
                    $gwParam = if ($e.GW) { " -DefaultGateway '$($e.GW)'" } else { "" }
                    $ipCmds += "`n    New-NetIPAddress -InterfaceAlias `$adapter.Name -IPAddress '$($e.IP)' -PrefixLength $($e.Prefix)$gwParam -ErrorAction SilentlyContinue"
                    if ($e.DNS) {
                        $ipCmds += "`n    Set-DnsClientServerAddress -InterfaceAlias `$adapter.Name -ServerAddresses '$($e.DNS)' -ErrorAction SilentlyContinue"
                    }
                    $ipCmds += "`n}"
                }
                $scriptParts += $ipCmds
            }

            # --- iSCSI ターゲット ---
            if ($RoleiSCSITarget) {
                $scriptParts += @"
Install-WindowsFeature -Name FS-iSCSITarget-Server -IncludeManagementTools
`$diskDir = Split-Path '$ISCSIDiskPath' -Parent
if (-not (Test-Path `$diskDir)) { New-Item -ItemType Directory -Path `$diskDir -Force | Out-Null }
New-IscsiVirtualDisk -Path '$ISCSIDiskPath' -Size ${ISCSIDiskGB}GB
`$ids = '$ISCSIInitIPs'.Split(',') | ForEach-Object { "IPAddress:`$(`$_.Trim())" }
New-IscsiServerTarget -TargetName '$ISCSITargetName' -InitiatorIds `$ids
Add-IscsiVirtualDiskTargetMapping -TargetName '$ISCSITargetName' -Path '$ISCSIDiskPath'
"@
            }

            # --- iSCSI イニシエーター ---
            if ($RoleiSCSIInit) {
                $scriptParts += @"
Start-Service -Name MSiSCSI
Set-Service -Name MSiSCSI -StartupType Automatic
`$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt `$deadline) {
    `$tentative = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { `$_.PrefixOrigin -eq 'Manual' -and `$_.AddressState -eq 'Tentative' }
    if (-not `$tentative) { break }
    Start-Sleep -Seconds 2
}
New-IscsiTargetPortal -TargetPortalAddress '$ISCSIPortalIP'
`$target = Get-IscsiTarget | Where-Object { `$_.IsConnected -eq `$false } | Select-Object -First 1
if (`$target) { Connect-IscsiTarget -NodeAddress `$target.NodeAddress -IsPersistent `$true }
"@
            }

            # --- IIS ---
            if ($RoleIIS) {
                $scriptParts += "Install-WindowsFeature -Name Web-Server -IncludeManagementTools"
            }

            # --- Windows Server バックアップ ---
            if ($RoleBackup) {
                $scriptParts += "Install-WindowsFeature -Name Windows-Server-Backup"
            }

            # --- ドメイン参加あり + Hyper-V/Cluster: Phase2 で features をインストール ---
            if ($hasFeatures -and $ADRole -ne 0) {
                $featStr = $featureNames -join ','
                # ドメイン参加の再起動後に setup2.ps1 を実行するタスクを登録
                $scriptParts += 'schtasks /Create /TN "VMSetupPhase2" /TR "powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\setup2.ps1 >> C:\Windows\Setup\Scripts\setup2.log 2>&1" /SC ONSTART /RU SYSTEM /RL HIGHEST /F'
                # setup2.ps1 生成
                @"
schtasks /Delete /TN "VMSetupPhase2" /F 2>`$null
Start-Transcript -Path 'C:\Windows\Setup\Scripts\setup2.log' -Append -ErrorAction SilentlyContinue
Install-WindowsFeature -Name $featStr -IncludeManagementTools -Restart:`$false
shutdown /r /f /t 5
"@ | Out-File -Encoding UTF8 -FilePath "$scriptsDir\setup2.ps1"
                Write-Log "   setup2.ps1 ($($featStr): ドメイン参加後) 配置完了" ([System.Drawing.Color]::LightGreen)
            }

            # --- AD ロール ---
            switch ($ADRole) {
                1 {
                    $scriptParts += @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Restart:`$false
Import-Module ADDSDeployment
`$safePwd = ConvertTo-SecureString '$DSRMPass' -AsPlainText -Force
Install-ADDSForest ``
    -DomainName '$Domain' ``
    -SafeModeAdministratorPassword `$safePwd ``
    -InstallDNS ``
    -Force
"@
                }
                2 {
                    $scriptParts += @"
Start-Sleep -Seconds 60
`$password   = ConvertTo-SecureString '$DomainAdminPass' -AsPlainText -Force
`$credential = New-Object PSCredential('$DomainAdmin', `$password)
Add-Computer -DomainName '$Domain' -Credential `$credential -Restart -Force
"@
                }
                3 {
                    $scriptParts += @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Restart:`$false
Import-Module ADDSDeployment
`$domCred = New-Object PSCredential('$DomainAdmin', (ConvertTo-SecureString '$DomainAdminPass' -AsPlainText -Force))
`$dsrmPwd = ConvertTo-SecureString '$DSRMPass' -AsPlainText -Force
Install-ADDSDomainController ``
    -DomainName '$Domain' ``
    -Credential `$domCred ``
    -SafeModeAdministratorPassword `$dsrmPwd ``
    -InstallDns:`$true ``
    -NoGlobalCatalog:`$false ``
    -NoRebootOnCompletion:`$false ``
    -Force
"@
                }
            }

            # --- ドメイン参加なし + Hyper-V/Cluster: Phase1 で直接インストール → 再起動 ---
            if ($hasFeatures -and $ADRole -eq 0) {
                $scriptParts += "Install-WindowsFeature -Name $($featureNames -join ',') -IncludeManagementTools -Restart:`$false"
                $scriptParts += "shutdown /r /f /t 5"
            }

            ($scriptParts -join "`n`n") | Out-File -Encoding UTF8 -FilePath "$scriptsDir\setup.ps1"
            Write-Log "   スクリプト配置完了" ([System.Drawing.Color]::LightGreen)
        }
```

置き換え後のコード:
```powershell
        $scriptParams = @{
            UseStaticIP     = $UseStaticIP
            NicIPList       = $nicParams.IPList
            NicMacs         = $nicParams.Macs
            RoleiSCSITarget = $chkRoleiSCSITarget.Checked
            ISCSITargetName = $txtISCSITargetName.Text.Trim()
            ISCSIDiskPath   = $txtISCSIDiskPath.Text.Trim()
            ISCSIDiskGB     = [int]$numISCSIDiskGB.Value
            ISCSIInitIPs    = $txtISCSIInitIPs.Text.Trim()
            RoleiSCSIInit   = $chkRoleiSCSIInit.Checked
            ISCSIPortalIP   = $txtISCSIPortal.Text.Trim()
            RoleIIS         = $chkRoleIIS.Checked
            RoleBackup      = $chkRoleBackup.Checked
            RoleHyperV      = $chkRoleHyperV.Checked
            RoleCluster     = $chkRoleCluster.Checked
            ADRole          = $ADRole
            Domain          = $Domain
            DomainAdmin     = $txtDomainAdmin.Text.Trim()
            DomainAdminPass = $txtDomainAdminPass.Text
            DSRMPass        = $txtDSRMPass.Text
        }
        $guestScript = New-GuestSetupScript $scriptParams
        if ($guestScript.Script) {
            Write-Log "セットアップスクリプト配置中..." ([System.Drawing.Color]::Cyan)
            $scriptsDir = "${vhdDrive}:\Windows\Setup\Scripts"
            New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
            "@echo off`r`npowershell.exe -ExecutionPolicy Bypass -File ""C:\Windows\Setup\Scripts\setup.ps1"" >> ""C:\Windows\Setup\Scripts\setup.log"" 2>&1" |
                Out-File -Encoding ASCII -FilePath "$scriptsDir\SetupComplete.cmd"
            $guestScript.Script | Out-File -Encoding UTF8 -FilePath "$scriptsDir\setup.ps1"
            if ($guestScript.Phase2) {
                $guestScript.Phase2 | Out-File -Encoding UTF8 -FilePath "$scriptsDir\setup2.ps1"
                Write-Log "   setup2.ps1 配置完了" ([System.Drawing.Color]::LightGreen)
            }
            Write-Log "   スクリプト配置完了" ([System.Drawing.Color]::LightGreen)
        }
```

- [ ] **Step 3: クリックハンドラ先頭の `$nicSwitches`/`$nicIPList`/`$nicMacs` 生成ブロックを `Get-NicParams` 呼び出しに置き換える**

クリックハンドラ冒頭の入力収集部分の末尾にある以下のブロック（`$nicSwitches` / `$nicIPList` / `$nicMacs` 生成、lines 407–429 付近）を削除し、置き換える。

削除するブロック:
```powershell
    # NIC ごとのスイッチ・IP 情報を収集
    $nicSwitches = @()
    $nicIPList   = @()
    for ($i = 0; $i -lt $NICCount; $i++) {
        $nicSwitches += "$($script:nicControls[$i].Switch.SelectedItem)"
        if ($UseStaticIP) {
            $ip  = $script:nicControls[$i].IP.Text.Trim()
            $pfx = [int]$script:nicControls[$i].Prefix.Value
            $dns = $script:nicControls[$i].DNS.Text.Trim()
            $gw  = $script:nicControls[$i].GW.Text.Trim()
            # NICIndex を保持してMAC対応に使用
            if ($ip) { $nicIPList += @{ IP = $ip; Prefix = $pfx; DNS = $dns; GW = $gw; NICIndex = $i } }
        }
    }

    # NIC ごとに静的 MAC を事前生成 (スイッチ単位での正確な IP 割り当てを保証)
    $nicMacs = @()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    for ($i = 0; $i -lt $NICCount; $i++) {
        $b = New-Object byte[] 3
        $rng.GetBytes($b)
        $nicMacs += "00155D" + (($b | ForEach-Object { '{0:X2}' -f $_ }) -join '')
    }
    $rng.Dispose()
```

置き換え後:
```powershell
    $nicParams = Get-NicParams -NICCount $NICCount -UseStaticIP $UseStaticIP
```

- [ ] **Step 4: バリデーション部分の変数名を更新する**

クリックハンドラ内のバリデーション（旧 `$nicSwitches[0]` / `$nicIPList` 参照）を以下に更新:

変更前:
```powershell
    if (-not $nicSwitches[0])        { [System.Windows.Forms.MessageBox]::Show("NIC1の仮想スイッチを選択してください。");     return }
    if ($UseStaticIP -and $nicIPList.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("静的IPを有効にする場合はNIC1のIPアドレスを入力してください。"); return
    }
```

変更後:
```powershell
    if (-not $nicParams.Switches[0]) { [System.Windows.Forms.MessageBox]::Show("NIC1の仮想スイッチを選択してください。");     return }
    if ($UseStaticIP -and $nicParams.IPList.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("静的IPを有効にする場合はNIC1のIPアドレスを入力してください。"); return
    }
```

- [ ] **Step 5: クリックハンドラ先頭の不要なローカル変数宣言を削除する**

Task 4 の変更により、以下の変数は `$scriptParams` 内で直接コントロール参照に置き換わったため不要になる。クリックハンドラ冒頭から以下のブロックを削除する:

```powershell
    $RoleHyperV      = $chkRoleHyperV.Checked
    $RoleCluster     = $chkRoleCluster.Checked
    $RoleiSCSITarget = $chkRoleiSCSITarget.Checked
    $RoleiSCSIInit   = $chkRoleiSCSIInit.Checked
    $RoleIIS         = $chkRoleIIS.Checked
    $RoleBackup      = $chkRoleBackup.Checked
    $ISCSITargetName = $txtISCSITargetName.Text.Trim()
    $ISCSIDiskPath   = $txtISCSIDiskPath.Text.Trim()
    $ISCSIDiskGB     = [int]$numISCSIDiskGB.Value
    $ISCSIInitIPs    = $txtISCSIInitIPs.Text.Trim()
    $ISCSIPortalIP   = $txtISCSIPortal.Text.Trim()
    $DSRMPass        = $txtDSRMPass.Text
    $DomainAdmin     = $txtDomainAdmin.Text.Trim()
    $DomainAdminPass = $txtDomainAdminPass.Text
```

- [ ] **Step 6: 構文チェック**

```powershell
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'D:\prj\vmcreate\vmcreate-gui.ps1', [ref]$null, [ref]$errs)
if ($errs.Count -eq 0) { "OK" } else { $errs }
```

期待出力: `OK`

- [ ] **Step 7: コミット**

```bash
git add vmcreate/vmcreate-gui.ps1
git commit -m "refactor(vmcreate): extract New-GuestSetupScript and Get-NicParams call"
```

---

### Task 5: `Set-GuestRegistry` を抽出してレジストリブロックを置き換える

**Files:**
- Modify: `vmcreate\vmcreate-gui.ps1`

- [ ] **Step 1: `New-GuestSetupScript` の直後に `Set-GuestRegistry` を追加する**

```powershell

function Set-GuestRegistry {
    param(
        [string]$VhdDrive,
        [string]$HiveKey,
        [string]$AdminPass,
        [string]$Domain,
        [bool]$UseAutoLogon,
        [bool]$UseDisableCAD
    )
    reg load "HKLM\$HiveKey" "${VhdDrive}:\Windows\System32\config\SYSTEM" | Out-Null
    $regSystem = "HKLM:\$HiveKey\Setup"
    if (-not (Test-Path $regSystem)) { New-Item -Path $regSystem -Force | Out-Null }
    Set-ItemProperty -Path $regSystem -Name "UnattendFile" -Value "C:\autounattend.xml" -Type String
    reg unload "HKLM\$HiveKey" | Out-Null

    if ($UseAutoLogon -or $UseDisableCAD) {
        reg load "HKLM\${HiveKey}SW" "${VhdDrive}:\Windows\System32\config\SOFTWARE" | Out-Null
        if ($UseAutoLogon) {
            $winlogonPath = "HKLM:\${HiveKey}SW\Microsoft\Windows NT\CurrentVersion\Winlogon"
            if (-not (Test-Path $winlogonPath)) { New-Item -Path $winlogonPath -Force | Out-Null }
            Set-ItemProperty -Path $winlogonPath -Name "AutoAdminLogon"    -Value "1"             -Type String
            Set-ItemProperty -Path $winlogonPath -Name "DefaultUserName"   -Value "administrator" -Type String
            Set-ItemProperty -Path $winlogonPath -Name "DefaultPassword"   -Value $AdminPass      -Type String
            Set-ItemProperty -Path $winlogonPath -Name "DefaultDomainName" -Value $(if ($Domain) { $Domain } else { "." }) -Type String
            Remove-ItemProperty -Path $winlogonPath -Name "AutoLogonCount" -ErrorAction SilentlyContinue
            Write-Log "   自動ログオン設定完了" ([System.Drawing.Color]::LightGreen)
        }
        if ($UseDisableCAD) {
            $cadPath = "HKLM:\${HiveKey}SW\Microsoft\Windows\CurrentVersion\Policies\System"
            if (-not (Test-Path $cadPath)) { New-Item -Path $cadPath -Force | Out-Null }
            Set-ItemProperty -Path $cadPath -Name "DisableCAD" -Value 1 -Type DWord
            Write-Log "   Ctrl+Alt+Del 無効化設定完了" ([System.Drawing.Color]::LightGreen)
        }
        reg unload "HKLM\${HiveKey}SW" | Out-Null
    }
    Write-Log "   レジストリ設定完了" ([System.Drawing.Color]::LightGreen)
}
```

- [ ] **Step 2: クリックハンドラ内のレジストリブロックを置き換える**

削除するブロック（`Write-Log "レジストリ設定中..."` から `Write-Log "   レジストリ設定完了"` まで）:

```powershell
        Write-Log "レジストリ設定中..." ([System.Drawing.Color]::Cyan)
        reg load "HKLM\$TempHiveKey" "${vhdDrive}:\Windows\System32\config\SYSTEM" | Out-Null
        $regSystem = "HKLM:\$TempHiveKey\Setup"
        if (-not (Test-Path $regSystem)) { New-Item -Path $regSystem -Force | Out-Null }
        Set-ItemProperty -Path $regSystem -Name "UnattendFile" -Value "C:\autounattend.xml" -Type String
        reg unload "HKLM\$TempHiveKey" | Out-Null

        if ($UseAutoLogon -or $UseDisableCAD) {
            reg load "HKLM\${TempHiveKey}SW" "${vhdDrive}:\Windows\System32\config\SOFTWARE" | Out-Null
            if ($UseAutoLogon) {
                $winlogonPath = "HKLM:\${TempHiveKey}SW\Microsoft\Windows NT\CurrentVersion\Winlogon"
                if (-not (Test-Path $winlogonPath)) { New-Item -Path $winlogonPath -Force | Out-Null }
                Set-ItemProperty -Path $winlogonPath -Name "AutoAdminLogon"    -Value "1"             -Type String
                Set-ItemProperty -Path $winlogonPath -Name "DefaultUserName"   -Value "administrator" -Type String
                Set-ItemProperty -Path $winlogonPath -Name "DefaultPassword"   -Value $AdminPass      -Type String
                Set-ItemProperty -Path $winlogonPath -Name "DefaultDomainName" -Value $(if ($Domain) { $Domain } else { "." }) -Type String
                Remove-ItemProperty -Path $winlogonPath -Name "AutoLogonCount" -ErrorAction SilentlyContinue
                Write-Log "   自動ログオン設定完了" ([System.Drawing.Color]::LightGreen)
            }
            if ($UseDisableCAD) {
                $cadPath = "HKLM:\${TempHiveKey}SW\Microsoft\Windows\CurrentVersion\Policies\System"
                if (-not (Test-Path $cadPath)) { New-Item -Path $cadPath -Force | Out-Null }
                Set-ItemProperty -Path $cadPath -Name "DisableCAD" -Value 1 -Type DWord
                Write-Log "   Ctrl+Alt+Del 無効化設定完了" ([System.Drawing.Color]::LightGreen)
            }
            reg unload "HKLM\${TempHiveKey}SW" | Out-Null
        }
        Write-Log "   レジストリ設定完了" ([System.Drawing.Color]::LightGreen)
```

置き換え後:
```powershell
        Write-Log "レジストリ設定中..." ([System.Drawing.Color]::Cyan)
        Set-GuestRegistry -VhdDrive $vhdDrive -HiveKey $hiveKey `
            -AdminPass $AdminPass -Domain $Domain `
            -UseAutoLogon $UseAutoLogon -UseDisableCAD $UseDisableCAD
```

- [ ] **Step 3: クリックハンドラの変数名を更新する**

クリックハンドラ冒頭の変数宣言 `$TempHiveKey = "TempSystemHive_$VMName"` を次に変更:

変更前:
```powershell
    $TempHiveKey = "TempSystemHive_$VMName"
```

変更後:
```powershell
    $hiveKey    = "TempSystemHive_$VMName"
```

catch ブロックにある `$TempHiveKey` 参照も更新する。

変更前:
```powershell
        try { reg unload "HKLM\${TempHiveKey}SW" 2>$null } catch {}
        try { reg unload "HKLM\$TempHiveKey"     2>$null } catch {}
```

変更後:
```powershell
        try { reg unload "HKLM\${hiveKey}SW" 2>$null } catch {}
        try { reg unload "HKLM\$hiveKey"     2>$null } catch {}
```

- [ ] **Step 4: 構文チェック**

```powershell
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'D:\prj\vmcreate\vmcreate-gui.ps1', [ref]$null, [ref]$errs)
if ($errs.Count -eq 0) { "OK" } else { $errs }
```

期待出力: `OK`

- [ ] **Step 5: コミット**

```bash
git add vmcreate/vmcreate-gui.ps1
git commit -m "refactor(vmcreate): extract Set-GuestRegistry"
```

---

### Task 6: `New-HyperVVM` を抽出してVM作成ブロックを置き換える

**Files:**
- Modify: `vmcreate\vmcreate-gui.ps1`

- [ ] **Step 1: `Set-GuestRegistry` の直後に `New-HyperVVM` を追加する**

```powershell

function New-HyperVVM {
    param(
        [string]$VMName,
        [string]$DiffVHD,
        [string]$VmBase,
        [long]$MemBytes,
        [int]$CPUCount,
        [string[]]$NicSwitches,
        [string[]]$NicMacs,
        [int]$NICCount,
        [bool]$UseNestedVM
    )
    New-VM -Name $VMName -MemoryStartupBytes $MemBytes -BootDevice VHD `
           -VHDPath $DiffVHD -Generation 2 -Path $VmBase -SwitchName $NicSwitches[0] | Out-Null
    Set-VMProcessor -VMName $VMName -Count $CPUCount

    Get-VMNetworkAdapter -VMName $VMName | Select-Object -First 1 |
        Set-VMNetworkAdapter -StaticMacAddress $NicMacs[0]
    $mac0 = ($NicMacs[0] -replace '(..)(..)(..)(..)(..)(..)', '$1-$2-$3-$4-$5-$6').ToUpper()
    Write-Log "   NIC1  SW: $($NicSwitches[0])  MAC: $mac0" ([System.Drawing.Color]::LightGreen)

    for ($i = 1; $i -lt $NICCount; $i++) {
        Add-VMNetworkAdapter -VMName $VMName -SwitchName $NicSwitches[$i]
        Get-VMNetworkAdapter -VMName $VMName | Select-Object -Last 1 |
            Set-VMNetworkAdapter -StaticMacAddress $NicMacs[$i]
        $macN = ($NicMacs[$i] -replace '(..)(..)(..)(..)(..)(..)', '$1-$2-$3-$4-$5-$6').ToUpper()
        Write-Log "   NIC$($i+1)  SW: $($NicSwitches[$i])  MAC: $macN" ([System.Drawing.Color]::LightGreen)
    }

    if ($UseNestedVM) {
        Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
        Write-Log "   仮想化拡張（ネスト Hyper-V）有効化完了" ([System.Drawing.Color]::LightGreen)
    }
    Write-Log "   VM 作成完了" ([System.Drawing.Color]::LightGreen)
}
```

- [ ] **Step 2: クリックハンドラ内のVM作成ブロックを置き換える**

削除するブロック（`Write-Log "VM 作成中: ..."` から `Write-Log "   VM 作成完了"` まで）:

```powershell
        # NIC1 スイッチを使って VM 作成
        Write-Log "VM 作成中: $VMName  (メモリ $($numMem.Value)GB / CPU $CPUCount コア / NIC $NICCount 枚)" ([System.Drawing.Color]::Cyan)
        New-VM -Name $VMName -MemoryStartupBytes $MemBytes -BootDevice VHD `
               -VHDPath $diffVHD -Generation 2 -Path $vmBase -SwitchName $nicSwitches[0] | Out-Null
        Set-VMProcessor -VMName $VMName -Count $CPUCount

        # NIC1 に静的 MAC を設定 (IP割り当てをスイッチに正確に対応させる)
        Get-VMNetworkAdapter -VMName $VMName | Select-Object -First 1 |
            Set-VMNetworkAdapter -StaticMacAddress $nicMacs[0]
        $mac0 = ($nicMacs[0] -replace '(..)(..)(..)(..)(..)(..)', '$1-$2-$3-$4-$5-$6').ToUpper()
        Write-Log "   NIC1  SW: $($nicSwitches[0])  MAC: $mac0" ([System.Drawing.Color]::LightGreen)

        # NIC2 以降を追加して静的 MAC を設定
        for ($i = 1; $i -lt $NICCount; $i++) {
            Add-VMNetworkAdapter -VMName $VMName -SwitchName $nicSwitches[$i]
            Get-VMNetworkAdapter -VMName $VMName | Select-Object -Last 1 |
                Set-VMNetworkAdapter -StaticMacAddress $nicMacs[$i]
            $macN = ($nicMacs[$i] -replace '(..)(..)(..)(..)(..)(..)', '$1-$2-$3-$4-$5-$6').ToUpper()
            Write-Log "   NIC$($i+1)  SW: $($nicSwitches[$i])  MAC: $macN" ([System.Drawing.Color]::LightGreen)
        }

        if ($UseNestedVM) {
            Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
            Write-Log "   仮想化拡張（ネスト Hyper-V）有効化完了" ([System.Drawing.Color]::LightGreen)
        }
        Write-Log "   VM 作成完了" ([System.Drawing.Color]::LightGreen)
```

置き換え後:
```powershell
        Write-Log "VM 作成中: $VMName  (メモリ $($numMem.Value)GB / CPU $CPUCount コア / NIC $NICCount 枚)" ([System.Drawing.Color]::Cyan)
        New-HyperVVM -VMName $VMName -DiffVHD $diffVHD -VmBase $vmBase -MemBytes $MemBytes `
            -CPUCount $CPUCount -NicSwitches $nicParams.Switches -NicMacs $nicParams.Macs `
            -NICCount $NICCount -UseNestedVM $UseNestedVM
```

- [ ] **Step 3: 構文チェック**

```powershell
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'D:\prj\vmcreate\vmcreate-gui.ps1', [ref]$null, [ref]$errs)
if ($errs.Count -eq 0) { "OK" } else { $errs }
```

期待出力: `OK`

- [ ] **Step 4: コミット**

```bash
git add vmcreate/vmcreate-gui.ps1
git commit -m "refactor(vmcreate): extract New-HyperVVM"
```

---

### Task 7: 最終確認

**Files:**
- Modify: `vmcreate\vmcreate-gui.ps1` (確認のみ)

- [ ] **Step 1: クリックハンドラの行数を確認する**

```powershell
$content = Get-Content 'D:\prj\vmcreate\vmcreate-gui.ps1'
$start = ($content | Select-String -Pattern '^\$btnCreate\.Add_Click' | Select-Object -First 1).LineNumber
$end   = ($content | Select-String -Pattern '^}\)$' | Where-Object { $_.LineNumber -gt $start } | Select-Object -First 1).LineNumber
"クリックハンドラ: line $start 〜 $end ($($end - $start + 1) 行)"
```

期待: 60行以下

- [ ] **Step 2: 全ファイルの構文チェック**

```powershell
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'D:\prj\vmcreate\vmcreate-gui.ps1', [ref]$null, [ref]$errs)
if ($errs.Count -eq 0) { "OK: 構文エラーなし" } else { $errs }
```

期待出力: `OK: 構文エラーなし`

- [ ] **Step 3: ヘルパー関数が全て定義されていることを確認する**

```powershell
$names = @('Write-Log','Get-NicParams','New-UnattendXml','New-GuestSetupScript','Set-GuestRegistry','New-HyperVVM')
foreach ($n in $names) {
    $hit = Select-String -Path 'D:\prj\vmcreate\vmcreate-gui.ps1' -Pattern "^function $n"
    if ($hit) { "OK: $n" } else { "MISSING: $n" }
}
```

期待出力: 全て `OK: ...`

- [ ] **Step 4: 旧変数名が残っていないことを確認する**

```powershell
$old = @('nicSwitches','nicIPList','nicMacs','TempHiveKey')
foreach ($v in $old) {
    $hits = Select-String -Path 'D:\prj\vmcreate\vmcreate-gui.ps1' -Pattern "\`$$v\b" | Where-Object { $_ -notmatch '^\s*#' }
    if ($hits) { "WARN: `$$v がまだ残存 ($($hits.Count) 箇所)" } else { "OK: `$$v なし" }
}
```

期待出力: 全て `OK: ...`

- [ ] **Step 5: 最終コミット**

```bash
git add vmcreate/vmcreate-gui.ps1
git commit -m "refactor(vmcreate): final verification pass"
```
