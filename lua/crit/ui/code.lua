local annotations = require("crit.annotations")
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
    error("crit-terminal.nvim code UI requires snacks.nvim layout support", 0)
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

local function split_lines(text)
  if not text or text == "" then
    return { "(empty)" }
  end

  return vim.split(text, "\n", { plain = true })
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

local function active_client()
  local session = require("crit.session")
  if not session.client then
    error("No active Crit session", 0)
  end

  return session.client
end

local function set_doc_buf(workspace, buf)
  if not (workspace and workspace.doc_win and workspace.doc_win:win_valid()) then
    return
  end

  local current = vim.api.nvim_get_current_win()
  workspace.doc_win:focus()
  vim.api.nvim_win_set_buf(0, buf)
  if vim.api.nvim_win_is_valid(current) then
    vim.api.nvim_set_current_win(current)
  end
end

local function ensure_file_buf(workspace, path)
  local full_path = state.resolve_local_path(path)
  if not full_path or vim.fn.filereadable(full_path) == 0 then
    error("Crit file not readable: " .. tostring(path), 0)
  end
  local buf = vim.fn.bufadd(full_path)
  vim.fn.bufload(buf)
  state.local_path = full_path

  if workspace.file_buf and workspace.file_buf ~= buf and vim.api.nvim_buf_is_valid(workspace.file_buf) then
    annotations.clear(workspace.file_buf)
  end

  workspace.file_buf = buf
  return buf
end

local function diff_lines(path)
  local raw = active_client():file_diff(path)
  if raw == "" then
    return { "(empty diff)" }, "diff"
  end

  local ok, decoded = pcall(vim.json.decode, raw)
  if ok then
    return vim.split(vim.inspect(decoded), "\n", { plain = true }), "json"
  end

  return split_lines(raw), "diff"
end

local function render_files(workspace)
  local lines = {}
  workspace.file_lines = {}

  if #state.files == 0 then
    lines = { "No files" }
  else
    for idx, path in ipairs(state.files) do
      local current = path == state.file and "> " or "  "
      lines[idx] = current .. path
      workspace.file_lines[idx] = path
    end
  end

  set_scratch_lines(workspace.files_buf, lines)
end

local function render_comments(workspace)
  local lines = { "Comments", "" }
  workspace.comment_lines = {}

  if #state.comments == 0 then
    table.insert(lines, "No comments")
  else
    for _, comment in ipairs(state.comments) do
      table.insert(lines, string.format("%s - %s", comment_range(comment), comment_body(comment)))
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

local function render_document(workspace)
  if workspace.show_diff and state.file then
    if not workspace.diff_view or workspace.diff_view.path ~= state.file then
      local ok, lines, filetype = pcall(diff_lines, state.file)
      if not ok then
        workspace.show_diff = false
        workspace.diff_view = nil
        vim.notify(tostring(lines), vim.log.levels.ERROR)
      else
        workspace.diff_view = {
          path = state.file,
          lines = lines,
          filetype = filetype,
        }
      end
    end
  end

  if workspace.show_diff and workspace.diff_view then
    vim.bo[workspace.diff_buf].filetype = workspace.diff_view.filetype
    set_scratch_lines(workspace.diff_buf, workspace.diff_view.lines)
    if workspace.file_buf and vim.api.nvim_buf_is_valid(workspace.file_buf) then
      annotations.clear(workspace.file_buf)
    end
    set_doc_buf(workspace, workspace.diff_buf)
    return
  end

  if workspace.diff_buf and vim.api.nvim_buf_is_valid(workspace.diff_buf) then
    set_scratch_lines(workspace.diff_buf, { "Diff hidden" })
  end

  if not state.file then
    set_scratch_lines(workspace.empty_buf, { "No file selected" })
    set_doc_buf(workspace, workspace.empty_buf)
    return
  end

  local doc_buf = ensure_file_buf(workspace, state.file)
  set_doc_buf(workspace, doc_buf)
  annotations.clear(doc_buf)
  annotations.apply(doc_buf, state.comments)
end

local function focus_doc(workspace)
  if workspace and workspace.doc_win and workspace.doc_win:win_valid() then
    workspace.doc_win:focus()
  end
end

