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
├── baton.gemspec                      # gem パッケージ定義
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
# ワークフロー実行 (Rails プロジェクト内で bundle exec)
bundle exec baton run -t "タスク内容"      # default.yaml を実行
bundle exec baton run -f plan.md           # プランファイルから実装開始
bundle exec baton run -f plan.md -t "タスク" # プランファイル + タスク指定
bundle exec baton run -p path/to/piece.yaml # カスタム piece ファイル指定
bundle exec baton run -d /path/to/project   # 別ディレクトリを対象に実行

# 情報表示
bundle exec baton list                     # 利用可能な piece 一覧
bundle exec baton providers                # 登録済みプロバイダー一覧
bundle exec baton version                  # バージョン表示
```

## テスト実行

```bash
/opt/rbenv/versions/3.3.6/bin/rspec spec/core_spec.rb
```

## デフォルトワークフロー (default.yaml)

```
plan (Claude, read-only, interactive)
  ├─ 人間がフィードバック → plan を再実行 (セッション継続)
  └─ 人間が空入力で承認 → implement

implement (Claude, edit)
  └─ [IMPLEMENT:0] complete → review

review (Codex, read-only)
  ├─ [REVIEW:0] approved → COMPLETE
  └─ [REVIEW:1] needs_fix → fix

fix (Claude, edit)
  └─ [FIX:0] complete → review (ループ)
```

plan ステップは `interactive: true` により、Claude の出力後に人間の確認を挟む。
フィードバックを入力すると Claude セッションを再開して修正、空入力で承認して implement へ進む。

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

## Interactive モード

Movement に `interactive: true` を設定すると、provider 実行後に人間の入力を待つ。

- **空入力** → 承認。最初のルールの `next` に遷移。
- **テキスト入力** → フィードバック。同じ movement をセッション継続で再実行。

ルールタグは interactive movement のプロンプトには注入されない（人間が遷移を決定するため）。

```yaml
movements:
  - name: plan
    provider: claude
    interactive: true   # ← これを追加
    rules:
      - condition: approved
        next: implement
```

## ルール評価の優先順位

非 interactive movement でのルール評価:

1. 正確なタグマッチ: `[TAG:N]` (例: `[REVIEW:0]`)
2. 汎用パターン: `[MOVEMENT:N]`
3. Fuzzy フォールバック: condition テキストの部分一致

## コーディング規約

- Ruby 3.2+
- `frozen_string_literal: true` 全ファイル
- `Struct.new(keyword_init: true)` でモデル定義
- テストは RSpec
