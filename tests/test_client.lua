local client = require("crit.client")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b))
  end
end

local calls = {}
local session_attempts = 0

client._request = function(method, url, body)
  table.insert(calls, { method = method, url = url, body = body })

  if method == "GET" and url:find("/api/health", 1, true) then
    return 200, '{"status":"ok"}'
  end

  if method == "GET" and url:find("/api/session", 1, true) then
    session_attempts = session_attempts + 1
    if session_attempts == 1 then
      return 503, '{"error":"warming up"}'
    end
    return 200, '{"mode":"files","files":[{"path":"plan.md"}]}'
  end

  if method == "GET" and url:find("/api/files/list", 1, true) then
    return 200, '["plan.md"]'
  end

  if method == "GET" and url:find("/api/file/comments", 1, true) then
    return 200, '[{"id":"c_old","start_line":3,"end_line":4,"body":"old"}]'
  end

  if method == "POST" and url:find("/api/file/comments", 1, true) then
    return 200, '{"id":"c_abc","start_line":1,"end_line":2,"body":"hi"}'
  end

  if method == "PUT" and url:find("/api/comment/c_abc%?path=plan%.md", 1) then
    return 200, '{"id":"c_abc","start_line":1,"end_line":2,"body":"updated"}'
  end

  if method == "DELETE" and url:find("/api/comment/c_abc%?path=plan%.md", 1) then
    return 204, ""
  end

  if method == "POST" and url:find("/api/finish", 1, true) then
    return 200, '{"ok":true}'
  end

  return 500, '{"error":"unexpected"}'
end

local c = client.new("http://127.0.0.1:9/")
assert_eq(c.base_url, "http://127.0.0.1:9", "trim trailing slash")
assert_eq(c:health(), true, "health")

local ready = c:wait_ready({ attempts = 2, sleep_ms = 0 })
assert_eq(ready.mode, "files", "wait_ready.mode")

local session = c:session()
assert_eq(session.mode, "files", "session.mode")

local files = c:files()
assert_eq(files[1], "plan.md", "files[1]")
assert(calls[#calls].url:find("/api/files/list", 1, true), "files endpoint")

local comments = c:list_file_comments("docs/plan one.md")
assert_eq(comments[1].id, "c_old", "comments[1].id")
assert(calls[#calls].url:find("path=docs%%2Fplan%%20one%.md"), "encoded comments path")

local comment = c:add_file_comment("plan.md", 1, 2, "hi")
assert_eq(comment.id, "c_abc", "comment.id")
assert_eq(calls[#calls].method, "POST", "post method")
assert(calls[#calls].url:find("path=plan%.md"), "path query")
assert_eq(calls[#calls].body, vim.json.encode({
  start_line = 1,
  end_line = 2,
  body = "hi",
}), "comment body")

local updated = c:update_comment("plan.md", "c_abc", "updated")
assert_eq(updated.body, "updated", "updated.body")
assert_eq(calls[#calls].method, "PUT", "update method")
assert(calls[#calls].url:find("path=plan%.md"), "update path query")
assert_eq(calls[#calls].body, vim.json.encode({
  body = "updated",
}), "update body")

local deleted = c:delete_comment("plan.md", "c_abc")
assert_eq(deleted, true, "delete result")
assert_eq(calls[#calls].method, "DELETE", "delete method")
assert(calls[#calls].url:find("path=plan%.md"), "delete path query")

c:finish()
assert_eq(calls[#calls].method, "POST", "finish method")

client._request = function()
  return 500, '{"error":"boom"}'
end

local ok, err = pcall(function()
  c:health()
end)
assert_eq(ok, false, "health error")
assert(err:find("500", 1, true), "status in error")
assert(err:find("boom", 1, true), "body in error")

print("test_client OK")
