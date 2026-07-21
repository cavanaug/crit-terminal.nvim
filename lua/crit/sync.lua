local config = require("crit.config")
local state = require("crit.state")

local M = {
  timer = nil,
}

local function comment_signature(comments)
  local parts = {}

  for _, comment in ipairs(comments or {}) do
    parts[#parts + 1] = table.concat({
      tostring(comment.id or ""),
      tostring(comment.body or comment.text or ""),
    }, ":")
  end

  return table.concat(parts, "|")
end

function M.start()
  M.stop()

  local poll_ms = config.get().poll_ms
  M.timer = vim.uv.new_timer()
  M.timer:start(poll_ms, poll_ms, vim.schedule_wrap(function()
    local session = require("crit.session")
    if not session.client or not state.file then
      return
    end

    local ok, raw_comments = pcall(session.client.list_file_comments, session.client, state.file)
    local status = require("crit.ui.status")
    local plan = require("crit.ui.plan")
    if not ok then
      status.set("disconnected")
      plan.refresh()
      return
    end

    local was_connected = status.text == "connected"
    local comments = raw_comments.comments or raw_comments or {}
    status.set("connected")

    if comment_signature(comments) ~= comment_signature(state.comments) then
      state.set_comments(comments)
      plan.refresh()
    elseif not was_connected then
      plan.refresh()
    end
  end))
end

function M.stop()
  if not M.timer then
    return
  end

  M.timer:stop()
  M.timer:close()
  M.timer = nil
end

return M
