local navigation = require("crit.navigation")
local state = require("crit.state")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b))
  end
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
})

state.comments = {
  { start_line = 7, body = "later" },
  { line = 2, body = "first" },
  { start_line = 5, body = "middle" },
}

vim.api.nvim_win_set_cursor(0, { 1, 0 })
assert_eq(navigation.next_comment(), 2, "next first")
assert_eq(vim.api.nvim_win_get_cursor(0)[1], 2, "cursor on first")

assert_eq(navigation.next_comment(), 5, "next second")
assert_eq(vim.api.nvim_win_get_cursor(0)[1], 5, "cursor on second")

assert_eq(navigation.prev_comment(), 2, "prev comment")
assert_eq(vim.api.nvim_win_get_cursor(0)[1], 2, "cursor back on first")

vim.api.nvim_win_set_cursor(0, { 8, 0 })
assert_eq(navigation.next_comment(), nil, "no next comment")

print("test_navigation OK")
