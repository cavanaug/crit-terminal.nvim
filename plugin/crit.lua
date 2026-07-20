-- plugin/crit.lua
if vim.g.loaded_crit then
  return
end
vim.g.loaded_crit = true

vim.api.nvim_create_user_command("CritReview", function(cmd)
  if require("crit.config").opts == nil then
    require("crit").setup()
  end
  require("crit").review({ file = cmd.args ~= "" and cmd.args or nil })
end, { nargs = "?", complete = "file", desc = "Open Crit review workspace" })
