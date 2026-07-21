local client = require("crit.client")
local annotations = require("crit.annotations")
local config = require("crit.config")
local state = require("crit.state")
local code_ui = require("crit.ui.code")
local plan_ui = require("crit.ui.plan")
local status_ui = require("crit.ui.status")
local sync = require("crit.sync")

local M = {
  client = nil,
  mode = nil,
}

local function notify_err(err)
  vim.notify(tostring(err), vim.log.levels.ERROR)
end

local function is_markdown(path)
  return type(path) == "string" and path:lower():sub(-3) == ".md"
end

local function current_markdown_buffer()
  local path = vim.api.nvim_buf_get_name(0)
  if is_markdown(path) then
    return path
  end
end

function M.parse_status_json(body)
  local ok, decoded = pcall(vim.json.decode, body)
  if not ok then
    error("Crit status JSON decode failed: " .. decoded, 0)
  end

  return decoded
end

function M.base_url_from_status(raw_status)
  local daemon = raw_status and raw_status.daemon or nil
  if daemon and daemon.running and daemon.port then
    return "http://127.0.0.1:" .. daemon.port
  end
end

function M.detect_mode(opts)
  opts = opts or {}
  return is_markdown(opts.path or opts.file) and "plan" or "code"
end

function M.crit_on_path()
  return vim.fn.executable("crit") == 1
end

local function crit_missing_error()
  error("Crit CLI not found on PATH; install from https://crit.md", 0)
end

local function active_review()
  if not M.client then
    error("No active Crit session", 0)
  end

  if not state.file or state.file == "" then
    error("No active Crit file", 0)
  end

  return M.client, state.file
end

local function same_file(current, target)
  return current == target
    or vim.endswith(current, "/" .. target)
    or vim.endswith(target, "/" .. current)
end

local function current_comment_file()
  local path = state.file
  if not path or path == "" then
    return nil
  end

  local current = vim.api.nvim_buf_get_name(0)
  if current == "" or same_file(current, path) then
    return path
  end

  return nil
end

local function selection_range(opts)
  if opts and opts.line1 and opts.line2 then
    return math.min(opts.line1, opts.line2), math.max(opts.line1, opts.line2)
  end

  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    local start_line = vim.fn.line("v")
    local end_line = vim.fn.line(".")
    return math.min(start_line, end_line), math.max(start_line, end_line)
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  return line, line
end

function M.status()
  if not M.crit_on_path() then
    crit_missing_error()
  end

  local result = vim.system({ "crit", "status", "--json" }, { text = true }):wait()
  if result.code ~= 0 then
    error("Crit status failed: " .. ((result.stderr ~= "" and result.stderr) or result.stdout or ""), 0)
  end

  return M.parse_status_json(result.stdout or "")
end

local function launch_crit(file)
  local args = { "crit", "--no-open" }
  if file then
    table.insert(args, file)
  end

  local result = vim.system(args, { text = true }):wait()
  if result.code ~= 0 then
    error("Crit launch failed: " .. ((result.stderr ~= "" and result.stderr) or result.stdout or ""), 0)
  end
end

function M.ensure_daemon(opts)
  opts = opts or {}

  local base_url = opts.base_url or config.get().base_url
  if base_url and base_url ~= "" then
    return base_url
  end

  if not M.crit_on_path() then
    crit_missing_error()
  end

  local ok, raw_status = pcall(M.status)
  if ok then
    local status_base_url = M.base_url_from_status(raw_status)
    if status_base_url then
      return status_base_url
    end
  end

  launch_crit(opts.file or opts.path)

  for _ = 1, (opts.status_attempts or 40) do
    ok, raw_status = pcall(M.status)
    if ok then
      local status_base_url = M.base_url_from_status(raw_status)
      if status_base_url then
        return status_base_url
      end
    end
    vim.wait(opts.status_sleep_ms or 250)
  end

  error("Crit daemon did not become ready", 0)
end

function M.review(opts)
  opts = opts or {}

  local file = opts.file or opts.path or current_markdown_buffer()
  local mode = M.detect_mode({ file = file })
  local base_url = M.ensure_daemon(vim.tbl_extend("force", opts, { file = file }))
  local crit_client = client.new(base_url)

  crit_client:wait_ready()

  M.client = crit_client
  M.mode = mode

  local loaded = state.load_from_client(crit_client, file)
  status_ui.set("connected")

  if mode == "plan" then
    plan_ui.open(loaded.file or file)
  else
    code_ui.open()
  end

  return loaded
end

function M.refresh()
  local crit_client, path = active_review()
  local loaded = state.load_from_client(crit_client, path)
  plan_ui.refresh()
  return loaded
end

function M.add_comment_on_selection(opts)
  local start_line, end_line = selection_range(opts)
  local ok, crit_client, path = pcall(active_review)
  if not ok then
    notify_err(crit_client)
    return
  end

  vim.ui.input({ prompt = "Review Comment: " }, function(body)
    if body == nil or body == "" then
      return
    end

    local comment_ok, err = pcall(function()
      crit_client:add_file_comment(path, start_line, end_line, body)
      M.refresh()
    end)

    if not comment_ok then
      notify_err(err)
    end
  end)
end

function M.comment_at_cursor()
  local path = current_comment_file()
  if not path then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, comment in ipairs(state.comments or {}) do
    local start_line, end_line = annotations.line_range(comment)
    if start_line and line >= start_line and line <= end_line then
      return path, comment
    end
  end

  return path, nil
end

function M.delete_comment_at_cursor()
  local ok, err = pcall(function()
    local crit_client, path = active_review()
    local _, comment = M.comment_at_cursor()
    if not comment or not comment.id then
      error("No Crit comment at cursor", 0)
    end

    crit_client:delete_comment(path, comment.id)
    M.refresh()
  end)

  if not ok then
    notify_err(err)
  end
end

function M.edit_comment_at_cursor()
  local path, comment = M.comment_at_cursor()
  if not path or not comment or not comment.id then
    notify_err("No Crit comment at cursor")
    return
  end

  local crit_client = M.client
  if not crit_client then
    notify_err("No active Crit session")
    return
  end

  vim.ui.input({ prompt = "Review Comment: ", default = comment.body or "" }, function(body)
    if body == nil or body == "" then
      return
    end

    local ok, err = pcall(function()
      crit_client:update_comment(path, comment.id, body)
      M.refresh()
    end)

    if not ok then
      notify_err(err)
    end
  end)
end

function M.finish()
  if not M.client then
    error("No active Crit session", 0)
  end

  M.client:finish()
  sync.stop()
  status_ui.set("finished")
  if plan_ui.close then
    plan_ui.close()
  end
  return true
end

return M
