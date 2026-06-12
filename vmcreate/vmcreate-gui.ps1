# 管理者権限で再起動
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process pwsh -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Hyper-V VM 作成ツール"
$form.ClientSize = New-Object System.Drawing.Size(700, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$tabCtrl = New-Object System.Windows.Forms.TabControl
$tabCtrl.Location = New-Object System.Drawing.Point(5, 5)
$tabCtrl.Size = New-Object System.Drawing.Size(688, 435)
$form.Controls.Add($tabCtrl)

$tabBasic   = New-Object System.Windows.Forms.TabPage; $tabBasic.Text   = "基本設定"
$tabNetwork = New-Object System.Windows.Forms.TabPage; $tabNetwork.Text = "ネットワーク"
$tabRoles   = New-Object System.Windows.Forms.TabPage; $tabRoles.Text   = "ロール / AD"
$tabOptions = New-Object System.Windows.Forms.TabPage; $tabOptions.Text = "オプション"
$tabCtrl.TabPages.AddRange(@($tabBasic, $tabNetwork, $tabRoles, $tabOptions))

function Add-Row($parent, [ref]$y, $labelText, $control, $ctrlWidth = 200) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $labelText
    $lbl.Location = New-Object System.Drawing.Point(10, ($y.Value + 3))
    $lbl.Size = New-Object System.Drawing.Size(130, 20)
    $lbl.TextAlign = "MiddleRight"
    $control.Location = New-Object System.Drawing.Point(145, $y.Value)
    $control.Width = $ctrlWidth
    $parent.Controls.Add($lbl)
    $parent.Controls.Add($control)
    $y.Value += 32
}

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
        $iSCSITargetScript = @"
Install-WindowsFeature -Name FS-iSCSITarget-Server -IncludeManagementTools
`$diskDir = Split-Path '$($p.ISCSIDiskPath)' -Parent
if (-not (Test-Path `$diskDir)) { New-Item -ItemType Directory -Path `$diskDir -Force | Out-Null }
New-IscsiVirtualDisk -Path '$($p.ISCSIDiskPath)' -Size $($p.ISCSIDiskGB)GB
`$ids = '$($p.ISCSIInitIPs)'.Split(',') | ForEach-Object { "IPAddress:`$(`$_.Trim())" }
New-IscsiServerTarget -TargetName '$($p.ISCSITargetName)' -InitiatorIds `$ids
Add-IscsiVirtualDiskTargetMapping -TargetName '$($p.ISCSITargetName)' -Path '$($p.ISCSIDiskPath)'
"@
        $parts += $iSCSITargetScript
    }

    # --- iSCSI イニシエーター ---
    if ($p.RoleiSCSIInit) {
        $iSCSIInitScript = @"
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
        $parts += $iSCSIInitScript
    }

    # --- IIS ---
    if ($p.RoleIIS)    { $parts += "Install-WindowsFeature -Name Web-Server -IncludeManagementTools" }

    # --- Windows Server バックアップ ---
    if ($p.RoleBackup) { $parts += "Install-WindowsFeature -Name Windows-Server-Backup" }

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
            $adScript = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Restart:`$false
Import-Module ADDSDeployment
`$safePwd = ConvertTo-SecureString '$($p.DSRMPass)' -AsPlainText -Force
Install-ADDSForest ``
    -DomainName '$($p.Domain)' ``
    -SafeModeAdministratorPassword `$safePwd ``
    -InstallDNS ``
    -Force
"@
            $parts += $adScript
        }
        2 {
            $adScript = @"
Start-Sleep -Seconds 60
`$password   = ConvertTo-SecureString '$($p.DomainAdminPass)' -AsPlainText -Force
`$credential = New-Object PSCredential('$($p.DomainAdmin)', `$password)
Add-Computer -DomainName '$($p.Domain)' -Credential `$credential -Restart -Force
"@
            $parts += $adScript
        }
        3 {
            $adScript = @"
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
            $parts += $adScript
        }
    }

    # --- ドメイン参加なし + Hyper-V/Cluster: Phase1 で直接インストール ---
    if ($featureNames.Count -gt 0 -and $p.ADRole -eq 0) {
        $parts += "Install-WindowsFeature -Name $($featureNames -join ',') -IncludeManagementTools -Restart:`$false"
        $parts += "shutdown /r /f /t 5"
    }

    return @{ Script = ($parts -join "`n`n"); Phase2 = $phase2Script }
}

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

# ============================================================
# Tab1: 基本設定  (仮想スイッチはネットワークタブの NIC 毎に設定)
# ============================================================
$y1 = 10

$txtVMName = New-Object System.Windows.Forms.TextBox
Add-Row $tabBasic ([ref]$y1) "VM 名 :" $txtVMName 300

$pnlVHD = New-Object System.Windows.Forms.Panel; $pnlVHD.Height = 26
$txtVHDPath = New-Object System.Windows.Forms.TextBox
$txtVHDPath.Width = 220; $txtVHDPath.Location = New-Object System.Drawing.Point(0, 0)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "参照..."; $btnBrowse.Width = 60; $btnBrowse.Height = 26
$btnBrowse.Location = New-Object System.Drawing.Point(225, 0)
$pnlVHD.Controls.AddRange(@($txtVHDPath, $btnBrowse))
Add-Row $tabBasic ([ref]$y1) "親VHDX パス :" $pnlVHD 290

