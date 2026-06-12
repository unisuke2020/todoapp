# vmcreate リファクタリング設計

## 概要

`vmcreate-gui.ps1` (843行) を可読性・保守性の向上を目的にリファクタリングする。
機能・動作・ファイル構成（単一ファイル）は変更しない。

## 問題点

- `$btnCreate.Add_Click` が355行超で、XML生成・スクリプト生成・レジストリ操作・VM作成をすべて1ハンドラに含む
- 関心の分離がなく、どこで何をしているか追いにくい
- `1vmcreate-gui.ps1`（旧版）が不要なまま残存

## ファイル構造（リファクタリング後）

```
1. 管理者昇格
2. アセンブリ読み込み
3. ヘルパー関数群          ← Add-Row / Write-Log + 新規関数を集約
4. UI構築（タブ4枚）        ← 変更なし
5. UIイベントハンドラ群     ← ほぼ変更なし
6. クリックハンドラ         ← ~355行 → ~50行に圧縮
7. 設定保存・読み込み       ← 変更なし
8. エントリポイント         ← 変更なし
```

## 抽出する関数

### `Get-NicParams`
- 入力: `$NICCount`, `$UseStaticIP`, `$script:nicControls`
- 出力: `@{ Switches = string[]; IPList = hashtable[]; Macs = string[] }`
- 役割: UIからNIC情報を収集し、静的MACを生成してまとめて返す
- 現在: クリックハンドラ先頭のNIC収集・MAC生成コード

### `New-UnattendXml`
- 入力: `$VMName`, `$AdminPass`, `$UseAutoLogon`
- 出力: XML文字列
- 役割: Autounattend.xml の内容を生成して返す
- 現在: クリックハンドラ内のhere-string (`$xml = @"..."@`)

### `New-GuestSetupScript`
- 入力: 静的IP設定・ロール・ADロール・iSCSI等のパラメータ群 (hashtable)
- 出力: setup.ps1 の内容文字列（空文字列なら配置不要）
- 役割: `$scriptParts` の組み立てロジックをすべて内包する
- 現在: クリックハンドラ内の `$scriptParts += ...` 群

### `Set-GuestRegistry`
- 入力: `$vhdDrive`, `$TempHiveKey`, `$VMName`, `$AdminPass`, `$Domain`, `$UseAutoLogon`, `$UseDisableCAD`
- 出力: なし（副作用のみ）
- 役割: SYSTEM/SOFTWARE ハイブの reg load → 書き込み → reg unload をまとめる
- 現在: クリックハンドラ内のレジストリ操作ブロック (660–687行)

### `New-HyperVVM`
- 入力: `$VMName`, `$diffVHD`, `$vmBase`, `$MemBytes`, `$CPUCount`, `$NicParams`, `$UseNestedVM`
- 出力: なし（副作用のみ）
- 役割: `New-VM` → `Set-VMProcessor` → NIC追加・MAC設定 → 仮想化拡張設定
- 現在: クリックハンドラ末尾 (694–718行)

## クリックハンドラ（リファクタリング後のイメージ）

```powershell
$btnCreate.Add_Click({
    # --- 入力収集 ---
    $params = @{ VMName = ...; ParentVHD = ...; ... }
    $nicParams = Get-NicParams ...

    # --- バリデーション ---
    if (-not $params.VMName) { ... return }
    ...

    $btnCreate.Enabled = $false
    $rtbLog.Clear()
    try {
        # フォルダ・Unattend XML
        New-Item ...; $xml = New-UnattendXml ...; $xml | Out-File ...

        # 差分VHD作成・マウント
        New-VHD ...; $disk = Mount-VHD ...

        # ゲストへファイル配置
        Copy-Item (AutoUnattend.xml)
        $script = New-GuestSetupScript $params $nicParams
        if ($script) { ... SetupComplete.cmd + setup.ps1 を配置 }

        # レジストリ編集
        Set-GuestRegistry ...

        # アンマウント → VM作成
        Dismount-VHD ...; New-HyperVVM ...

        Start-VM ...; Write-Log "完了"
    } catch {
        Write-Log "エラー: $_" Red
        # クリーンアップ
    } finally {
        $btnCreate.Enabled = $true
    }
})
```

## その他の変更

- `1vmcreate-gui.ps1`（旧バージョン）を削除する

## 対象外

- UI構築コード（タブ4枚分）は変更しない
- イベントハンドラ（チェックボックスのトグル等）は変更しない
- 設定の保存・読み込み関数は変更しない
- 機能追加・動作変更はしない
