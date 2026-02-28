# Baton

AI エージェントオーケストレーション CLI ツール。TAKT (https://github.com/nrslib/takt) の Ruby 簡易実装。

## 概要

YAML で定義したワークフロー（piece）に従い、Claude Code と Codex を CLI 子プロセスで呼び出して plan → implement → review のループを自動実行する。

## アーキテクチャ

```
bin/baton (CLI/Thor) → Engine::PieceEngine (メインループ)
                          ↓
                     Movement を順次実行
                          ↓
                     Providers::Registry → ClaudeProvider (claude -p)
                                         → CodexProvider  (codex exec)
                          ↓
                     RuleEvaluator ([MOVEMENT:N] タグ検知) → 次の movement へ
```

## ディレクトリ構成

```
baton/
├── CLAUDE.md                          # このファイル
├── Gemfile
├── bin/baton                          # CLI エントリポイント (Thor)
├── lib/baton.rb                       # メインローダー
├── lib/baton/
│   ├── models/
│   │   ├── types.rb                   # Movement, Rule, PieceConfig, PieceState, AgentResponse
│   │   └── piece_loader.rb            # YAML → PieceConfig パーサー
│   ├── providers/
│   │   ├── base.rb                    # Provider 基底クラス + Registry
│   │   ├── claude_provider.rb         # Claude Code CLI プロバイダー
│   │   └── codex_provider.rb          # Codex CLI プロバイダー
│   └── engine/
│       ├── piece_engine.rb            # メインループ・状態管理
│       ├── rule_evaluator.rb          # [MOVEMENT:N] タグ検知 + fuzzy fallback
│       ├── instruction_builder.rb     # {task}, {previous_response} テンプレ展開
│       └── logger.rb                  # Pastel カラー出力
├── config/
│   ├── pieces/default.yaml            # デフォルトワークフロー定義
│   ├── pieces/from-plan.yaml          # プランファイル指定時のワークフロー
│   └── personas/                      # planner.md, coder.md, reviewer.md
└── spec/
    ├── spec_helper.rb
    └── core_spec.rb                   # MockProvider 結合テスト
```

## コマンド

```bash
# ワークフロー実行
bin/baton run                        # default.yaml を実行
bin/baton run default -t "タスク内容"  # タスク指定で実行
bin/baton run -p path/to/piece.yaml   # カスタム piece ファイル指定
bin/baton run -f plan.md              # プランファイルから実装開始 (from-plan.yaml)
bin/baton run -f plan.md -t "タスク"   # プランファイル + タスク指定

# 情報表示
bin/baton list                       # 利用可能な piece 一覧
bin/baton providers                  # 登録済みプロバイダー一覧
bin/baton version                    # バージョン表示
```

## テスト実行

```bash
/opt/rbenv/versions/3.3.6/bin/rspec spec/core_spec.rb
```

## デフォルトワークフロー (default.yaml)

```
plan (Claude, read-only)
  └─ [PLAN:0] approved → implement

implement (Claude, edit)
  └─ [IMPLEMENT:0] complete → review

review (Codex, read-only)
  ├─ [REVIEW:0] approved → COMPLETE
  └─ [REVIEW:1] needs_fix → fix

fix (Claude, edit)
  └─ [FIX:0] complete → review (ループ)
```

## プランファイル実行 (from-plan.yaml)

```
implement (Claude, edit) ← {plan} にプランファイル内容を展開
  └─ [IMPLEMENT:0] complete → review

review (Codex, read-only)
  ├─ [REVIEW:0] approved → COMPLETE
  └─ [REVIEW:1] needs_fix → fix

fix (Claude, edit)
  └─ [FIX:0] complete → review (ループ)
```

テンプレートプレースホルダー: `{task}`, `{previous_response}`, `{plan}`

## ルール評価の優先順位

1. 正確なタグマッチ: `[TAG:N]` (例: `[REVIEW:0]`)
2. 汎用パターン: `[MOVEMENT:N]`
3. Fuzzy フォールバック: condition テキストの部分一致

## コーディング規約

- Ruby 3.2+
- `frozen_string_literal: true` 全ファイル
- `Struct.new(keyword_init: true)` でモデル定義
- テストは RSpec