$txtBasePath = New-Object System.Windows.Forms.TextBox; $txtBasePath.Text = "D:\Hyper-V"
Add-Row $tabBasic ([ref]$y1) "ベースパス :" $txtBasePath 300

$pnlMem = New-Object System.Windows.Forms.Panel; $pnlMem.Height = 26
$numMem = New-Object System.Windows.Forms.NumericUpDown
$numMem.Width = 70; $numMem.Minimum = 1; $numMem.Maximum = 128; $numMem.Value = 4
$numMem.Location = New-Object System.Drawing.Point(0, 0)
$lblGB = New-Object System.Windows.Forms.Label; $lblGB.Text = "GB"
$lblGB.Location = New-Object System.Drawing.Point(74, 3); $lblGB.AutoSize = $true
$pnlMem.Controls.AddRange(@($numMem, $lblGB))
Add-Row $tabBasic ([ref]$y1) "メモリ :" $pnlMem 150

$numCPU = New-Object System.Windows.Forms.NumericUpDown
$numCPU.Width = 70; $numCPU.Minimum = 1; $numCPU.Maximum = 32; $numCPU.Value = 2
Add-Row $tabBasic ([ref]$y1) "CPU 数 :" $numCPU 70

$txtPassword = New-Object System.Windows.Forms.TextBox; $txtPassword.Text = "TS12345!"
Add-Row $tabBasic ([ref]$y1) "Admin パスワード :" $txtPassword 200

# ============================================================
# Tab2: ネットワーク
# ============================================================
$y2 = 10

$chkUseIP = New-Object System.Windows.Forms.CheckBox
$chkUseIP.Text = "静的 IP / DNS を設定する"
$chkUseIP.Location = New-Object System.Drawing.Point(10, $y2); $chkUseIP.AutoSize = $true
$tabNetwork.Controls.Add($chkUseIP); $y2 += 28

$pnlNICCount = New-Object System.Windows.Forms.Panel; $pnlNICCount.Height = 26
$numNICCount = New-Object System.Windows.Forms.NumericUpDown
$numNICCount.Width = 60; $numNICCount.Minimum = 1; $numNICCount.Maximum = 4; $numNICCount.Value = 1
$numNICCount.Location = New-Object System.Drawing.Point(0, 0)
$lblNICUnit = New-Object System.Windows.Forms.Label; $lblNICUnit.Text = "枚"
$lblNICUnit.Location = New-Object System.Drawing.Point(64, 3); $lblNICUnit.AutoSize = $true
$pnlNICCount.Controls.AddRange(@($numNICCount, $lblNICUnit))
Add-Row $tabNetwork ([ref]$y2) "NIC 枚数 :" $pnlNICCount 100

# 仮想スイッチ一覧を取得
$vmSwitchNames = @()
try { $vmSwitchNames = @(Get-VMSwitch | Select-Object -ExpandProperty Name) } catch {}

$script:nicControls = @()
for ($i = 0; $i -lt 4; $i++) {
    # NIC パネル: 2行 (スイッチ行 + IP行) 計56px
    $pnlNIC = New-Object System.Windows.Forms.Panel
    $pnlNIC.Height = 56; $pnlNIC.Width = 660
    $pnlNIC.Location = New-Object System.Drawing.Point(10, $y2)
    $pnlNIC.Visible = ($i -eq 0)

    # --- 行1: スイッチ選択 (常に有効) ---
    $lblNICHdr = New-Object System.Windows.Forms.Label
    $lblNICHdr.Text = "NIC $($i+1) スイッチ:"
    $lblNICHdr.Location = New-Object System.Drawing.Point(0, 4); $lblNICHdr.Width = 110; $lblNICHdr.TextAlign = "MiddleRight"

    $cboNICSwitch = New-Object System.Windows.Forms.ComboBox
    $cboNICSwitch.DropDownStyle = "DropDownList"; $cboNICSwitch.Width = 220
    $cboNICSwitch.Location = New-Object System.Drawing.Point(113, 1)
    foreach ($sw in $vmSwitchNames) { $cboNICSwitch.Items.Add($sw) | Out-Null }
    if ($cboNICSwitch.Items.Contains("Default Switch")) { $cboNICSwitch.SelectedItem = "Default Switch" }
    elseif ($cboNICSwitch.Items.Count -gt 0) { $cboNICSwitch.SelectedIndex = 0 }

    # --- 行2: IP / prefix / DNS (chkUseIP でトグル) ---
    $txtNICIP = New-Object System.Windows.Forms.TextBox
    $txtNICIP.Width = 120; $txtNICIP.Location = New-Object System.Drawing.Point(113, 30); $txtNICIP.Enabled = $false

    $lblSlash = New-Object System.Windows.Forms.Label
    $lblSlash.Text = "/"; $lblSlash.Location = New-Object System.Drawing.Point(237, 33); $lblSlash.AutoSize = $true

    $numNICPrefix = New-Object System.Windows.Forms.NumericUpDown
    $numNICPrefix.Width = 52; $numNICPrefix.Minimum = 8; $numNICPrefix.Maximum = 30; $numNICPrefix.Value = 24
    $numNICPrefix.Location = New-Object System.Drawing.Point(246, 30); $numNICPrefix.Enabled = $false

    $lblNICDNS = New-Object System.Windows.Forms.Label
    $lblNICDNS.Text = "DNS:"; $lblNICDNS.Location = New-Object System.Drawing.Point(302, 33); $lblNICDNS.AutoSize = $true

    $txtNICDNS = New-Object System.Windows.Forms.TextBox
    $txtNICDNS.Width = 120; $txtNICDNS.Location = New-Object System.Drawing.Point(330, 30); $txtNICDNS.Enabled = $false

    $lblNICGW = New-Object System.Windows.Forms.Label
    $lblNICGW.Text = "GW:"; $lblNICGW.Location = New-Object System.Drawing.Point(455, 33); $lblNICGW.AutoSize = $true

    $txtNICGW = New-Object System.Windows.Forms.TextBox
    $txtNICGW.Width = 155; $txtNICGW.Location = New-Object System.Drawing.Point(480, 30); $txtNICGW.Enabled = $false

    $pnlNIC.Controls.AddRange(@($lblNICHdr, $cboNICSwitch, $txtNICIP, $lblSlash, $numNICPrefix, $lblNICDNS, $txtNICDNS, $lblNICGW, $txtNICGW))
    $tabNetwork.Controls.Add($pnlNIC)
    $script:nicControls += @{
        Panel  = $pnlNIC
        Switch = $cboNICSwitch
        IP     = $txtNICIP
        Prefix = $numNICPrefix
        DNS    = $txtNICDNS
        GW     = $txtNICGW
    }
    $y2 += 60
}

