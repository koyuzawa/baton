# Baton

AI エージェントオーケストレーション CLI ツール。
[TAKT](https://github.com/nrslib/takt) の Ruby 簡易実装。

YAML で定義したワークフロー（piece）に従い、Claude Code と Codex を CLI 子プロセスで呼び出して **plan → implement → review** のループを自動実行します。

## インストール

### Rails プロジェクトの Gemfile に追加

```ruby
gem "baton", github: "koyuzawa/baton"
```

```bash
bundle install
```

### スタンドアロン

```bash
git clone https://github.com/koyuzawa/baton.git
cd baton
bundle install
```

### 必要なもの

- Ruby 3.2+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- [OpenAI Codex CLI](https://github.com/openai/codex) (review ステップで使用)

## 使い方

### 基本（Rails プロジェクト内で実行）

```bash
# Rails プロジェクトのルートで実行（カレントディレクトリで agent が動作）
bundle exec baton run -t "ユーザー認証機能を追加"

# プランファイルから実装開始 (plan ステップをスキップ)
bundle exec baton run -f plan.md

# プランファイル + タスク指定
bundle exec baton run -f plan.md -t "JWT認証で実装して"

# カスタム piece ファイルを指定
bundle exec baton run -p my_workflow.yaml -t "タスク内容"

# 別ディレクトリのプロジェクトを対象に実行
bundle exec baton run -d /path/to/project -t "タスク内容"
```

### その他のコマンド

```bash
bin/baton list         # 利用可能な piece 一覧
bin/baton providers    # 登録済みプロバイダー一覧
bin/baton version      # バージョン表示
```

## ワークフロー

### デフォルト (`default.yaml`)

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

### プランファイル実行 (`from-plan.yaml`)

Claude Code の `/plan` 等で作成したプランファイルを `-f` で渡すと、plan ステップをスキップして直接実装に入ります。

```
implement (Claude, edit) ← {plan} にファイル内容を展開
  └─ [IMPLEMENT:0] complete → review

review (Codex, read-only)
  ├─ [REVIEW:0] approved → COMPLETE
  └─ [REVIEW:1] needs_fix → fix

fix (Claude, edit)
  └─ [FIX:0] complete → review (ループ)
```

## カスタムワークフロー

`config/pieces/` に YAML ファイルを追加することで独自のワークフローを定義できます。

```yaml
name: my-workflow
task: "{task}"
start: design

movements:
  - name: design
    provider: claude
    persona: config/personas/planner.md
    prompt: |
      Design the architecture for: {task}
    tools: "Read,Glob,Grep"
    sandbox: read-only
    max_turns: 15
    rules:
      - condition: approved
        next: implement

  - name: implement
    provider: claude
    persona: config/personas/coder.md
    prompt: |
      Implement: {previous_response}
    tools: "Read,Write,Edit,Glob,Grep,Bash"
    max_turns: 30
    rules:
      - condition: done
        next: __COMPLETE__
```

### テンプレートプレースホルダー

| プレースホルダー | 内容 |
|----------------|------|
| `{task}` | `-t` で指定したタスク説明 |
| `{previous_response}` | 前のステップの出力 |
| `{plan}` | `-f` で指定したプランファイルの内容 |

### ルール評価

Agent の出力から次のステップを決定します。優先順位:

1. **正確なタグマッチ** — `[REVIEW:0]`, `[PLAN:0]` など
2. **汎用パターン** — `[MOVEMENT:N]`
3. **Fuzzy フォールバック** — `condition` テキストの部分一致

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

### ディレクトリ構成

```
baton/
├── bin/baton                          # CLI エントリポイント
├── lib/baton.rb                       # メインローダー
├── lib/baton/
│   ├── models/
│   │   ├── types.rb                   # データモデル (Struct)
│   │   └── piece_loader.rb            # YAML パーサー
│   ├── providers/
│   │   ├── base.rb                    # Provider 基底 + Registry
│   │   ├── claude_provider.rb         # Claude Code CLI
│   │   └── codex_provider.rb          # Codex CLI
│   └── engine/
│       ├── piece_engine.rb            # メインループ
│       ├── rule_evaluator.rb          # ルール評価
│       ├── instruction_builder.rb     # テンプレート展開
│       └── logger.rb                  # カラー出力
├── config/
│   ├── pieces/                        # ワークフロー定義
│   └── personas/                      # Agent ペルソナ
└── spec/                              # テスト
```

## テスト

```bash
bundle exec rspec
```

## ライセンス

MIT
