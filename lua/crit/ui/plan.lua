local M = {}

function M.open(file)
  vim.notify("Crit plan review: " .. (file or "(no file)"))
end

return M
