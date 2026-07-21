# crit-terminal.nvim

Native LazyVim frontend for [Crit](https://crit.md). Crit stays the source of truth.

## Install (LazyVim)

```lua
{
  "cavanaug/crit-terminal.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {},
  keys = {
    { "<leader>r", "<cmd>CritReview<cr>", desc = "Crit Review" },
  },
}
```

Requires `crit` on `PATH`. Lua module remains `require("crit")`.

## CLI

```bash
./scripts/crit-terminal path/to/plan.md
```

Starts Crit with `--no-open` (or reuses a running daemon), exports `CRIT_TERMINAL_BASE_URL`, and opens Neovim directly into the Crit review workspace.

## Smoke checklist

- [ ] `crit` on `PATH`; plugin + Snacks
- [ ] `./scripts/crit-terminal plan.md` opens plan workspace
- [ ] Visual select + `<leader>rc` creates comment
- [ ] Comment in Crit browser UI
- [ ] Browser comment appears in Neovim ~2s
- [ ] `<leader>rf` / `:CritFinish` writes artifact
- [ ] Without RenderMarkdown, plan still opens
