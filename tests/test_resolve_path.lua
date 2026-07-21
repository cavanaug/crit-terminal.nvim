local state = require("crit.state")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b))
  end
end

state.session = { cwd = "/tmp/crit-cwd" }
assert_eq(state.resolve_local_path("plan.md"), "/tmp/crit-cwd/plan.md")
assert_eq(state.resolve_local_path("/abs/plan.md"), "/abs/plan.md")
print("test_resolve_path OK")
