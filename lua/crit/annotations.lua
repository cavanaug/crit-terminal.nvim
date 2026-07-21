local M = {
  ns = vim.api.nvim_create_namespace("crit_comments"),
  sign_group = "crit_comments",
}

vim.fn.sign_define("CritComment", { text = "┃", texthl = "DiagnosticInfo" })

function M.virt_text_for(comment)
  local body = (comment.body or ""):gsub("\n.*", "")
  return "💬 " .. body
end

function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  vim.fn.sign_unplace(M.sign_group, { buffer = buf })
end

---@param buf integer
---@param comments table[]
function M.apply(buf, comments)
  M.clear(buf)
  for _, c in ipairs(comments or {}) do
    local line = math.max(0, (c.start_line or 1) - 1)
    vim.fn.sign_place(0, M.sign_group, "CritComment", buf, { lnum = line + 1 })
    vim.api.nvim_buf_set_extmark(buf, M.ns, line, 0, {
      virt_text = { { M.virt_text_for(c), "Comment" } },
      virt_text_pos = "eol",
    })
  end
end

return M
