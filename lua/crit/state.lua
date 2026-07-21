local M = {
  comments = {},
  file = nil,
  files = {},
  local_path = nil,
  session = nil,
}

local function file_path(entry)
  if type(entry) == "string" then
    return entry
  end

  if type(entry) == "table" then
    return entry.path or entry.file
  end
end

local function collect_files(entries)
  local files = {}

  for _, entry in ipairs(entries or {}) do
    local path = file_path(entry)
    if path and path ~= "" then
      table.insert(files, path)
    end
  end

  return files
end

local function pick_file(files, prefer_file)
  if #files == 0 then
    return prefer_file
  end

  if prefer_file and prefer_file ~= "" then
    for _, path in ipairs(files) do
      if path == prefer_file or vim.endswith(prefer_file, "/" .. path) or vim.endswith(prefer_file, path) then
        return path
      end
    end
  end

  return files[1]
end

function M.resolve_local_path(crit_path)
  if not crit_path or crit_path == "" then
    return nil
  end

  if crit_path:sub(1, 1) == "/" then
    return crit_path
  end

  local cwd = M.session and M.session.cwd
  if type(cwd) == "string" and cwd ~= "" then
    return cwd:gsub("/+$", "") .. "/" .. crit_path
  end

  return vim.fn.fnamemodify(crit_path, ":p")
end

function M.set_comments(comments)
  M.comments = comments or {}
  return M.comments
end

function M.load_from_client(client, prefer_file)
  local session = client:session() or {}
  local files = collect_files(session.files)

  if #files == 0 then
    files = collect_files(client:files())
  end

  local file = pick_file(files, prefer_file)
  local raw_comments = file and client:list_file_comments(file) or {}
  local comments = raw_comments.comments or raw_comments

  M.session = session
  M.files = files
  M.file = file
  M.local_path = nil
  M.set_comments(comments)

  return {
    session = session,
    files = files,
    file = file,
    comments = M.comments,
  }
end

return M
