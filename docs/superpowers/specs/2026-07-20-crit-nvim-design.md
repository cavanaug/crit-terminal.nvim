# crit-nvim Design

Native LazyVim/Neovim frontend for [Crit](https://crit.md) (tomasz-tomczyk/crit). Crit remains the backend and source of truth; Neovim is an alternative review client that can coexist with the browser UI.

**Date:** 2026-07-20  
**Status:** Draft — pending user review before implementation plan  

**Repo:** Neovim plugin (`crit-nvim`) + small shell entrypoint

---

## Goals

### Primary (v1)

- Review **plan/markdown documents** in Neovim without a browser (priority path)
- Use **RenderMarkdown** (when installed) for plan reading UX
- Create line-range comments via visual selection + keymaps
- Show comments as **inline signs + virtual text** and in a **comments pane**
- Attach to a running Crit session or **launch Crit** when needed
- Finish review via Crit’s normal completion workflow (`POST /api/finish`)
- Stay compatible with existing Crit agent integrations (plugin never owns agent protocol)
- Allow browser and Neovim clients on the same session
- Ship a shell CLI `crit-nvim` that starts/finds Crit and opens Neovim into the workspace
- Live sync comments via Crit events (or short poll fallback)

### Secondary (same plugin, polish after plan path works)

- Multi-file **code/diff** review workspace (files list, working-tree buffers, optional diff toggle)
- Per-file reviewed status, richer threading UI, agent slash `/crit` helpers

### Non-goals

- Independent review system or comment database
- Generating review artifacts outside Crit
- Custom agent integrations / forking Crit’s protocol
- Required Telescope dependency
- Matching or replacing [kevindutra/crit](https://github.com/kevindutra/crit) (separate TUI product; same idea, different protocol)

---

## Decisions

| Topic | Choice |
|---|---|
| Architecture | Thin HTTP client + Snacks UI (Approach 1) |
| Packaging | LazyVim-first Neovim plugin + `crit-nvim` CLI |
| Session | Attach or launch Crit (`--no-open` when plugin owns the UI) |
| v1 priority | Plan/markdown mode first; code mode skeleton OK |
| Layout | Native Snacks panes (not Diffview-centric, not LazyGit-only) |
| Plan chrome | RenderMarkdown buffer + comments pane + status |
| Code chrome (later) | Files + working-tree buffer (+ `diff` toggle) + comments + status |
| Annotations | Both inline signs/virtual text **and** comments pane |
| Keymaps | `<leader>ar…` under LazyVim `+ai`; pane-local nav |
| Out of scope for writes | Direct `review.json` editing when daemon down (launch Crit instead) |

---

## Architecture

```text
crit-nvim (shell)          Neovim (LazyVim plugin)
       │                         │
       │  start/find Crit        │  Snacks workspace
       │  --no-open              │  plan | code mode
       ▼                         ▼
              Crit daemon (source of truth)
              HTTP /api/*  +  review artifacts
                       ▲
                       │
                 Browser UI (optional, coexists)
```

**Rules:**

1. Crit owns sessions, comments, finish/review files, and agent protocol.
2. The plugin is an HTTP client + Neovim UX only.
3. Two entrypoints share one core: `crit-nvim` (CLI) and `:CritReview` / `<leader>ar` (in-editor).
4. Modes share `client` + `state`; UI layouts differ.

---

## Components

| Module | Responsibility |
|---|---|
| `cli/crit-nvim` | Resolve cwd/file → start or find Crit → open `nvim` with workspace bootstrap |
| `session` | Discover base URL (`crit status --json`, session metadata); launch `crit plan <file>` or `crit` as needed; detect plan vs code mode |
| `client` | HTTP: health, comments CRUD, files list, finish; `/api/events` subscribe (poll fallback) |
| `state` | In-memory mirror of session for UI + annotations; never durable storage |
| `ui.plan` | Snacks: RenderMarkdown buffer \| comments \| status |
| `ui.code` | Snacks: files \| buffer (+ optional diff) \| comments \| status |
| `annotations` | Signs + extmarks/virtual text; re-anchor using Crit `anchor` when present |
| `commands` / `keymaps` | User commands + `<leader>ar…` + pane-local maps |

**Dependencies:**

- Required: Neovim (LazyVim target), Snacks, Crit CLI on `PATH`
- Optional: RenderMarkdown for plan buffers (plain markdown fallback)

**Not required:** Telescope, Diffview (may be used later as optional diff helper, not the review shell)

---

## Dual-mode UX

### Mode 1 — Plan / Markdown (v1 priority)

Optimized for **new, often unversioned** plan documents.

```text
┌─────────────────────────────────────────────┐
│ RenderMarkdown buffer (plan file)           │
│   … inline sign / virtual text …            │
│                      │ Comments pane        │
│                      │  L12 — …             │
├──────────────────────┴──────────────────────┤
│ Status · plan · N comments · session …      │
└─────────────────────────────────────────────┘
```

- Main surface is the real file buffer (Crit line numbers = on-disk lines).
- Comment pane lists all comments for glance + jump.
- No multi-file chrome required for single-plan reviews.

### Mode 2 — Code / Diff (later polish)

Optimized for **multi-file change review**.

```text
┌─────────────────────────────────────────────┐
│ Files · M foo.go · M bar.go                 │
├─────────────────┬───────────────────────────┤
│ Working-tree    │ Comments                  │
│ buffer (+diff)  │                           │
├─────────────────┴───────────────────────────┤
│ Status                                      │
└─────────────────────────────────────────────┘
```

- Default main pane: working-tree file (not diff-first), because Crit comments use file line numbers.
- Diff is a toggle, not the home screen.

---

## Data flow

### Start (CLI)

```text
crit-nvim [file?]
  → session: find Crit or launch
       plan file → crit plan --no-open …
       else → attach or crit --no-open …
  → nvim opens plugin workspace for detected mode
  → GET comments/files → state → annotations + panes
```

### Start (in-editor)

```text
:CritReview / <leader>ar
  → prefer current markdown buffer for plan mode
  → else attach to active session / launch
  → mount workspace
```

### Comment lifecycle

```text
visual range + <leader>arc
  → prompt body
  → POST /api/comments  (wait for success)
  → state → annotations + comments pane

edit/delete → PUT/DELETE /api/comment/{id} → reconcile
```

### Live sync

```text
/api/events (preferred) or short poll
  → state reconcile
  → refresh annotations + pane
```

Browser and Neovim both remain valid clients; Crit serializes truth.

### Finish

```text
<leader>arf / :CritFinish
  → POST /api/finish
  → Crit emits review artifact for the agent
  → status shows completed; workspace may close
```

The plugin never writes review JSON / `.review.md` itself.

---

## Keymaps

Global (LazyVim `+ai` namespace; avoids Sidekick: `aa as ad at af av ap ao`):

| Key | Action |
|---|---|
| `<leader>ar` | Open/focus Crit workspace (`:CritReview`) |
| `<leader>arc` | Create comment (normal/visual) |
| `<leader>are` | Edit comment under cursor |
| `<leader>arx` | Delete comment |
| `<leader>ard` | Toggle diff (code mode) |
| `<leader>arr` | Refresh / force sync |
| `<leader>arf` | Finish / send review |

Pane-local (Crit workspace only):

| Key | Action |
|---|---|
| `j` / `k` | Navigate lists |
| `<CR>` | Open file / jump to comment |
| `]r` / `[r` | Next / previous Crit comment |

**Explicitly avoided:** overriding `gc` (mini.comment), `gd`/`gD`/`gr` (LSP), `]c`/`[c` (gitsigns/treesitter).

Commands mirror keymaps: `:CritReview`, `:CritComment`, `:CritFinish`, etc.

---

## Crit API surface (client)

Consume existing Crit local HTTP API (exact shapes verified against installed Crit during implementation). Expected operations:

- Health / session: `/api/health`, session discovery via `crit status --json`
- Files: `/api/files/list`, `/api/file`, `/api/file/diff` (code mode)
- Comments: `/api/comments`, `/api/comment/{id}`, replies endpoints as needed
- Sync: `/api/events` (and/or wait-for-event)
- Complete: `/api/finish`

If an endpoint differs by Crit version, adapt the client — do not invent a parallel store.

---

## Error handling

| Situation | Behavior |
|---|---|
| Crit missing from `PATH` | Hard error with install hint; no half-open UI |
| Launch fails | Surface Crit stderr; do not enter broken workspace |
| Daemon dies mid-review | Status → disconnected; refresh retries; no silent local-only comments |
| Comment HTTP failure | Notify; keep selection; do not paint fake extmarks |
| Plan file unreadable | Abort with path |
| RenderMarkdown missing | Plain markdown buffer; full comment UX still works |
| Ambiguous sessions | Snacks select (cwd/file preference first) |

**Non-negotiable:** never imply a comment is saved until Crit accepts it.

---

## Testing

| Layer | Scope |
|---|---|
| Unit | `client` parsing/mapping with fixtures; `session` status JSON; `annotations` placement/anchor smoke |
| Manual smoke | `crit-nvim plan.md` → comment → visible in browser → finish → artifact exists |
| Deferred | Full Snacks layout headless tests |

Ship a small assert-style test entry and a README smoke checklist.

---

## Repository shape (intended)

```text
crit-nvim/
  lua/crit/
    init.lua
    client.lua
    session.lua
    state.lua
    annotations.lua
    ui/plan.lua
    ui/code.lua
    commands.lua
    keymaps.lua
  plugin/crit.lua          -- commands bootstrap
  scripts/crit-nvim        -- shell entrypoint
  tests/                   -- unit/smoke
  docs/superpowers/specs/  -- this design
  README.md
```

LazyVim install: standard lazy.nvim plugin spec; optional LazyVim “extra” later.

---

## Implementation phases (preview)

1. **Skeleton** — plugin load, config, session discover/launch, health check  
2. **Plan workspace** — Snacks layout, RenderMarkdown buffer, comments pane, status  
3. **Comments** — create/edit/delete via API; annotations; `<leader>ar…`  
4. **Live sync + finish** — events/poll; `:CritFinish`  
5. **CLI** — `crit-nvim` wrapper  
6. **Code mode** — files list + buffer/diff toggle (reuse client/annotations)

Detailed task breakdown follows in the implementation plan after spec sign-off.

---

## Open points for implementation (not design blockers)

- Exact Crit JSON schemas per endpoint (probe against Crit 0.18+ during phase 1)
- Event stream vs poll interval defaults
- Whether `crit plan` CLI flags differ from code `crit` for `--no-open` / session reuse
