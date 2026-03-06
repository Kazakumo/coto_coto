# CLAUDE.md

**このドキュメントについて**: CotoCotoプロジェクトの概要、アーキテクチャ、開発ワークフローのガイダンスです。

**役割**: プロジェクト全体の指針・参照書
**言語**: English（国際スタンダード）

**読み方**:
- プロジェクト全体の概要を知りたい → Project Overview、Architecture Overview
- 実装の具体的なコーディング規則を知りたい → AGENTS.md を参照
- 実装のテスト戦略・エラーハンドリング設計を知りたい → ARCHITECTURE_DECISIONS.md を参照
- GitHub Issue・Branch・PR のワークフローを知りたい → WORKFLOW.md を参照

---

## Project Overview

**CotoCoto** is an idea fermentation workspace (アイデア発酵ワークスペース) built with Phoenix LiveView. It enables users to organize ideas on an infinite canvas using absolute positioning, with real-time collaborative features and AI-assisted idea discovery.

The project combines digital speed with analog feel, inspired by Shigeru Takahashi's "The Art of Thinking Clearly" (思考の整理学) - focusing on the process of observing, letting ideas rest, and fermenting them.

Key technologies:
- **Backend**: Elixir/Phoenix 1.8 with LiveView for real-time UI
- **Frontend**: Tailwind CSS v4, esbuild
- **Database**: PostgreSQL with Ecto
- **Real-time**: Phoenix.PubSub and Phoenix.Presence for collaborative features
- **HTTP Client**: Req (included, do not use httpoison/tesla/httpc)

## Development Workflow

**GitHub Issue is the single source of truth (SSOT).**

All work must:
1. Start with a GitHub Issue (`gh issue create`)
2. Use branch naming: `feat/issue-<NUMBER>` or `fix/issue-<NUMBER>`
3. Reference the Issue number in commits and PRs
4. Update the Issue with progress comments
5. Close the Issue with `Closes #<NUMBER>` in the PR

See `.claude/WORKFLOW.md` for complete workflow documentation and GitHub CLI examples.

**Quick start**:
```bash
# Create a GitHub Issue
gh issue create --title "Feature name" --body "Description"

# View Issues
gh issue list

# Create branch and work
git switch -c feat/issue-<NUMBER>

# Update progress in Issue
gh issue comment <NUMBER> --body "Progress: ✅ Done"

# Merge with Issue reference
gh pr create --title "feat(issue-<NUMBER>): name" --body "Closes #<NUMBER>"
```

## Essential Commands

```bash
# Initial setup
mix setup                  # Install deps, setup DB, build assets

# Development
mix phx.server            # Start dev server (localhost:4000)
iex -S mix phx.server     # Start with IEx REPL

# Testing
mix test                  # Run all tests with DB setup
mix test test/path_to_test.exs  # Run single test file
mix test --failed         # Run only previously failed tests

# Code quality & linting
mix precommit             # Run full pre-commit: compile, format, test, unlock unused deps
mix format                # Format code according to .formatter.exs
mix compile --warnings-as-errors  # Catch errors early

# Database
mix ecto.create          # Create database
mix ecto.migrate          # Run pending migrations
mix ecto.gen.migration migration_name  # Generate new migration
mix ecto.reset            # Drop, recreate, and seed database
mix ecto.setup            # Create, migrate, and seed

# Assets
mix assets.build          # Build Tailwind + esbuild
mix assets.deploy         # Minified build for production
```

## Architecture Overview

### Directory Structure

