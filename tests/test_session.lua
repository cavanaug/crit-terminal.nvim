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
assert_eq(session.mode_from_session({ mode = "files" }, { "plan.md" }), "plan")
assert_eq(session.mode_from_session({ mode = "files" }, { "docs/plan.md", "notes.md" }), "plan")
assert_eq(session.mode_from_session({ mode = "plan" }, { "main.lua" }), "plan")
assert_eq(session.mode_from_session({ mode = "files" }, { "main.lua" }), "code")

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

do
  local status_calls = 0
  local launched
  local orig_system = vim.system
  local orig_wait = vim.wait
  local orig_crit_on_path = session.crit_on_path
  local orig_status = session.status

  session.crit_on_path = function()
    return true
  end
  session.status = function()
    status_calls = status_calls + 1
    if status_calls == 1 then
      error("not running")
    end
    return {
      daemon = {
        running = true,
        port = 44927,
      },
    }
  end
  vim.system = function(args, opts)
    launched = {
      args = args,
      opts = opts,
    }
    return {
      wait = function()
        return { code = 0, stdout = "", stderr = "" }
      end,
    }
  end
  vim.wait = function()
    return true
  end

  local base_url, launched_new = session.ensure_daemon({
    file = "plan.md",
    status_attempts = 2,
    status_sleep_ms = 0,
  })

  assert_eq(base_url, "http://127.0.0.1:44927", "ensure_daemon base url")
  assert_eq(launched_new, true, "ensure_daemon launch flag")
  assert_eq(launched.args[1], "crit", "launch command")
  assert_eq(launched.args[2], "--no-open", "no-open flag")
  assert_eq(launched.args[3], "plan.md", "plan file")

  vim.system = orig_system
  vim.wait = orig_wait
  session.crit_on_path = orig_crit_on_path
  session.status = orig_status
end

print("test_session OK")