$txtDomain = New-Object System.Windows.Forms.TextBox; $txtDomain.Text = "contoso2022.local"
Add-Row $tabNetwork ([ref]$y2) "ドメイン名 :" $txtDomain 220

# ============================================================
# Tab3: ロール / AD
# ============================================================
$y3 = 10

$chkUseAD = New-Object System.Windows.Forms.CheckBox
$chkUseAD.Text = "ドメインに参加 / AD ロールを設定する"
$chkUseAD.Location = New-Object System.Drawing.Point(10, $y3); $chkUseAD.AutoSize = $true
$tabRoles.Controls.Add($chkUseAD); $y3 += 28

$cboADRole = New-Object System.Windows.Forms.ComboBox; $cboADRole.DropDownStyle = "DropDownList"
$cboADRole.Items.AddRange(@("なし", "新規フォレスト（第1 DC）", "ドメイン参加（メンバー）", "追加 DC"))
$cboADRole.SelectedIndex = 0; $cboADRole.Enabled = $false
Add-Row $tabRoles ([ref]$y3) "AD ロール :" $cboADRole 250

$lblDSRM = New-Object System.Windows.Forms.Label; $lblDSRM.Text = "DSRM パスワード :"
$lblDSRM.Location = New-Object System.Drawing.Point(10, ($y3+3)); $lblDSRM.Size = New-Object System.Drawing.Size(130,20)
$lblDSRM.TextAlign = "MiddleRight"; $lblDSRM.Enabled = $false; $tabRoles.Controls.Add($lblDSRM)
$txtDSRMPass = New-Object System.Windows.Forms.TextBox; $txtDSRMPass.Text = "TS12345!"; $txtDSRMPass.Width = 200
$txtDSRMPass.Location = New-Object System.Drawing.Point(145, $y3); $txtDSRMPass.Enabled = $false
$tabRoles.Controls.Add($txtDSRMPass); $y3 += 32

$lblDomainAdmin = New-Object System.Windows.Forms.Label; $lblDomainAdmin.Text = "ドメイン管理者 :"
$lblDomainAdmin.Location = New-Object System.Drawing.Point(10, ($y3+3)); $lblDomainAdmin.Size = New-Object System.Drawing.Size(130,20)
$lblDomainAdmin.TextAlign = "MiddleRight"; $lblDomainAdmin.Enabled = $false; $tabRoles.Controls.Add($lblDomainAdmin)
$txtDomainAdmin = New-Object System.Windows.Forms.TextBox; $txtDomainAdmin.Text = "contoso2022\administrator"; $txtDomainAdmin.Width = 230
$txtDomainAdmin.Location = New-Object System.Drawing.Point(145, $y3); $txtDomainAdmin.Enabled = $false
$tabRoles.Controls.Add($txtDomainAdmin); $y3 += 32

$lblDomainAdminPass = New-Object System.Windows.Forms.Label; $lblDomainAdminPass.Text = "管理者パスワード :"
$lblDomainAdminPass.Location = New-Object System.Drawing.Point(10, ($y3+3)); $lblDomainAdminPass.Size = New-Object System.Drawing.Size(130,20)
$lblDomainAdminPass.TextAlign = "MiddleRight"; $lblDomainAdminPass.Enabled = $false; $tabRoles.Controls.Add($lblDomainAdminPass)
$txtDomainAdminPass = New-Object System.Windows.Forms.TextBox; $txtDomainAdminPass.Text = "TS12345!"; $txtDomainAdminPass.Width = 200
$txtDomainAdminPass.Location = New-Object System.Drawing.Point(145, $y3); $txtDomainAdminPass.Enabled = $false
$tabRoles.Controls.Add($txtDomainAdminPass); $y3 += 36

