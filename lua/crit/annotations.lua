local M = {
  ns = vim.api.nvim_create_namespace("crit_comments"),
  sign_group = "crit_comments",
}

vim.fn.sign_define("CritComment", { text = "┃", texthl = "DiagnosticInfo" })

function M.line_range(comment)
  local start_line = comment and (comment.start_line or comment.line or comment.line_number)
  local end_line = comment and (comment.end_line or start_line)

  if not start_line then
    return nil
  end

  return start_line, end_line
end

function M.virt_text_for(comment)
  local body = (comment.body or ""):gsub("\n.*", "")
  return "💬 " .. body
end

function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  vim.fn.sign_unplace(M.sign_group, { buffer = buf })
end

local function anchor_text(anchor)
  if type(anchor) ~= "string" or anchor == "" then
    return nil
  end

  for line in anchor:gmatch("[^\r\n]+") do
    line = vim.trim(line)
    if line ~= "" then
      return line
    end
  end
end

local function anchor_line(buf, anchor)
  local text = anchor_text(anchor)
  if not text then
    return nil
  end

  for idx, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(text, 1, true) then
      return idx
    end
  end
end

---@param buf integer
---@param comments table[]
function M.apply(buf, comments)
  M.clear(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  for _, c in ipairs(comments or {}) do
    local start_line = anchor_line(buf, c.anchor) or M.line_range(c)
    if start_line then
      local line = math.max(0, start_line - 1)
      if line < line_count then
        vim.fn.sign_place(0, M.sign_group, "CritComment", buf, { lnum = line + 1 })
        vim.api.nvim_buf_set_extmark(buf, M.ns, line, 0, {
          virt_text = { { M.virt_text_for(c), "Comment" } },
          virt_text_pos = "eol",
        })
      end
    end
  end
end

return M
