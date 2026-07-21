local config = require("crit.config")
local state = require("crit.state")

local M = {
  timer = nil,
  inflight = false,
  last_signature = nil,
}

local function comment_signature(comments)
  local parts = {}

  for _, comment in ipairs(comments or {}) do
    parts[#parts + 1] = table.concat({
      tostring(comment.id or ""),
      tostring(comment.body or comment.text or ""),
      tostring(comment.start_line or comment.line or comment.line_number or ""),
      tostring(comment.end_line or comment.start_line or comment.line or comment.line_number or ""),
      tostring(comment.anchor or ""),
    }, ":")
  end

  return table.concat(parts, "|")
end

local function refresh_workspace()
  local session = require("crit.session")
  if session.mode == "code" then
    require("crit.ui.code").refresh()
  else
    require("crit.ui.plan").refresh()
  end
end

local function apply_poll_result(err, raw_comments)
  local status = require("crit.ui.status")
  if err then
    status.set("disconnected")
    refresh_workspace()
    return
  end

  local was_connected = status.text == "connected"
  local comments = raw_comments.comments or raw_comments or {}
  local signature = comment_signature(comments)
  status.set("connected")

  if signature ~= M.last_signature then
    M.last_signature = signature
    state.set_comments(comments)
    refresh_workspace()
  elseif not was_connected then
    refresh_workspace()
  end
end

function M.start()
  M.stop()

  local poll_ms = config.get().poll_ms
  M.last_signature = comment_signature(state.comments)
  M.timer = vim.uv.new_timer()
  M.timer:start(poll_ms, poll_ms, vim.schedule_wrap(function()
    local session = require("crit.session")
    if not session.client or not state.file or M.inflight then
      return
    end

    M.inflight = true
    local function done(err, raw_comments)
      M.inflight = false
      if not M.timer then
        return
      end
      apply_poll_result(err, raw_comments)
    end

    -- Prefer async so curl never blocks j/k scrolling on the UI thread.
    if session.client.list_file_comments_async then
      session.client:list_file_comments_async(state.file, done)
      return
    end

    local ok, raw_comments = pcall(session.client.list_file_comments, session.client, state.file)
    done(not ok and raw_comments or nil, ok and raw_comments or nil)
  end))
end

function M.stop()
  if not M.timer then
    M.inflight = false
    return
  end

  M.timer:stop()
  M.timer:close()
  M.timer = nil
  M.inflight = false
  M.last_signature = nil
end

return M
