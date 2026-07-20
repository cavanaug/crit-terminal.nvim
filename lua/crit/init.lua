-- lua/crit/init.lua
local M = {}

function M.setup(opts)
  require("crit.config").setup(opts or {})
  require("crit.commands").setup()
  require("crit.keymaps").setup()
end

--- Open or focus the Crit review workspace.
---@param opts? { file?: string, base_url?: string }
function M.review(opts)
  return require("crit.session").review(opts or {})
end

function M.finish()
  return require("crit.session").finish()
end

return M
