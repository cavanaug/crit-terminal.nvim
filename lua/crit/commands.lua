local M = {
  _setup_done = false,
}

local function ensure_setup()
  if require("crit.config").opts == nil then
    require("crit").setup()
  end
end

function M.setup()
  if M._setup_done then
    return
  end

  M._setup_done = true

  vim.api.nvim_create_user_command("CritReview", function(cmd)
    ensure_setup()
    require("crit").review({ file = cmd.args ~= "" and cmd.args or nil })
  end, { nargs = "?", complete = "file", desc = "Open Crit review workspace" })

  vim.api.nvim_create_user_command("CritComment", function(cmd)
    ensure_setup()
    require("crit.session").add_comment_on_selection({
      line1 = cmd.line1,
      line2 = cmd.line2,
    })
  end, { nargs = 0, range = true, desc = "Add Crit comment" })

  vim.api.nvim_create_user_command("CritFinish", function()
    ensure_setup()
    require("crit").finish()
  end, { nargs = 0, desc = "Finish Crit review" })

  vim.api.nvim_create_user_command("CritRefresh", function()
    ensure_setup()
    require("crit.session").refresh()
  end, { nargs = 0, desc = "Refresh Crit comments" })
end

return M