```
lib/
├── coto_coto/              # Business logic, contexts, schemas
│   ├── application.ex      # OTP supervision tree
│   ├── repo.ex             # Ecto repository
│   └── ...
└── coto_coto_web/          # Web layer (LiveViews, controllers, components)
    ├── router.ex           # Route definitions
    ├── endpoint.ex         # Phoenix endpoint
    ├── components/         # Reusable view components
    │   ├── core_components.ex    # Shared UI components
    │   └── layouts.ex      # Layout templates
    └── ...

config/
├── config.exs             # Shared config
├── dev.exs                # Development-specific
├── test.exs               # Test-specific
├── prod.exs               # Production-specific
└── runtime.exs            # Runtime config (env vars)

assets/
├── js/app.js              # JS entry point
├── css/app.css            # CSS entry point (Tailwind v4)
└── vendor/                # Third-party assets

test/
├── support/               # Test helpers and fixtures
└── coto_coto_web/         # Web layer tests (LiveViews, controllers)
```

### Key Patterns & Architectural Decisions

**LiveView-First Design**: The application relies on LiveView for real-time interactivity rather than REST APIs. This keeps business logic and UI state synchronized without heavy JavaScript.

**OTP Supervision Tree**: The application uses standard OTP patterns via the supervision tree in `Application`. Currently initialized:
- `CotoCotoWeb.Telemetry` - metrics collection
- `CotoCoto.Repo` - database connection pool
- `Phoenix.PubSub` - pub/sub messaging for real-time features
- `CotoCotoWeb.Endpoint` - HTTP endpoint

For future stateful features (Z-index management with GenServer, card auto-fermentation timers), add children to the supervision tree here.

**Real-Time Synchronization**:
- Use `Phoenix.PubSub` for broadcasting state changes across clients
- Use `Phoenix.Presence` for tracking who is currently editing/viewing (needed for the "who is grabbing this card" highlighting)
- LiveView streams (`stream/3`) for efficient list rendering of large card collections

**Client-Side Interactivity**:
- JS hooks (colocated with `:type={Phoenix.LiveView.ColocatedHook}`) for drag-and-drop at 60fps
- Position confirmation sent to server after user stops dragging
- CSS animations for smooth transitions

## Code Style & Best Practices

This project follows strict guidelines documented in **AGENTS.md** - refer there for detailed rules on:
- Phoenix v1.8 patterns (layouts, forms, inputs, LiveView)
- Elixir conventions (immutability, pattern matching, guards)
- Ecto best practices (preloading, changesets, migrations)
- HEEx template rules (interpolation, class lists, conditionals)
- LiveView patterns (streams, hooks, event handling)
- Testing with Phoenix.LiveViewTest and LazyHTML

**Key principles from AGENTS.md**:
1. Always begin LiveView templates with `<Layouts.app flash={@flash} ...>`
2. Use `start_supervised!/1` for test processes (guarantees cleanup)
3. Replace deprecated `live_redirect`/`live_patch` with `<.link navigate={}/patch={}>`
4. Avoid LiveComponents unless absolutely necessary
5. Use `<.form>` with `to_form/2`, not changeset directly in templates
6. Always add unique DOM IDs to key elements for testing

## Development Workflow

### 1. Issue Preparation
1. **Create issue** on GitHub with requirements
2. **Attach test design** (in issue comments): test cases, edge cases, C1 100% target
3. **Attach error handling design** (in issue comments): error patterns (expected/abnormal/unexpected), handling rules

### 2. Implementation (TDD)
1. **Create feature branch**: `git switch -c feat/issue-<NUMBER>` or `fix/issue-<NUMBER>`
2. **Write tests first** (per ARCHITECTURE_DECISIONS.md test strategy)
3. **Develop incrementally**: Small, logical commits
4. **Run quality checks**: `mix precommit` before pushing

### 3. Testing Requirements
- **Test coverage**: C1 100% (Statement Coverage) - mandatory for task completion
- **Test categories**: Unit tests (ExUnit), Integration tests (LiveViewTest), System tests (Phase 2)
- **Test tools**: lazy_html for assertions, ex_machina for factories
- **Verification**: `mix test.coverage` must show 100%

### 4. Error Handling
- **Classify errors**: Expected (バリデーション) / Abnormal (バグ) / Unexpected (外部API)
- **Design first**: Document all error patterns in issue before implementing
- **Implement per spec**: Map errors to HTTP status, user messages, logging levels
- **Test errors**: Mock/stub external dependencies to trigger error paths

