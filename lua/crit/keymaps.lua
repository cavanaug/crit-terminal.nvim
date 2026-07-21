local config = require("crit.config")
local navigation = require("crit.navigation")

local M = {
  leader = nil,
}

local function del_map(modes, lhs)
  for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do
    pcall(vim.keymap.del, mode, lhs)
  end
end

local function set_map(modes, lhs, rhs, desc)
  vim.keymap.set(modes, lhs, rhs, { silent = true, desc = desc })
end

local function register_which_key(leader)
  local ok, wk = pcall(require, "which-key")
  if not ok then
    return
  end

  if type(wk.add) == "function" then
    wk.add({
      { leader, group = "Crit Review" },
      { leader .. "c", desc = "Add Crit Comment" },
      { leader .. "e", desc = "Edit Crit Comment" },
      { leader .. "x", desc = "Delete Crit Comment" },
      { leader .. "r", desc = "Refresh Crit Comments" },
      { leader .. "f", desc = "Finish Crit Review" },
    })
    return
  end

  if type(wk.register) == "function" then
    wk.register({
      name = "Crit Review",
      c = "Add Crit Comment",
      e = "Edit Crit Comment",
      f = "Finish Crit Review",
      r = "Refresh Crit Comments",
      x = "Delete Crit Comment",
    }, { prefix = leader })
  end
end

function M.setup()
  local leader = config.get().leader or "<leader>ar"
  if M.leader and M.leader ~= leader then
    del_map("n", M.leader)
    del_map({ "n", "x" }, M.leader .. "c")
    del_map("n", M.leader .. "e")
    del_map("n", M.leader .. "x")
    del_map("n", M.leader .. "r")
    del_map("n", M.leader .. "f")
  elseif M.leader == leader then
    return
  end

  M.leader = leader

  set_map("n", leader, "<cmd>CritReview<cr>", "Open Crit Review")
  set_map({ "n", "x" }, leader .. "c", function()
    require("crit.session").add_comment_on_selection()
  end, "Add Crit Comment")
  set_map("n", leader .. "e", function()
    require("crit.session").edit_comment_at_cursor()
  end, "Edit Crit Comment")
  set_map("n", leader .. "x", function()
    require("crit.session").delete_comment_at_cursor()
  end, "Delete Crit Comment")
  set_map("n", leader .. "r", "<cmd>CritRefresh<cr>", "Refresh Crit Comments")
  set_map("n", leader .. "f", "<cmd>CritFinish<cr>", "Finish Crit Review")

  register_which_key(leader)
end

function M.bind_workspace()
  vim.keymap.set("n", "]r", navigation.next_comment, {
    buffer = 0,
    silent = true,
    desc = "Next Crit Comment",
  })
  vim.keymap.set("n", "[r", navigation.prev_comment, {
    buffer = 0,
    silent = true,
    desc = "Previous Crit Comment",
  })
end

return M
