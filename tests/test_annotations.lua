local ann = require("crit.annotations")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b))
  end
end

local preview = ann.virt_text_for({ body = "Missing validation\nmore" })
assert_eq(preview, "💬 Missing validation")

local start_line, end_line = ann.line_range({ line_number = 7 })
assert_eq(start_line, 7, "line_range start")
assert_eq(end_line, 7, "line_range end")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
ann.apply(buf, {
  { body = "skip me" },
  { line = 3, body = "render me" },
})

local marks = vim.api.nvim_buf_get_extmarks(buf, ann.ns, 0, -1, { details = true })
assert_eq(#marks, 2, "sign and virtual text rendered once")
assert_eq(marks[1][2], 2, "sign line is zero-indexed line 3")
assert_eq(marks[2][2], 2, "virt text line is zero-indexed line 3")
assert_eq(marks[2][4].virt_text[1][1], "💬 render me", "annotation text")
print("test_annotations OK")
