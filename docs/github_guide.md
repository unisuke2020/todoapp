# GitHubとは？わかりやすく解説

## 一言で言うと

> **コードを保存・共有・共同編集できるサービス**

プログラムのソースコードを「クラウド上に保存」して、チームで一緒に開発できる場所です。

---

## よく使われるたとえ

| たとえ | 意味 |
|--------|------|
| 📁 **Googleドライブ** | コードをクラウドに保存して、どこからでもアクセスできる |
| 📝 **Googleドキュメントの履歴** | 「いつ・誰が・何を変えたか」がすべて記録される |
| 🔀 **Slack + ドライブ** | チームでコードを共有・レビュー・議論できる |

---

## GitとGitHubの違い

多くの人が混乱しますが、別物です。

```
Git       = 変更履歴を管理するツール（自分のパソコン上で動く）
GitHub    = Gitの履歴をクラウドで共有するサービス（ウェブ上）
```

### たとえるなら
- **Git** = 手元の「下書きノート」
- **GitHub** = ノートを保存する「クラウドの本棚」

---

## GitHubの主な機能

### 1. リポジトリ（Repository）
プロジェクトごとの「フォルダ」のこと。  
コード・画像・設定ファイルなど、プロジェクトに必要なものをまとめて管理します。

```
例）
my-app/
  ├── index.html
  ├── style.css
  └── script.js
```

### 2. コミット（Commit）
変更内容を「保存する」こと。  
「何を変えたか」のメモ（コミットメッセージ）と一緒に記録します。

```
例）
✅ "ログイン機能を追加"
✅ "バグ修正: ボタンが押せない問題を解決"
✅ "README を更新"
```

### 3. ブランチ（Branch）
「作業用のコピー」を作る機能。  
本番のコードを壊さずに、新機能を試したりできます。

```
main（本番）
  └── feature/login（新機能の開発中）
  └── fix/button-bug（バグ修正中）
```

### 4. プルリクエスト（Pull Request / PR）
変更内容を「レビューしてもらってから本番に反映する」仕組み。  
チーム開発では必ず使います。

```
【流れ】
① 自分のブランチで開発する
② プルリクエストを作成
③ チームメンバーがコードをレビュー
④ 問題なければ main に統合（マージ）
```

### 5. Issues（イシュー）
バグ報告・機能追加の要望・タスク管理に使う機能。  
GitHubの中でタスク管理もできます。

---

## Claude Codeとの関係

Claude Codeはターミナルから直接GitHubと連携できます。

```bash
# よく使うコマンド（Claude Codeが自動でやってくれることも）
git init          # リポジトリを作成
git add .         # 変更をステージング
git commit -m "メッセージ"  # 変更を保存
git push          # GitHubにアップロード
git pull          # GitHubから最新を取得
```

Claude Codeに「GitHubにプッシュして」と指示すると、これらを自動で実行してくれます。

---

## まとめ

```
GitHub ＝ コードのための「クラウド保存 ＋ 変更履歴 ＋ チーム共有」サービス

✅ いつでもどこでもコードにアクセスできる
✅ 誰が何を変えたか全部わかる
✅ チームでレビューしながら開発できる
✅ 間違えても過去の状態に戻せる
```

---

## Gitコマンド 具体例で解説

### 🚀 最初の一回だけやること

#### リポジトリを新規作成する
```bash
cd my-app          # プロジェクトフォルダに移動
git init           # Gitの管理を開始（.gitフォルダが作られる）
```

#### GitHubのリポジトリをローカルにコピーする
```bash
git clone https://github.com/username/my-app.git
# → my-app/ フォルダが作られ、中にコードが入る
```

---

### 📝 毎日使う基本の流れ

実際の開発は、この3ステップの繰り返しです。

```
① 変更する
② git add（ステージング）
③ git commit（保存）
```

#### ① 変更内容を確認する
```bash
git status
# 出力例：
# Changes not staged for commit:
#   modified:   index.html    ← 変更されたファイル
# Untracked files:
#   new-file.js               ← 新しく作ったファイル
```

#### ② 変更をステージングに追加する（`git add`）
```bash
git add index.html          # 特定のファイルだけ追加
git add .                   # すべての変更をまとめて追加
git add src/                # フォルダごと追加
```

> 💡 **ステージング** ＝「次のコミットに含めるもの」を選ぶ作業。  
> 写真を撮る前に「どれを写すか」選んでいるイメージ。

#### ③ コミットする（`git commit`）
```bash
git commit -m "ログイン機能を追加"
git commit -m "バグ修正: ボタンが押せない問題を解決"
git commit -m "README を日本語に更新"
```

> 💡 メッセージは **「何をしたか」** を一行で書くのが基本。

---

### 🌿 ブランチ操作

#### ブランチを作って移動する
```bash
git branch feature/login        # ブランチを作成
git checkout feature/login      # ブランチに移動

# ↑ 上の2行を1行でまとめた書き方（よく使う）
git checkout -b feature/login
```

#### 今いるブランチを確認する
```bash
git branch
# 出力例：
#   main
# * feature/login    ← * が今いるブランチ
```

#### ブランチを main に統合する（マージ）
```bash
git checkout main              # まず main に移動
git merge feature/login        # feature/login の変更を取り込む
```

---

### ☁️ GitHubとのやりとり

#### GitHubにアップロードする（`git push`）
```bash
git push origin main           # main ブランチをアップロード
git push origin feature/login  # 別ブランチをアップロード

# 初回だけ -u をつけると次回から git push だけでOKになる
git push -u origin main
```

#### GitHubから最新を取得する（`git pull`）
```bash
git pull                       # 現在のブランチの最新を取得
git pull origin main           # main の最新を取得
```

---

### ⏪ 困ったときのコマンド

#### 変更を取り消す（まだコミット前）
```bash
git restore index.html         # 特定ファイルの変更を取り消す
git restore .                  # すべての変更を取り消す（注意！）
```

#### 直前のコミットを修正する
```bash
git commit --amend -m "正しいメッセージに修正"
# ※ GitHubにpush済みのコミットは修正しないこと
```

#### 過去のコミット履歴を見る
```bash
git log                        # 詳細な履歴
git log --oneline              # 1行ずつシンプルに表示
# 出力例：
# a3f2c1b ログイン機能を追加
# 9d1e4a2 バグ修正: ボタンが押せない問題
# 3b8f0c5 最初のコミット
```

#### 特定のコミットに戻す
```bash
git checkout a3f2c1b           # そのコミット時点の状態を見る
git revert a3f2c1b             # そのコミットを打ち消す新しいコミットを作る（安全）
```

---

### 🔄 よくある開発の流れ（まとめ）

```bash
# 1. 作業ブランチを作る
git checkout -b feature/new-button

# 2. コードを編集する（エディタで作業）

# 3. 変更を確認
git status

# 4. ステージング & コミット
git add .
git commit -m "新しいボタンを追加"

# 5. GitHubにアップ
git push origin feature/new-button

# 6. GitHubでプルリクエストを作成 → レビュー → マージ
```

---

## 参考リンク

- [GitHub 公式サイト](https://github.com)
- [GitHub 公式ドキュメント（日本語）](https://docs.github.com/ja)
- [Git入門（サル先生のGit入門）](https://backlog.com/ja/git-tutorial/)
