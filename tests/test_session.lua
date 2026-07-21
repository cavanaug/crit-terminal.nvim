local session = require("crit.session")
local state = require("crit.state")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b))
  end
end

local status = session.parse_status_json([[{
  "daemon": { "running": true, "port": 44927, "pid": 1 },
  "review_file": "/tmp/x/review.json"
}]])
assert_eq(status.daemon.running, true)
assert_eq(session.base_url_from_status(status), "http://127.0.0.1:44927")

assert_eq(session.detect_mode({ path = "plan.md" }), "plan")
assert_eq(session.detect_mode({ path = "foo.go" }), "code")
assert_eq(session.detect_mode({ file = "x.md" }), "plan")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/plan.md")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "1",
  "2",
  "3",
  "4",
  "5",
})

state.file = "plan.md"
state.comments = {
  { id = "c_one", start_line = 2, end_line = 3, body = "one" },
  { id = "c_two", line_number = 5, body = "two" },
}

vim.api.nvim_win_set_cursor(0, { 3, 0 })
local path, comment = session.comment_at_cursor()
assert_eq(path, "plan.md", "comment path")
assert_eq(comment.id, "c_one", "comment range match")

vim.api.nvim_win_set_cursor(0, { 5, 0 })
path, comment = session.comment_at_cursor()
assert_eq(path, "plan.md", "legacy comment path")
assert_eq(comment.id, "c_two", "legacy comment match")

vim.api.nvim_win_set_cursor(0, { 4, 0 })
path, comment = session.comment_at_cursor()
assert_eq(path, "plan.md", "no comment path")
assert_eq(comment, nil, "no comment match")

print("test_session OK")
