# CLAUDE.md

ISE Report (情報科学演習) 進捗管理リポジトリ。学生のレポート進捗を自動収集・可視化するダッシュボードシステム。

## システム概要

このリポジトリは、情報科学演習II のレポート進捗を追跡するためのダッシュボードを提供する。

### 主な機能

1. **進捗データ収集**: 学生リポジトリから index.html のサイズ・更新日時を自動収集
2. **可視化**: README.md に進捗表とグラフを自動生成
3. **履歴管理**: 日次スナップショットを archive/ に保存

## ディレクトリ構造

```
ise-report/
├── .github/workflows/
│   └── update-progress.yml    # 日次自動更新ワークフロー
├── scripts/
│   ├── collect-progress.sh    # 進捗データ収集
│   ├── generate-tables.sh     # テーブル・グラフ生成
│   ├── extract-previous-data.py  # 前日データ抽出
│   └── create-auto-update-pr.sh  # 自動PR作成
├── 2024/
│   └── students.csv           # 対象学生リスト
├── archive/
│   ├── snapshots/             # 日次スナップショット
│   └── data/                  # CSV形式の進捗データ
├── README.md                  # 進捗ダッシュボード（自動生成）
└── CLAUDE.md                  # このファイル
```

## 学生リポジトリ

対象リポジトリは `k{学籍番号}-ise-report2` 形式:
- 例: `k23rs017-ise-report2`

### 追跡項目

- **ファイルサイズ**: `index.html` のバイト数
- **最終更新日時**: 最新コミットの日時
- **ドラフトブランチ**: 現在の作業ブランチ
- **PR状態**: Review中、承認済み等

## ワークフロー

### 日次更新 (update-progress.yml)

毎日 JST 5:19 に自動実行:

1. 学生リポジトリから進捗データを収集
2. README.md を再生成
3. スナップショットを作成
4. PRを作成して自動マージ

### 手動実行

GitHub Actions の "Run workflow" から手動実行可能。

## 必要な Secrets

- `WORKFLOW_PAT`: Classic Personal Access Token with `repo` scope
  - 学生リポジトリ（Private）へのアクセスに必要

## 学生リストの更新

`2024/students.csv` を編集:

```csv
student_id,name,repo_suffix
23RS017,伊藤 温人,ise-report2
```

- `student_id`: 学籍番号（大文字、kプレフィックスなし）
- `name`: 氏名
- `repo_suffix`: リポジトリ名のサフィックス

## 関連リポジトリ

- [ise-report-template](https://github.com/smkwlab/ise-report-template): レポートテンプレート
- [thesis-report](https://github.com/smkwlab/thesis-report): 卒論進捗管理（類似システム）