### 5. Commit & PR
- **Commit format**: `feat(issue-<NUMBER>): short description` (conventional commits)
- **PR references**: Include `Closes #<NUMBER>` in PR body
- **Merge checklist**:
  - [ ] Test design documented in issue
  - [ ] Error handling design documented in issue
  - [ ] All tests passing (0 failures)
  - [ ] C1 100% achieved
  - [ ] `mix precommit` passes (format, type check, tests)
  - [ ] Dialyzer type checking passes
  - [ ] Code review approved

## Configuration & Environment

**Runtime Configuration** (`config/runtime.exs`): Database URL, secrets, and other environment-dependent settings are read here at startup. Set via environment variables.

**Development**: `mix phx.server` automatically enables live reload and hot asset compilation.

**Testing**: Uses `Sandbox` mode (rollback after each test for isolation).

## Dependencies to Know

| Package | Purpose |
|---------|---------|
| `phoenix` | Web framework |
| `phoenix_live_view` | Real-time UI via WebSocket |
| `ecto_sql` + `postgrex` | Database abstraction & PostgreSQL adapter |
| `phoenix_html` | HTML helpers |
| `tailwind` + `esbuild` | Asset compilation |
| `req` | HTTP requests (use this, not httpoison) |
| `swoosh` | Email delivery |

## Collaborative Features Notes

Since CotoCoto is multi-user in real-time:

1. **Presence Tracking**: Use `Phoenix.Presence` to show who's currently viewing/editing. User color highlighting requires presence subscriptions on the canvas LiveView.
2. **PubSub Broadcasting**: When a user moves a card, broadcast the new position via `Phoenix.PubSub.broadcast/3` so all connected clients see it instantly.
3. **Z-Index State**: Currently managed per-canvas. Will eventually use a GenServer to maintain order (recent = top, important = top, old = bottom).
4. **Optimistic UI**: For drag-and-drop, update position client-side immediately, confirm to server when drag ends. This gives low-latency feel even on high-latency networks.

## Documentation Reference Guide

This project uses **4 key documents** to provide comprehensive guidance:

### 📄 CLAUDE.md（このファイル）
- **目的**: プロジェクト概要・アーキテクチャ・必須コマンド
- **用途**: 全体像を理解したいときに参照

### 📄 AGENTS.md
- **目的**: コーディング規則（Phoenix v1.8・Elixir・Ecto など）
- **用途**: 実装時のコーディングガイドラインが必要なときに参照
- **参照先**: `AGENTS.md` contains the authoritative rules for:
  - Phoenix v1.8 patterns (layouts, forms, inputs, LiveView)
  - Elixir conventions (immutability, pattern matching, guards)
  - Ecto best practices (preloading, changesets, migrations)
  - HEEx template rules (interpolation, class lists, conditionals)
  - LiveView patterns (streams, hooks, event handling)
  - Testing with Phoenix.LiveViewTest and LazyHTML
  - JavaScript hook patterns

### 📄 ARCHITECTURE_DECISIONS.md
- **目的**: アーキテクチャ決定・テスト戦略・エラーハンドリング設計
- **用途**: テスト設計・エラーハンドリング設計が必要なときに参照
- **参照先**: ARCHITECTURE_DECISIONS.md contains:
  - Architectural decisions (Phoenix.PubSub, GenServer, Nx.Serving など)
  - Test strategy and design (TDD process, test categories, coverage requirements - C1 100%)
  - Error handling design (expected/abnormal/unexpected classification)
  - Task completion requirements (merge checklist)

### 📄 WORKFLOW.md（.claude/WORKFLOW.md）
- **目的**: GitHub Issue・Branch・PR の実行ワークフロー
- **用途**: 開発プロセスの具体的な手順が必要なときに参照
- **言語**: 日本語
