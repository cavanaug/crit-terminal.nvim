local M = {
  text = "",
}

function M.set(text)
  M.text = text or ""
  return M.text
end

function M.render(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { M.text })
  end

  return M.text
end

return M