$sepRole = New-Object System.Windows.Forms.Label; $sepRole.Text = "--- Windows ロール / 機能 ---"
$sepRole.Location = New-Object System.Drawing.Point(10, $y3); $sepRole.AutoSize = $true
$sepRole.ForeColor = [System.Drawing.Color]::DimGray; $tabRoles.Controls.Add($sepRole); $y3 += 22

$chkRoleHyperV = New-Object System.Windows.Forms.CheckBox; $chkRoleHyperV.Text = "Hyper-V"
$chkRoleHyperV.Location = New-Object System.Drawing.Point(10, $y3); $chkRoleHyperV.AutoSize = $true; $tabRoles.Controls.Add($chkRoleHyperV)
$chkRoleCluster = New-Object System.Windows.Forms.CheckBox; $chkRoleCluster.Text = "フェールオーバークラスタリング"
$chkRoleCluster.Location = New-Object System.Drawing.Point(120, $y3); $chkRoleCluster.AutoSize = $true; $tabRoles.Controls.Add($chkRoleCluster)
$y3 += 26

$chkRoleiSCSITarget = New-Object System.Windows.Forms.CheckBox; $chkRoleiSCSITarget.Text = "iSCSI ターゲット"
$chkRoleiSCSITarget.Location = New-Object System.Drawing.Point(10, $y3); $chkRoleiSCSITarget.AutoSize = $true; $tabRoles.Controls.Add($chkRoleiSCSITarget)
$chkRoleiSCSIInit = New-Object System.Windows.Forms.CheckBox; $chkRoleiSCSIInit.Text = "iSCSI イニシエーター"
$chkRoleiSCSIInit.Location = New-Object System.Drawing.Point(200, $y3); $chkRoleiSCSIInit.AutoSize = $true; $tabRoles.Controls.Add($chkRoleiSCSIInit)
$y3 += 26

$chkRoleIIS = New-Object System.Windows.Forms.CheckBox; $chkRoleIIS.Text = "IIS (Web サーバー)"
$chkRoleIIS.Location = New-Object System.Drawing.Point(10, $y3); $chkRoleIIS.AutoSize = $true; $tabRoles.Controls.Add($chkRoleIIS)
$chkRoleBackup = New-Object System.Windows.Forms.CheckBox; $chkRoleBackup.Text = "Windows Server バックアップ"
$chkRoleBackup.Location = New-Object System.Drawing.Point(200, $y3); $chkRoleBackup.AutoSize = $true; $tabRoles.Controls.Add($chkRoleBackup)
$y3 += 28

$lblISCSITargetName = New-Object System.Windows.Forms.Label; $lblISCSITargetName.Text = "ターゲット名 :"
$lblISCSITargetName.Location = New-Object System.Drawing.Point(10, ($y3+3)); $lblISCSITargetName.Size = New-Object System.Drawing.Size(130,20)
$lblISCSITargetName.TextAlign = "MiddleRight"; $lblISCSITargetName.Enabled = $false; $tabRoles.Controls.Add($lblISCSITargetName)
$txtISCSITargetName = New-Object System.Windows.Forms.TextBox; $txtISCSITargetName.Text = "Target01"; $txtISCSITargetName.Width = 150
$txtISCSITargetName.Location = New-Object System.Drawing.Point(145, $y3); $txtISCSITargetName.Enabled = $false; $tabRoles.Controls.Add($txtISCSITargetName); $y3 += 32

$lblISCSIDiskPath = New-Object System.Windows.Forms.Label; $lblISCSIDiskPath.Text = "仮想ディスクパス :"
$lblISCSIDiskPath.Location = New-Object System.Drawing.Point(10, ($y3+3)); $lblISCSIDiskPath.Size = New-Object System.Drawing.Size(130,20)
$lblISCSIDiskPath.TextAlign = "MiddleRight"; $lblISCSIDiskPath.Enabled = $false; $tabRoles.Controls.Add($lblISCSIDiskPath)
$pnlISCSIDisk = New-Object System.Windows.Forms.Panel; $pnlISCSIDisk.Height = 26; $pnlISCSIDisk.Width = 340
$pnlISCSIDisk.Location = New-Object System.Drawing.Point(145, $y3); $pnlISCSIDisk.Enabled = $false
$txtISCSIDiskPath = New-Object System.Windows.Forms.TextBox; $txtISCSIDiskPath.Text = "C:\iSCSIVirtualDisks\Disk01.vhdx"; $txtISCSIDiskPath.Width = 230
$txtISCSIDiskPath.Location = New-Object System.Drawing.Point(0, 0)
$numISCSIDiskGB = New-Object System.Windows.Forms.NumericUpDown; $numISCSIDiskGB.Width = 55
$numISCSIDiskGB.Minimum = 1; $numISCSIDiskGB.Maximum = 9999; $numISCSIDiskGB.Value = 10
$numISCSIDiskGB.Location = New-Object System.Drawing.Point(235, 0)
$lblISCSIGB = New-Object System.Windows.Forms.Label; $lblISCSIGB.Text = "GB"
$lblISCSIGB.Location = New-Object System.Drawing.Point(293, 3); $lblISCSIGB.AutoSize = $true
$pnlISCSIDisk.Controls.AddRange(@($txtISCSIDiskPath, $numISCSIDiskGB, $lblISCSIGB))
$tabRoles.Controls.Add($pnlISCSIDisk); $y3 += 32

