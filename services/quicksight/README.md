# QuickSight Management Service

AWS QuickSight の分析とデータセットを管理するための統合ツールセットです。

## 機能

- **バックアップと復元**: 分析とデータセットの安全なバックアップ
- **差分チェック**: 設定変更の検出と比較
- **バッチ操作**: 複数リソースの一括処理
- **バージョン管理**: API バージョンの自動対応
- **環境管理**: 開発/ステージング/本番環境の分離

## ディレクトリ構造

```
services/quicksight/
├── README.md           # このファイル
├── bin/               # 実行可能スクリプト
│   ├── qs-manager     # メインCLI
│   ├── qs-backup      # バックアップ専用
│   ├── qs-restore     # 復元専用
│   └── qs-diff        # 差分チェック専用
├── src/               # ソースコード
│   ├── core/          # 核となる機能
│   │   ├── manager.sh # メイン管理機能
│   │   └── backup.sh  # バックアップ機能
│   ├── resources/     # リソース別実装
│   │   ├── analysis.sh
│   │   └── dataset.sh
│   └── api/           # API バージョン別実装
│       └── v1/        # 現在のAPI実装
├── config/            # サービス固有設定
├── tests/             # テストスイート
│   ├── unit/          # ユニットテスト
│   └── integration/   # 統合テスト
└── schemas/           # JSON スキーマ定義
```

## 使用方法

### 基本的な使い方

```bash
# 環境を指定してツールを初期化
export AWS_UTILITIES_ENV=dev
./bin/qs-manager --help

# 分析をバックアップ
./bin/qs-backup --type analysis --all

# データセットを復元
./bin/qs-restore --backup backup-20241004-140524 --type dataset

# 差分をチェック
./bin/qs-diff --source backup-A --target backup-B
```

### 設定

環境別の設定は以下のファイルで管理されます：

- `config/global.env` - グローバル設定
- `config/services/quicksight.env` - QuickSight 固有設定
- `config/environments/{env}.conf` - 環境別設定

### API バージョン

現在サポートされている API バージョン：

- **v1**: QuickSight API 2018-04-01 (stable)
- **v2**: 将来の API バージョン (計画中)

## 開発

### 新機能の追加

1. 適切なディレクトリに実装を追加
2. ユニットテストを作成
3. 統合テストを更新
4. ドキュメントを更新

### テスト実行

```bash
# ユニットテスト
./tests/run_unit_tests.sh

# 統合テスト
./tests/run_integration_tests.sh
```

## 移行ガイド

既存の `quicksight-resource-manager` からの移行については、[MIGRATION.md](MIGRATION.md) を参照してください。
