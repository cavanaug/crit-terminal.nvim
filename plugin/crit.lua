-- plugin/crit.lua
if vim.g.loaded_crit then
  return
end
vim.g.loaded_crit = true
require("crit").setup()