$lblISCSIInitIPs = New-Object System.Windows.Forms.Label; $lblISCSIInitIPs.Text = "イニシエーター IP :"
$lblISCSIInitIPs.Location = New-Object System.Drawing.Point(10, ($y3+3)); $lblISCSIInitIPs.Size = New-Object System.Drawing.Size(130,20)
$lblISCSIInitIPs.TextAlign = "MiddleRight"; $lblISCSIInitIPs.Enabled = $false; $tabRoles.Controls.Add($lblISCSIInitIPs)
$txtISCSIInitIPs = New-Object System.Windows.Forms.TextBox; $txtISCSIInitIPs.Width = 280
$txtISCSIInitIPs.Location = New-Object System.Drawing.Point(145, $y3); $txtISCSIInitIPs.Enabled = $false
$tabRoles.Controls.Add($txtISCSIInitIPs); $y3 += 32

$lblISCSIPortal = New-Object System.Windows.Forms.Label; $lblISCSIPortal.Text = "ターゲットポータル IP :"
$lblISCSIPortal.Location = New-Object System.Drawing.Point(10, ($y3+3)); $lblISCSIPortal.Size = New-Object System.Drawing.Size(130,20)
$lblISCSIPortal.TextAlign = "MiddleRight"; $lblISCSIPortal.Enabled = $false; $tabRoles.Controls.Add($lblISCSIPortal)
$txtISCSIPortal = New-Object System.Windows.Forms.TextBox; $txtISCSIPortal.Width = 180
$txtISCSIPortal.Location = New-Object System.Drawing.Point(145, $y3); $txtISCSIPortal.Enabled = $false
$tabRoles.Controls.Add($txtISCSIPortal)

# ============================================================
# Tab4: オプション
# ============================================================
$y4 = 15
$chkAutoLogon = New-Object System.Windows.Forms.CheckBox; $chkAutoLogon.Text = "自動ログオンを有効にする"
$chkAutoLogon.Location = New-Object System.Drawing.Point(15, $y4); $chkAutoLogon.AutoSize = $true; $chkAutoLogon.Checked = $true
$tabOptions.Controls.Add($chkAutoLogon); $y4 += 28

$chkDisableCAD = New-Object System.Windows.Forms.CheckBox; $chkDisableCAD.Text = "Ctrl+Alt+Del を無効にする"
$chkDisableCAD.Location = New-Object System.Drawing.Point(15, $y4); $chkDisableCAD.AutoSize = $true; $chkDisableCAD.Checked = $true
$tabOptions.Controls.Add($chkDisableCAD); $y4 += 28

$chkNestedVM = New-Object System.Windows.Forms.CheckBox; $chkNestedVM.Text = "仮想化拡張を公開する（ネスト Hyper-V 用）"
$chkNestedVM.Location = New-Object System.Drawing.Point(15, $y4); $chkNestedVM.AutoSize = $true; $chkNestedVM.Checked = $false
$tabOptions.Controls.Add($chkNestedVM)

# ============================================================
# ボタン + ログ
# ============================================================
$btnCreate = New-Object System.Windows.Forms.Button
$btnCreate.Text = "VM を作成する"
$btnCreate.Location = New-Object System.Drawing.Point(245, 448)
$btnCreate.Size = New-Object System.Drawing.Size(200, 34)
$btnCreate.Font = New-Object System.Drawing.Font("Meiryo UI", 10, [System.Drawing.FontStyle]::Bold)
$btnCreate.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$btnCreate.ForeColor = [System.Drawing.Color]::White
$btnCreate.FlatStyle = "Flat"
$form.Controls.Add($btnCreate)

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location = New-Object System.Drawing.Point(5, 490)
$rtbLog.Size = New-Object System.Drawing.Size(688, 100)
$rtbLog.ReadOnly = $true
$rtbLog.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)
$rtbLog.ForeColor = [System.Drawing.Color]::White
$rtbLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$rtbLog.ScrollBars = "Vertical"
$form.Controls.Add($rtbLog)

# ============================================================
# イベントハンドラ
# ============================================================
$chkUseIP.Add_CheckedChanged({
    $on    = $chkUseIP.Checked
    $count = [int]$numNICCount.Value
    for ($i = 0; $i -lt 4; $i++) {
        $c = $script:nicControls[$i]
        $c.IP.Enabled     = ($i -lt $count -and $on)
        $c.Prefix.Enabled = ($i -lt $count -and $on)
        $c.DNS.Enabled    = ($i -lt $count -and $on)
        $c.GW.Enabled     = ($i -lt $count -and $on)
    }
})

$numNICCount.Add_ValueChanged({
    $count = [int]$numNICCount.Value
    $ipOn  = $chkUseIP.Checked
    for ($i = 0; $i -lt 4; $i++) {
        $c = $script:nicControls[$i]
        $c.Panel.Visible  = ($i -lt $count)
        $c.IP.Enabled     = ($i -lt $count -and $ipOn)
        $c.Prefix.Enabled = ($i -lt $count -and $ipOn)
        $c.DNS.Enabled    = ($i -lt $count -and $ipOn)
        $c.GW.Enabled     = ($i -lt $count -and $ipOn)
    }
})

