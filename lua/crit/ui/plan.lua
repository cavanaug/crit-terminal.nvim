local annotations = require("crit.annotations")
local config = require("crit.config")
local keymaps = require("crit.keymaps")
local state = require("crit.state")
local status = require("crit.ui.status")
local sync = require("crit.sync")

local M = {
  workspace = nil,
}

local function require_snacks()
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks or not snacks.layout or not snacks.win then
    error("crit-terminal.nvim plan UI requires snacks.nvim layout support", 0)
  end

  return snacks
end

local function set_scratch_lines(buf, lines)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function make_scratch(name, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = filetype
  vim.api.nvim_buf_set_name(buf, name)
  return buf
end

local function comment_range(comment)
  local start_line = comment.start_line or comment.line or comment.line_number
  local end_line = comment.end_line or start_line

  if not start_line then
    return "L?"
  end

  if end_line and end_line ~= start_line then
    return string.format("L%d-%d", start_line, end_line)
  end

  return string.format("L%d", start_line)
end

local function comment_body(comment)
  local body = comment.body or comment.text or ""
  body = body:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return body ~= "" and body or "(empty)"
end

local function render_comments(workspace)
  local lines = { "Comments", "" }
  workspace.comment_lines = {}

  if #state.comments == 0 then
    table.insert(lines, "No comments")
  else
    for _, comment in ipairs(state.comments) do
      table.insert(lines, string.format("%s — %s", comment_range(comment), comment_body(comment)))
      local start_line = annotations.line_range(comment)
      if start_line then
        workspace.comment_lines[#lines] = start_line
      end
    end
  end

  set_scratch_lines(workspace.comments_buf, lines)
end

local function jump_comment(workspace)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local target = workspace and workspace.comment_lines and workspace.comment_lines[line] or nil
  if not target or not (workspace and workspace.doc_win and workspace.doc_win:win_valid()) then
    return
  end

  workspace.doc_win:focus()
  local buf = vim.api.nvim_win_get_buf(0)
  local last_line = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(0, { math.min(target, last_line), 0 })
end

local function render_markdown(workspace)
  if not config.get().render_markdown or vim.fn.exists(":RenderMarkdown") ~= 2 then
    return
  end

  vim.schedule(function()
    if not (workspace and workspace.doc_win and workspace.doc_win:win_valid()) then
      return
    end

    local current = vim.api.nvim_get_current_win()
    workspace.doc_win:focus()
    pcall(vim.cmd, "silent RenderMarkdown")
    if vim.api.nvim_win_is_valid(current) then
      vim.api.nvim_set_current_win(current)
    end
  end)
end

local function close_workspace()
  local workspace = M.workspace
  if not workspace then
    return
  end

  sync.stop()
  annotations.clear(workspace.doc_buf)

  if workspace.layout and not workspace.layout.closed then
    workspace.layout:close()
  end

  M.workspace = nil
end

function M.close()
  close_workspace()
end

function M.refresh()
  local workspace = M.workspace
  if not workspace then
    return
  end

  render_comments(workspace)
  annotations.clear(workspace.doc_buf)
  annotations.apply(workspace.doc_buf, state.comments)
  status.render(workspace.status_buf)
end

function M.open(file)
  local Snacks = require_snacks()
  local crit_path = assert(file, "plan file is required")
  local path = vim.fn.fnamemodify(crit_path, ":p")
  state.local_path = path

  if M.workspace and M.workspace.layout and not M.workspace.layout.closed then
    close_workspace()
  end

  local doc_buf = vim.fn.bufadd(path)
  vim.fn.bufload(doc_buf)

  local comments_buf = make_scratch("crit://comments", "markdown")
  local status_buf = make_scratch("crit://status", "text")

  local workspace = {
    doc_buf = doc_buf,
    comments_buf = comments_buf,
    status_buf = status_buf,
  }

  workspace.doc_win = Snacks.win({
    buf = doc_buf,
    show = false,
    minimal = false,
    fixbuf = true,
    wo = {
      wrap = true,
    },
  })

  workspace.comments_win = Snacks.win({
    buf = comments_buf,
    show = false,
    fixbuf = true,
    wo = {
      wrap = true,
    },
  })

  workspace.status_win = Snacks.win({
    buf = status_buf,
    show = false,
    fixbuf = true,
    focusable = false,
    wo = {
      wrap = false,
      winbar = "",
    },
  })

  workspace.layout = Snacks.layout.new({
    show = false,
    wins = {
      document = workspace.doc_win,
      comments = workspace.comments_win,
      status = workspace.status_win,
    },
    layout = {
      position = "float",
      width = 0.9,
      height = 0.9,
      border = "rounded",
      title = " Crit Plan ",
      box = "vertical",
      {
        box = "horizontal",
        border = "none",
        { win = "document", width = 0.7, border = "none" },
        { win = "comments", width = 0.3, border = "left" },
      },
      { win = "status", height = 1, border = "top" },
    },
    on_close = function()
      sync.stop()
      annotations.clear(doc_buf)
      if M.workspace == workspace then
        M.workspace = nil
      end
    end,
  })

  M.workspace = workspace
  workspace.layout:show()
  if workspace.doc_win:win_valid() then
    workspace.doc_win:focus()
  end

  vim.keymap.set("n", "<CR>", function()
    jump_comment(workspace)
  end, {
    buffer = comments_buf,
    silent = true,
    desc = "Jump to Crit comment",
  })

  M.refresh()
  render_markdown(workspace)
  keymaps.bind_workspace()
  sync.start()

  return workspace
end

return M
