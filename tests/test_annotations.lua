local ann = require("crit.annotations")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b))
  end
end

local preview = ann.virt_text_for({ body = "Missing validation\nmore" })
assert_eq(preview, "💬 Missing validation")
print("test_annotations OK")
