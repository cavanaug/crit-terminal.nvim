local annotations = require("crit.annotations")
local config = require("crit.config")
local keymaps = require("crit.keymaps")
local state = require("crit.state")
local status = require("crit.ui.status")
local sync = require("crit.sync")

local M = {
  workspace = nil,
}

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
  if not target or not (workspace and workspace.doc_win and vim.api.nvim_win_is_valid(workspace.doc_win)) then
    return
  end

  vim.api.nvim_set_current_win(workspace.doc_win)
  local buf = vim.api.nvim_win_get_buf(workspace.doc_win)
  local last_line = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(workspace.doc_win, { math.min(target, last_line), 0 })
end

local function configure_markdown(workspace)
  vim.schedule(function()
    if not (workspace and workspace.doc_win and vim.api.nvim_win_is_valid(workspace.doc_win)) then
      return
    end

    local current = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(workspace.doc_win)
    if config.get().render_markdown and vim.fn.exists(":RenderMarkdown") == 2 then
      pcall(vim.cmd, "silent RenderMarkdown")
    elseif vim.fn.exists(":RenderMarkdown") == 2 then
      -- LazyVim often auto-attaches; disable so holding j stays responsive.
      pcall(vim.cmd, "silent RenderMarkdown buf_disable")
    end
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
  if workspace.doc_buf and vim.api.nvim_buf_is_valid(workspace.doc_buf) then
    annotations.clear(workspace.doc_buf)
  end

  -- Collapse back to the document in this tab.
  if workspace.doc_win and vim.api.nvim_win_is_valid(workspace.doc_win) then
    vim.api.nvim_set_current_win(workspace.doc_win)
    pcall(vim.cmd, "only")
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
  local crit_path = assert(file, "plan file is required")
  local path = state.resolve_local_path(crit_path)
  if not path or path == "" or vim.fn.filereadable(path) == 0 then
    error("Crit plan file not readable: " .. tostring(crit_path) .. " (resolved: " .. tostring(path) .. ")", 0)
  end
  state.local_path = path

  if M.workspace then
    close_workspace()
  end

  -- Take over the current tab with real splits (no float over an empty buffer).
  vim.cmd("only")
  vim.cmd.edit(vim.fn.fnameescape(path))
  local doc_win = vim.api.nvim_get_current_win()
  local doc_buf = vim.api.nvim_get_current_buf()

  -- Keep comments pane as text so render-markdown does not attach/redraw it.
  local comments_buf = make_scratch("crit://comments", "text")
  local status_buf = make_scratch("crit://status", "text")

  vim.cmd("botright vsplit")
  local comments_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(comments_win, comments_buf)

  vim.api.nvim_set_current_win(doc_win)
  vim.cmd("botright split")
  local status_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(status_win, status_buf)
  vim.api.nvim_win_set_height(status_win, 1)
  vim.wo[status_win].winfixheight = true
  vim.wo[status_win].statusline = " "
  vim.wo[status_win].number = false
  vim.wo[status_win].relativenumber = false
  vim.wo[status_win].signcolumn = "no"
  vim.wo[status_win].cursorline = false

  -- Size comments after the status split so equalize doesn't leave a 50/50 layout.
  local comments_width = math.max(24, math.floor(vim.o.columns / 3))
  vim.api.nvim_win_set_width(comments_win, comments_width)
  vim.api.nvim_set_option_value("winfixwidth", true, { win = comments_win })

  vim.api.nvim_set_current_win(doc_win)

  local workspace = {
    doc_buf = doc_buf,
    doc_win = doc_win,
    comments_buf = comments_buf,
    comments_win = comments_win,
    status_buf = status_buf,
    status_win = status_win,
  }

  M.workspace = workspace

  vim.keymap.set("n", "<CR>", function()
    jump_comment(workspace)
  end, {
    buffer = comments_buf,
    silent = true,
    desc = "Jump to Crit comment",
  })

  vim.keymap.set("n", "q", function()
    M.close()
  end, {
    buffer = comments_buf,
    silent = true,
    desc = "Close Crit review",
  })

  M.refresh()
  configure_markdown(workspace)
  keymaps.bind_workspace()
  sync.start()

  return workspace
end

return M