$chkUseAD.Add_CheckedChanged({
    $on = $chkUseAD.Checked
    $cboADRole.Enabled = $on
    if ($on) {
        $role = $cboADRole.SelectedIndex
        $showDSRM    = ($role -eq 1 -or $role -eq 3)
        $showDomCred = ($role -eq 2 -or $role -eq 3)
        foreach ($c in @($lblDSRM, $txtDSRMPass))                                                                             { $c.Enabled = $showDSRM    }
        foreach ($c in @($lblDomainAdmin, $txtDomainAdmin, $lblDomainAdminPass, $txtDomainAdminPass))                         { $c.Enabled = $showDomCred }
    } else {
        foreach ($c in @($lblDSRM, $txtDSRMPass, $lblDomainAdmin, $txtDomainAdmin, $lblDomainAdminPass, $txtDomainAdminPass)) { $c.Enabled = $false }
    }
})

$cboADRole.Add_SelectedIndexChanged({
    if (-not $chkUseAD.Checked) { return }
    $role = $cboADRole.SelectedIndex
    $showDSRM    = ($role -eq 1 -or $role -eq 3)
    $showDomCred = ($role -eq 2 -or $role -eq 3)
    foreach ($c in @($lblDSRM, $txtDSRMPass))                                                     { $c.Enabled = $showDSRM    }
    foreach ($c in @($lblDomainAdmin, $txtDomainAdmin, $lblDomainAdminPass, $txtDomainAdminPass)) { $c.Enabled = $showDomCred }
})

$chkRoleHyperV.Add_CheckedChanged({
    if ($chkRoleHyperV.Checked) { $chkNestedVM.Checked = $true }
})

$chkRoleiSCSITarget.Add_CheckedChanged({
    $on = $chkRoleiSCSITarget.Checked
    foreach ($c in @($lblISCSITargetName, $txtISCSITargetName, $lblISCSIDiskPath, $pnlISCSIDisk, $lblISCSIInitIPs, $txtISCSIInitIPs)) { $c.Enabled = $on }
})

$chkRoleiSCSIInit.Add_CheckedChanged({
    $on = $chkRoleiSCSIInit.Checked
    foreach ($c in @($lblISCSIPortal, $txtISCSIPortal)) { $c.Enabled = $on }
})

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "VHDX / VHD ファイル (*.vhdx;*.vhd)|*.vhdx;*.vhd"
    $dlg.InitialDirectory = $txtBasePath.Text
    if ($dlg.ShowDialog() -eq "OK") { $txtVHDPath.Text = $dlg.FileName }
})

