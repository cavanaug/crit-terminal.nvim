local annotations = require("crit.annotations")
local state = require("crit.state")

local M = {}

local function comment_starts()
  local starts = {}

  for _, comment in ipairs(state.comments or {}) do
    local start_line = annotations.line_range(comment)
    if start_line then
      table.insert(starts, start_line)
    end
  end

  table.sort(starts)
  return starts
end

local function jump(predicate)
  local current = vim.api.nvim_win_get_cursor(0)[1]

  for _, line in ipairs(comment_starts()) do
    if predicate(line, current) then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return line
    end
  end
end

function M.next_comment()
  return jump(function(line, current)
    return line > current
  end)
end

function M.prev_comment()
  local current = vim.api.nvim_win_get_cursor(0)[1]
  local last

  for _, line in ipairs(comment_starts()) do
    if line >= current then
      break
    end
    last = line
  end

  if last then
    vim.api.nvim_win_set_cursor(0, { last, 0 })
  end

  return last
end

return M
