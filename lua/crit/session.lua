local client = require("crit.client")
local config = require("crit.config")
local state = require("crit.state")
local code_ui = require("crit.ui.code")
local plan_ui = require("crit.ui.plan")
local status_ui = require("crit.ui.status")

local M = {
  client = nil,
  mode = nil,
}

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

function M.finish()
  if not M.client then
    error("No active Crit session", 0)
  end

  M.client:finish()
  status_ui.set("finished")
  return true
end

return M