# ============================================================
# VM 作成処理
# ============================================================
$btnCreate.Add_Click({
    $VMName        = $txtVMName.Text.Trim()
    $ParentVHD     = $txtVHDPath.Text.Trim()
    $BasePath      = $txtBasePath.Text.TrimEnd('\')
    $MemBytes      = [long]$numMem.Value * 1GB
    $CPUCount      = [int]$numCPU.Value
    $AdminPass     = $txtPassword.Text
    $Domain        = $txtDomain.Text.Trim()
    $UseAutoLogon  = $chkAutoLogon.Checked
    $UseDisableCAD = $chkDisableCAD.Checked
    $UseNestedVM   = $chkNestedVM.Checked
    $UseStaticIP   = $chkUseIP.Checked
    $NICCount      = [int]$numNICCount.Value
    $ADRole        = if ($chkUseAD.Checked) { $cboADRole.SelectedIndex } else { 0 }

    $nicParams = Get-NicParams -NICCount $NICCount -UseStaticIP $UseStaticIP

    # バリデーション
    if (-not $VMName)                { [System.Windows.Forms.MessageBox]::Show("VM名を入力してください。");                    return }
    if (-not (Test-Path $ParentVHD)) { [System.Windows.Forms.MessageBox]::Show("親VHDXが見つかりません。");                   return }
    if (-not $nicParams.Switches[0]) { [System.Windows.Forms.MessageBox]::Show("NIC1の仮想スイッチを選択してください。");     return }
    if ($UseStaticIP -and $nicParams.IPList.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("静的IPを有効にする場合はNIC1のIPアドレスを入力してください。"); return
    }
    if ($ADRole -ne 0 -and -not $Domain) {
        [System.Windows.Forms.MessageBox]::Show("ADロールを使用する場合はドメイン名を入力してください。"); return
    }
    if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
        [System.Windows.Forms.MessageBox]::Show("VM '$VMName' は既に存在します。"); return
    }

    $btnCreate.Enabled = $false
    $rtbLog.Clear()

    $vmBase      = "$BasePath\$VMName"
    $answerDir   = "$vmBase\Unattend"
    $answerFile  = "$answerDir\Autounattend.xml"
    $diffVHD     = "$vmBase\$VMName-diff.vhdx"
    $hiveKey    = "TempSystemHive_$VMName"

    try {
        Write-Log "フォルダ作成: $answerDir" ([System.Drawing.Color]::Cyan)
        New-Item -Path $answerDir -ItemType Directory -Force | Out-Null

        Write-Log "応答ファイル作成..." ([System.Drawing.Color]::Cyan)
        $xml = New-UnattendXml -VMName $VMName -AdminPass $AdminPass -UseAutoLogon $UseAutoLogon
        $xml | Out-File -Encoding UTF8 -FilePath $answerFile
        Write-Log "   保存: $answerFile" ([System.Drawing.Color]::LightGreen)

        Write-Log "差分ディスク作成: $diffVHD" ([System.Drawing.Color]::Cyan)
        New-VHD -Path $diffVHD -ParentPath $ParentVHD -Differencing | Out-Null
        Write-Log "   完了" ([System.Drawing.Color]::LightGreen)

        Write-Log "VHD マウント中..." ([System.Drawing.Color]::Cyan)
        $disk      = Mount-VHD -Path $diffVHD -PassThru | Get-Disk
        $partition = $disk | Get-Partition | Sort-Object Size -Descending | Select-Object -First 1
        $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
        $vhdDrive = [char[]](90..65) | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
        if (-not $vhdDrive) { throw "空きドライブレターが見つかりません" }
        Set-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -NewDriveLetter $vhdDrive
        Write-Log "   ドライブ ${vhdDrive}: 割り当て完了" ([System.Drawing.Color]::LightGreen)

        Write-Log "応答ファイルをゲスト OS へコピー..." ([System.Drawing.Color]::Cyan)
        Copy-Item -Path $answerFile -Destination "${vhdDrive}:\AutoUnattend.xml" -Force
        Write-Log "   完了" ([System.Drawing.Color]::LightGreen)

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

        Write-Log "レジストリ設定中..." ([System.Drawing.Color]::Cyan)
        Set-GuestRegistry -VhdDrive $vhdDrive -HiveKey $hiveKey `
            -AdminPass $AdminPass -Domain $Domain `
            -UseAutoLogon $UseAutoLogon -UseDisableCAD $UseDisableCAD

        Write-Log "VHD アンマウント中..." ([System.Drawing.Color]::Cyan)
        Dismount-VHD -Path $diffVHD
        Write-Log "   完了" ([System.Drawing.Color]::LightGreen)

        Write-Log "VM 作成中: $VMName  (メモリ $($numMem.Value)GB / CPU $CPUCount コア / NIC $NICCount 枚)" ([System.Drawing.Color]::Cyan)
        New-HyperVVM -VMName $VMName -DiffVHD $diffVHD -VmBase $vmBase -MemBytes $MemBytes `
            -CPUCount $CPUCount -NicSwitches $nicParams.Switches -NicMacs $nicParams.Macs `
            -NICCount $NICCount -UseNestedVM $UseNestedVM

        Write-Log "VM 起動中..." ([System.Drawing.Color]::Cyan)
        Start-VM -Name $VMName
        Write-Log "`nVM '$VMName' を作成・起動しました！" ([System.Drawing.Color]::LightGreen)

    } catch {
        Write-Log "`nエラー: $_" ([System.Drawing.Color]::Red)
        try { Dismount-VHD -Path $diffVHD -ErrorAction SilentlyContinue } catch {}
        try { if (Test-Path $diffVHD) { Remove-Item -Path $diffVHD -Force -ErrorAction SilentlyContinue } } catch {}
        try { reg unload "HKLM\${hiveKey}SW" 2>$null } catch {}
        try { reg unload "HKLM\$hiveKey"     2>$null } catch {}
    } finally {
        $btnCreate.Enabled = $true
    }
})

# ============================================================
# 設定の保存・読み込み
# ============================================================
$settingsFile = Join-Path $PSScriptRoot "vmcreate-settings.json"

function Save-Settings {
    $nicData = @()
    for ($i = 0; $i -lt 4; $i++) {
        $nicData += @{
            Switch = "$($script:nicControls[$i].Switch.SelectedItem)"
            IP     = $script:nicControls[$i].IP.Text
            Prefix = [int]$script:nicControls[$i].Prefix.Value
            DNS    = $script:nicControls[$i].DNS.Text
            GW     = $script:nicControls[$i].GW.Text
        }
    }
    @{
        VMName          = $txtVMName.Text
        VHDPath         = $txtVHDPath.Text
        BasePath        = $txtBasePath.Text
        Memory          = [int]$numMem.Value
        CPU             = [int]$numCPU.Value
        Password        = $txtPassword.Text
        NICCount        = [int]$numNICCount.Value
        NICData         = $nicData
        Domain          = $txtDomain.Text
        ADRole          = $cboADRole.SelectedIndex
        DSRMPass        = $txtDSRMPass.Text
        DomainAdmin     = $txtDomainAdmin.Text
        DomainAdminPass = $txtDomainAdminPass.Text
        UseIP           = $chkUseIP.Checked
        UseAD           = $chkUseAD.Checked
        RoleHyperV      = $chkRoleHyperV.Checked
        RoleCluster     = $chkRoleCluster.Checked
        RoleiSCSITarget = $chkRoleiSCSITarget.Checked
        RoleiSCSIInit   = $chkRoleiSCSIInit.Checked
        RoleIIS         = $chkRoleIIS.Checked
        RoleBackup      = $chkRoleBackup.Checked
        ISCSITargetName = $txtISCSITargetName.Text
        ISCSIDiskPath   = $txtISCSIDiskPath.Text
        ISCSIDiskGB     = [int]$numISCSIDiskGB.Value
        ISCSIInitIPs    = $txtISCSIInitIPs.Text
        ISCSIPortalIP   = $txtISCSIPortal.Text
        AutoLogon       = $chkAutoLogon.Checked
        DisableCAD      = $chkDisableCAD.Checked
        NestedVM        = $chkNestedVM.Checked
    } | ConvertTo-Json | Out-File -Encoding UTF8 -FilePath $settingsFile
}

