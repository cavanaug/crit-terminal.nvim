-- lua/crit/config.lua
local M = {}

M.defaults = {
  ---@type string|nil override Crit base URL (e.g. http://127.0.0.1:44927)
  base_url = nil,
  --- Author string sent with comments (nil → Crit default / omit)
  author = nil,
  --- Poll interval ms for comment sync when SSE unavailable
  poll_ms = 1500,
  --- Prefer render-markdown when available
  render_markdown = true,
  --- Keymap prefix under which-key +ai
  leader = "<leader>ar",
}

M.opts = nil

function M.setup(opts)
  if M.opts and (not opts or vim.tbl_isempty(opts)) then
    return M.opts
  end
  M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.opts
end

function M.get()
  return M.opts or M.setup({})
end

return M
