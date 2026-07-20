local session = require("crit.session")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b))
  end
end

local status = session.parse_status_json([[{
  "daemon": { "running": true, "port": 44927, "pid": 1 },
  "review_file": "/tmp/x/review.json"
}]])
assert_eq(status.daemon.running, true)
assert_eq(session.base_url_from_status(status), "http://127.0.0.1:44927")

assert_eq(session.detect_mode({ path = "plan.md" }), "plan")
assert_eq(session.detect_mode({ path = "foo.go" }), "code")
assert_eq(session.detect_mode({ file = "x.md" }), "plan")

print("test_session OK")
