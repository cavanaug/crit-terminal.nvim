# crit-nvim

Native LazyVim frontend for [Crit](https://crit.md). Crit stays the source of truth.

## Install (LazyVim)

```lua
{
  "YOUR_GITHUB_USER/crit-nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {},
  keys = {
    { "<leader>ar", "<cmd>CritReview<cr>", desc = "Crit Review" },
  },
}
```

Requires `crit` on `PATH`.

## CLI

```bash
./scripts/crit-nvim path/to/plan.md
```

Starts Crit with `--no-open` (or reuses a running daemon), exports `CRIT_NVIM_BASE_URL`, and opens Neovim directly into the Crit review workspace.
