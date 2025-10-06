# Migration Plan: QuickSight Resource Manager

既存の `quicksight-resource-manager` から新しい構造への移行計画と実装ロードマップ

## 現在の構造分析

### 既存ファイル構成
```
quicksight-resource-manager/
├── quicksight_manager.sh     # メイン管理スクリプト
├── quicksight_lib.sh         # 共通ライブラリ
├── config.sh                 # 設定ファイル
├── analysis_manager.sh       # Analysis 作成・更新
├── dataset_manager.sh        # Dataset 作成・更新
└── unknown.sh               # 用途不明
```

### 機能分析

#### 1. quicksight_manager.sh
- **主要機能**: バックアップ、リスト表示、差分チェック
- **移行先**: `services/quicksight/src/core/manager.sh`

#### 2. quicksight_lib.sh  
- **主要機能**: 共通関数ライブラリ
- **移行先**: `services/quicksight/src/api/v1/` + 共通ライブラリに分散

#### 3. analysis_manager.sh
- **主要機能**: Analysis の CRUD 操作
- **移行先**: `services/quicksight/src/resources/analysis.sh`

#### 4. dataset_manager.sh
- **主要機能**: Dataset の CRUD 操作  
- **移行先**: `services/quicksight/src/resources/dataset.sh`

#### 5. config.sh
- **主要機能**: 設定管理
- **移行先**: 新しい設定管理システムに統合済み

## 移行戦略

### Phase 1: 基盤整備 ✅
- [x] 新しいディレクトリ構造作成
- [x] 共通ライブラリ実装
- [x] 設定管理システム構築

### Phase 2: Core 機能移行
1. **API抽象化レイヤー作成**
   - QuickSight API呼び出しの抽象化
   - エラーハンドリングの統一
   - レスポンス処理の標準化

2. **リソース管理機能の移行**
   - Analysis操作の移行
   - Dataset操作の移行
   - 権限管理の移行

3. **バックアップ機能の移行**
   - バックアップロジックの抽出
   - 復元機能の実装
   - 差分チェック機能の改善

### Phase 3: CLI統合
1. **統一CLIの実装**
   - コマンド体系の設計
   - 引数解析の統一
   - ヘルプシステムの実装

2. **互換性レイヤー**
   - 既存コマンドとの互換性維持
   - 段階的移行サポート

### Phase 4: テストと検証
1. **テストスイート作成**
   - ユニットテスト
   - 統合テスト
   - 回帰テスト

2. **パフォーマンス最適化**
   - 並列処理の実装
   - API呼び出し最適化

## 関数マッピング

### 共通関数の移行

| 既存関数 | 新しい場所 | 備考 |
|---------|------------|------|
| `validate_aws_auth()` | `lib/aws/auth.sh` | ✅ 移行済み |
| `log_*()` 系 | `lib/utils/logger.sh` | ✅ 移行済み |
| `json_*()` 系 | `lib/utils/json_parser.sh` | ✅ 移行済み |

### Analysis関連の移行

| 既存関数 | 新しい場所 | 移行状況 |
|---------|------------|----------|
| `extract_analysis_params()` | `src/resources/analysis.sh` | 📋 計画中 |
| `create_analysis()` | `src/resources/analysis.sh` | 📋 計画中 |
| `update_analysis()` | `src/resources/analysis.sh` | 📋 計画中 |
| `check_analysis_exists()` | `src/api/v1/analysis_api.sh` | 📋 計画中 |

### Dataset関連の移行

| 既存関数 | 新しい場所 | 移行状況 |
|---------|------------|----------|
| `extract_dataset_params()` | `src/resources/dataset.sh` | 📋 計画中 |
| `create_dataset()` | `src/resources/dataset.sh` | 📋 計画中 |
| `update_dataset()` | `src/resources/dataset.sh` | 📋 計画中 |
| `check_dataset_exists()` | `src/api/v1/dataset_api.sh` | 📋 計画中 |

## 互換性維持計画

### 1. コマンド互換性
```bash
# 既存コマンド
./quicksight_manager.sh backup-all

# 新しいコマンド  
./services/quicksight/bin/qs-manager backup --all

# 互換性レイヤー（移行期間中）
./quicksight_manager.sh backup-all  # → 新しいコマンドに転送
```

### 2. 設定ファイル互換性
- 既存の `config.sh` を読み込み可能
- 新しい設定形式への自動変換
- 移行ガイドの提供

### 3. 出力形式互換性
- 既存スクリプトの出力形式を維持
- 新機能は新しい出力形式で提供

## リスクと軽減策

### 1. 機能回帰リスク
**軽減策**: 
- 包括的なテストスイート
- 既存機能の動作確認
- 段階的移行

### 2. 設定移行リスク  
**軽減策**:
- 自動変換ツール
- バックアップ機能
- 検証スクリプト

### 3. ユーザー影響リスク
**軽減策**:
- 詳細な移行ドキュメント
- 互換性レイヤー
- 段階的廃止予定

## 次のステップ

1. **API バージョン管理システム実装**
2. **Core 機能の移行開始**  
3. **テストフレームワーク構築**
4. **CLI統合の実装**
5. **ドキュメント整備**

## タイムライン

- **Week 1-2**: API抽象化レイヤー
- **Week 3-4**: リソース管理機能移行
- **Week 5-6**: CLI統合
- **Week 7-8**: テストとドキュメント
