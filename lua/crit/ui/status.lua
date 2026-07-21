local M = {
  text = "",
}

local function mode_label(path)
  if type(path) == "string" and path:lower():sub(-3) == ".md" then
    return "plan"
  end

  return "code"
end

local function render_text()
  local state = require("crit.state")
  local text = M.text ~= "" and M.text or "idle"
  return string.format(" Crit · %s · %d comments · %s ", mode_label(state.file), #state.comments, text)
end

function M.set(text)
  M.text = text or ""
  return M.text
end

function M.render(buf)
  local line = render_text()

  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    vim.bo[buf].modifiable = false
  end

  return line
end

return M
