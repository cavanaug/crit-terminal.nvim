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