local function load_file(path)
  local workspace = M.workspace
  if not workspace or not path or path == "" then
    return
  end

  local ok, result = pcall(function()
    local client = active_client()
    local raw_comments = client:list_file_comments(path) or {}
    state.file = path
    state.set_comments(raw_comments.comments or raw_comments or {})
    workspace.show_diff = false
    workspace.diff_view = nil
  end)

  if not ok then
    vim.notify(tostring(result), vim.log.levels.ERROR)
    return
  end

  M.refresh()
  focus_doc(workspace)
end

local function current_file_under_cursor()
  local workspace = M.workspace
  if not workspace then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  return workspace.file_lines and workspace.file_lines[line] or nil
end

local function close_workspace()
  local workspace = M.workspace
  if not workspace then
    return
  end

  sync.stop()
  if workspace.file_buf and vim.api.nvim_buf_is_valid(workspace.file_buf) then
    annotations.clear(workspace.file_buf)
  end

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

  render_files(workspace)
  render_comments(workspace)
  render_document(workspace)
  status.render(workspace.status_buf)
end

function M.toggle_diff()
  local workspace = M.workspace
  if not workspace then
    vim.notify("Crit code workspace is not open", vim.log.levels.WARN)
    return
  end

  if not state.file or state.file == "" then
    vim.notify("No Crit file selected", vim.log.levels.WARN)
    return
  end

  local ok, err = pcall(function()
    workspace.show_diff = not workspace.show_diff
    if not workspace.show_diff then
      workspace.diff_view = nil
    end
  end)

  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
    return
  end

  M.refresh()
  focus_doc(workspace)
end

function M.open(file)
  local Snacks = require_snacks()
  local initial_file = file or state.file or state.files[1]

  if M.workspace and M.workspace.layout and not M.workspace.layout.closed then
    close_workspace()
  end

  -- Take over the current tab; avoid floating over an empty buffer.
  vim.cmd("only")

  local files_buf = make_scratch("crit://files", "text")
  local comments_buf = make_scratch("crit://comments", "markdown")
  local diff_buf = make_scratch("crit://diff", "text")
  local empty_buf = make_scratch("crit://document", "text")
  local status_buf = make_scratch("crit://status", "text")

  local workspace = {
    files_buf = files_buf,
    comments_buf = comments_buf,
    diff_buf = diff_buf,
    empty_buf = empty_buf,
    status_buf = status_buf,
    file_lines = {},
    diff_view = nil,
    show_diff = false,
  }

  workspace.files_win = Snacks.win({
    buf = files_buf,
    show = false,
    fixbuf = true,
    wo = {
      wrap = false,
      number = false,
      relativenumber = false,
      cursorline = true,
    },
  })

  workspace.doc_win = Snacks.win({
    buf = empty_buf,
    show = false,
    minimal = false,
    fixbuf = false,
    wo = {
      wrap = false,
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
    fullscreen = true,
    wins = {
      files = workspace.files_win,
      document = workspace.doc_win,
      comments = workspace.comments_win,
      status = workspace.status_win,
    },
    layout = {
      -- Full-editor layout (not a float over an empty buffer).
      width = 0,
      height = 0,
      border = "none",
      box = "vertical",
      {
        box = "horizontal",
        border = "none",
        { win = "files", width = 0.25, border = "none" },
        {
          box = "vertical",
          border = "left",
          { win = "document", height = 0.7, border = "none" },
          { win = "comments", height = 0.3, border = "top" },
        },
      },
      { win = "status", height = 1, border = "top" },
    },
    on_close = function()
      sync.stop()
      if workspace.file_buf and vim.api.nvim_buf_is_valid(workspace.file_buf) then
        annotations.clear(workspace.file_buf)
      end
      if M.workspace == workspace then
        M.workspace = nil
      end
    end,
  })

  M.workspace = workspace
  workspace.layout:show()
  M.refresh()

  vim.keymap.set("n", "<CR>", function()
    local path = current_file_under_cursor()
    if path then
      load_file(path)
    end
  end, {
    buffer = files_buf,
    silent = true,
    desc = "Open Crit file",
  })

  vim.keymap.set("n", "<CR>", function()
    jump_comment(workspace)
  end, {
    buffer = comments_buf,
    silent = true,
    desc = "Jump to Crit comment",
  })

  if initial_file then
    load_file(initial_file)
  else
    focus_doc(workspace)
  end

  keymaps.bind_workspace()
  sync.start()

  return workspace
end

return M
