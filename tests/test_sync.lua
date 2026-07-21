local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b))
  end
end

do
  local state = {
    file = "plan.md",
    comments = {
      { id = "c1", body = "same" },
    },
  }
  function state.set_comments(comments)
    state.comments = comments
    return comments
  end
  local status_calls = {}
  local status = { text = "idle" }
  function status.set(text)
    status.text = text
    status_calls[#status_calls + 1] = text
    return text
  end
  local refreshes = 0
  local plan = {
    refresh = function()
      refreshes = refreshes + 1
    end,
  }
  local responses = {
    { comments = { { id = "c1", body = "same" } } },
    { comments = { { id = "c1", body = "changed" } } },
    "boom",
  }
  local session = {
    client = {
      list_file_comments = function(_, path)
        assert_eq(path, "plan.md", "sync path")
        local response = table.remove(responses, 1)
        if response == "boom" then
          error("boom")
        end
        return response
      end,
    },
  }
  local timer = {
    start = function(self, timeout, repeat_ms, cb)
      self.timeout = timeout
      self.repeat_ms = repeat_ms
      self.cb = cb
    end,
    stop = function(self)
      self.stopped = true
    end,
    close = function(self)
      self.closed = true
    end,
  }

  package.loaded["crit.config"] = {
    get = function()
      return { poll_ms = 1500 }
    end,
  }
  package.loaded["crit.state"] = state
  package.loaded["crit.session"] = session
  package.loaded["crit.ui.status"] = status
  package.loaded["crit.ui.plan"] = plan
  package.loaded["crit.sync"] = nil

  local orig_new_timer = vim.uv.new_timer
  local orig_schedule_wrap = vim.schedule_wrap
  vim.uv.new_timer = function()
    return timer
  end
  vim.schedule_wrap = function(fn)
    return fn
  end

  local sync = require("crit.sync")
  sync.start()
  assert_eq(timer.timeout, 1500, "poll interval")
  assert_eq(timer.repeat_ms, 1500, "repeat interval")

  timer.cb()
  assert_eq(status.text, "connected", "connected after success")
  assert_eq(refreshes, 1, "refresh on reconnect")
  assert_eq(state.comments[1].body, "same", "same comments unchanged")

  timer.cb()
  assert_eq(refreshes, 2, "refresh on comment change")
  assert_eq(state.comments[1].body, "changed", "changed comments stored")

  timer.cb()
  assert_eq(status.text, "disconnected", "disconnect status")
  assert_eq(refreshes, 3, "refresh on disconnect")
  assert_eq(status_calls[#status_calls], "disconnected", "last status")

  sync.stop()
  assert_eq(timer.stopped, true, "timer stopped")
  assert_eq(timer.closed, true, "timer closed")
  assert_eq(sync.timer, nil, "timer cleared")

  vim.uv.new_timer = orig_new_timer
  vim.schedule_wrap = orig_schedule_wrap
end

do
  local sync_calls = 0
  local finish_calls = 0
  local status = {}
  function status.set(text)
    status.text = text
    return text
  end
  local plan = {}
  function plan.close()
    plan.closed = (plan.closed or 0) + 1
  end

  package.loaded["crit.client"] = {}
  package.loaded["crit.annotations"] = {}
  package.loaded["crit.config"] = {
    get = function()
      return {}
    end,
  }
  package.loaded["crit.state"] = {}
  package.loaded["crit.ui.code"] = {}
  package.loaded["crit.ui.plan"] = plan
  package.loaded["crit.ui.status"] = status
  package.loaded["crit.sync"] = {
    stop = function()
      sync_calls = sync_calls + 1
    end,
  }
  package.loaded["crit.session"] = nil

  local session = require("crit.session")
  session.client = {
    finish = function()
      finish_calls = finish_calls + 1
    end,
  }

  assert_eq(session.finish(), true, "finish return")
  assert_eq(finish_calls, 1, "client finish called")
  assert_eq(sync_calls, 1, "sync stop called")
  assert_eq(status.text, "finished", "finish status")
  assert_eq(plan.closed, 1, "plan close called")
end

print("test_sync OK")
