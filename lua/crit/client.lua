local M = {}

local Client = {}
Client.__index = Client

local function q(s)
  return (s:gsub("([^%w%-_%.%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function decode(body)
  if not body or body == "" then
    return nil
  end

  return vim.json.decode(body)
end

local function trim_base_url(base_url)
  return (base_url or ""):gsub("/+$", "")
end

local function request_error(method, url, status, body)
  error(string.format("Crit request failed: %s %s -> %d %s", method, url, status, body or ""), 0)
end

function M._request(method, url, body)
  local args = {
    "curl",
    "-sS",
    "-X",
    method,
    "-w",
    "\n%{http_code}",
    url,
  }

  if body then
    vim.list_extend(args, {
      "-H",
      "Content-Type: application/json",
      "--data",
      body,
    })
  end

  local result = vim.system(args, { text = true }):wait()
  if result.code ~= 0 then
    error(string.format("Crit request failed: %s %s -> %s", method, url, result.stderr or result.stdout or ""), 0)
  end

  local output = result.stdout or ""
  local response_body, status = output:match("^(.*)\n(%d%d%d)$")
  if not status then
    error(string.format("Crit request failed: %s %s -> missing status", method, url), 0)
  end

  return tonumber(status), response_body
end

function M.new(base_url)
  return setmetatable({
    base_url = trim_base_url(base_url),
  }, Client)
end

function Client:_url(path)
  return self.base_url .. path
end

function Client:_json_request(method, path, body)
  local url = self:_url(path)
  local status, response_body = M._request(method, url, body and vim.json.encode(body) or nil)
  if status < 200 or status >= 300 then
    request_error(method, url, status, response_body)
  end

  return decode(response_body)
end

function Client:health()
  local response = self:_json_request("GET", "/api/health")
  return response == nil or response.status == nil or response.status == "ok"
end

function Client:wait_ready(opts)
  opts = opts or {}
  local attempts = opts.attempts or 40
  local sleep_ms = opts.sleep_ms or 250

  for _ = 1, attempts do
    local url = self:_url("/api/session")
    local status, response_body = M._request("GET", url)
    if status == 503 then
      if sleep_ms > 0 then
        vim.wait(sleep_ms)
      end
    elseif status >= 200 and status < 300 then
      return decode(response_body)
    else
      request_error("GET", url, status, response_body)
    end
  end

  error("Crit request failed: GET " .. self:_url("/api/session") .. " -> timed out waiting for ready", 0)
end

function Client:session()
  return self:_json_request("GET", "/api/session")
end

function Client:files()
  return self:_json_request("GET", "/api/files/list") or {}
end

function Client:list_file_comments(path)
  return self:_json_request("GET", "/api/file/comments?path=" .. q(path)) or {}
end

function Client:add_file_comment(path, start_line, end_line, body)
  return self:_json_request("POST", "/api/file/comments?path=" .. q(path), {
    start_line = start_line,
    end_line = end_line,
    body = body,
  })
end

function Client:update_comment(path, comment_id, body)
  return self:_json_request("PUT", "/api/comment/" .. q(comment_id) .. "?path=" .. q(path), {
    body = body,
  })
end

function Client:delete_comment(path, comment_id)
  self:_json_request("DELETE", "/api/comment/" .. q(comment_id) .. "?path=" .. q(path))
  return true
end

function Client:finish()
  return self:_json_request("POST", "/api/finish")
end

return M