function Load-Settings {
    if (-not (Test-Path $settingsFile)) { return }
    try {
        $s = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        if ($s.VMName)   { $txtVMName.Text   = $s.VMName }
        if ($s.VHDPath)  { $txtVHDPath.Text  = $s.VHDPath }
        if ($s.BasePath) { $txtBasePath.Text = $s.BasePath }
        if ($null -ne $s.Memory) { $numMem.Value = $s.Memory }
        if ($null -ne $s.CPU)    { $numCPU.Value = $s.CPU }
        if ($null -ne $s.Password) { $txtPassword.Text = $s.Password }
        if ($null -ne $s.NICCount) { $numNICCount.Value = $s.NICCount }
        if ($s.NICData) {
            for ($i = 0; $i -lt [Math]::Min($s.NICData.Count, 4); $i++) {
                $d = $s.NICData[$i]
                if ($d.Switch -and $script:nicControls[$i].Switch.Items.Contains($d.Switch)) {
                    $script:nicControls[$i].Switch.SelectedItem = $d.Switch
                }
                if ($null -ne $d.IP)     { $script:nicControls[$i].IP.Text      = $d.IP }
                if ($null -ne $d.Prefix) { $script:nicControls[$i].Prefix.Value = $d.Prefix }
                if ($null -ne $d.DNS)    { $script:nicControls[$i].DNS.Text     = $d.DNS }
                if ($null -ne $d.GW)     { $script:nicControls[$i].GW.Text      = $d.GW }
            }
        }
        # 旧フォーマット互換
        elseif ($null -ne $s.IPAddress) {
            $script:nicControls[0].IP.Text = $s.IPAddress
            if ($null -ne $s.Prefix) { $script:nicControls[0].Prefix.Value = $s.Prefix }
            if ($null -ne $s.DNS)    { $script:nicControls[0].DNS.Text = $s.DNS }
            if ($s.SwitchName -and $script:nicControls[0].Switch.Items.Contains($s.SwitchName)) {
                $script:nicControls[0].Switch.SelectedItem = $s.SwitchName
            }
        }
        if ($null -ne $s.Domain)          { $txtDomain.Text             = $s.Domain }
        if ($null -ne $s.ADRole)          { $cboADRole.SelectedIndex    = $s.ADRole }
        if ($null -ne $s.DSRMPass)        { $txtDSRMPass.Text           = $s.DSRMPass }
        if ($null -ne $s.DomainAdmin)     { $txtDomainAdmin.Text        = $s.DomainAdmin }
        if ($null -ne $s.DomainAdminPass) { $txtDomainAdminPass.Text    = $s.DomainAdminPass }
        if ($null -ne $s.UseIP)           { $chkUseIP.Checked           = $s.UseIP }
        if ($null -ne $s.UseAD)           { $chkUseAD.Checked           = $s.UseAD }
        if ($null -ne $s.RoleHyperV)      { $chkRoleHyperV.Checked      = $s.RoleHyperV }
        if ($null -ne $s.RoleCluster)     { $chkRoleCluster.Checked     = $s.RoleCluster }
        if ($null -ne $s.RoleiSCSITarget) { $chkRoleiSCSITarget.Checked = $s.RoleiSCSITarget }
        if ($null -ne $s.RoleiSCSIInit)   { $chkRoleiSCSIInit.Checked   = $s.RoleiSCSIInit }
        if ($null -ne $s.RoleIIS)         { $chkRoleIIS.Checked         = $s.RoleIIS }
        if ($null -ne $s.RoleBackup)      { $chkRoleBackup.Checked      = $s.RoleBackup }
        if ($s.ISCSITargetName) { $txtISCSITargetName.Text = $s.ISCSITargetName }
        if ($s.ISCSIDiskPath)   { $txtISCSIDiskPath.Text   = $s.ISCSIDiskPath }
        if ($null -ne $s.ISCSIDiskGB)   { $numISCSIDiskGB.Value  = $s.ISCSIDiskGB }
        if ($null -ne $s.ISCSIInitIPs)  { $txtISCSIInitIPs.Text  = $s.ISCSIInitIPs }
        if ($null -ne $s.ISCSIPortalIP) { $txtISCSIPortal.Text   = $s.ISCSIPortalIP }
        if ($null -ne $s.AutoLogon)  { $chkAutoLogon.Checked  = $s.AutoLogon }
        if ($null -ne $s.DisableCAD) { $chkDisableCAD.Checked = $s.DisableCAD }
        if ($null -ne $s.NestedVM)   { $chkNestedVM.Checked   = $s.NestedVM }
    } catch {}
}

Load-Settings
$form.Add_FormClosing({ Save-Settings })
[void]$form.ShowDialog()
