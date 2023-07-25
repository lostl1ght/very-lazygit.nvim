local api = vim.api

---@alias Scope "global"|"tabpage"

---@class Instance
---@field bufnr integer
---@field jobid integer
---@field last_path string?

---@class LazyGitConfig
---@field winscale float
---@field scope Scope

---@class LazyGit
---@field instances table<string|integer, Instance>
---@field config LazyGitConfig
local LazyGit = {
  instances = {
    global = {
      bufnr = -1,
      jobid = -1,
      last_path = nil,
    },
  },
  config = {
    winscale = 0.75,
    scope = 'global',
  },
}

---Debug print variables
---@param ... any
---@diagnostic disable-next-line
local function debug(...)
  local args = {}
  for _, v in ipairs(a) do
    table.insert(args, vim.inspect(v))
  end
  vim.notify(table.concat(args, ' '))
end

---@return integer
function LazyGit:get_bufnr()
  if self.config.scope == 'global' then
    return self.instances.global.bufnr
  end
end

---@param bufnr integer
function LazyGit:set_bufnr(bufnr)
  if self.config.scope == 'global' then
    self.instances.global.bufnr = bufnr
  end
end

---@return integer
function LazyGit:get_jobid()
  if self.config.scope == 'global' then
    return self.instances.global.jobid
  end
end

---@param jobid integer
function LazyGit:set_jobid(jobid)
  if self.config.scope == 'global' then
    self.instances.global.jobid = jobid
  end
end

---@return string?
function LazyGit:get_last_path()
  if self.config.scope == 'global' then
    return self.instances.global.last_path
  end
end

---Set last path
---@param path string
function LazyGit:set_last_path(path)
  if self.config.scope == 'global' then
    self.instances.global.last_path = path
  end
end

---Create buffer
function LazyGit:create_buffer()
  if self:get_bufnr() == -1 then
    local bufnr = api.nvim_create_buf(true, true)
    self:set_bufnr(bufnr)
    api.nvim_set_option_value('filetype', 'lazygit', { buf = bufnr })
    api.nvim_create_autocmd('TermLeave', {
      buffer = bufnr,
      callback = vim.schedule_wrap(function()
        local winid = vim.fn.bufwinid(bufnr)
        if api.nvim_win_is_valid(winid) then
          vim.defer_fn(function()
            api.nvim_win_set_cursor(winid, { 1, 0 })
          end, 20)
        end
      end),
    })
    api.nvim_create_autocmd('BufEnter', {
      buffer = bufnr,
      callback = function(args)
        vim.defer_fn(function()
          local winid = vim.fn.bufwinid(args.buf)
          api.nvim_win_set_cursor(winid, { 1, 0 })
          api.nvim_cmd({ cmd = 'startinsert' }, {})
        end, 20)
      end,
    })
    api.nvim_create_autocmd('BufWinEnter', {
      buffer = bufnr,
      callback = function(args)
        local win = vim.fn.bufwinid(args.buf)
        api.nvim_set_option_value('number', false, { scope = 'local', win = win })
        api.nvim_set_option_value('relativenumber', false, { scope = 'local', win = win })
      end,
    })
  end
end

---Create window
function LazyGit:create_window()
  local bufnr = self:get_bufnr()
  if vim.fn.bufwinid(bufnr) == -1 then
    api.nvim_cmd({ cmd = 'split', mods = { horizontal = true, split = 'belowright' } }, {})
    api.nvim_cmd({ cmd = 'wincmd', args = { 'J' } }, {})
    api.nvim_cmd({
      cmd = 'resize',
      args = { math.floor(vim.opt.lines:get() * self.config.winscale) },
    }, {})
    api.nvim_win_set_buf(0, bufnr)
  else
    api.nvim_set_current_win(vim.fn.bufwinid(bufnr))
  end
end

---Get root in git repo
---@param path string
---@return string?
function LazyGit.get_root(path)
  return vim.fs.dirname(vim.fs.find('.git', {
    path = vim.fs.normalize(path),
    upward = true,
    type = 'directory',
  })[1])
end

---Start Lazygit
---@param path string
function LazyGit:start_job(path)
  local jobid = self:get_jobid()
  if jobid == -1 then
    ---@diagnostic disable-next-line
    jobid = vim.fn.termopen('lazygit -p ' .. path, {
      on_exit = function()
        self:drop()
      end,
    })
    ---@diagnostic disable-next-line
    self:set_jobid(jobid)
    self:set_last_path(path)
  end
end

---Close window and buffer, reset parameters
function LazyGit:drop()
  local bufnr = self:get_bufnr()
  local winid = vim.fn.bufwinid(bufnr)
  if api.nvim_win_is_valid(winid) then
    api.nvim_win_close(winid, true)
  end
  if api.nvim_buf_is_loaded(bufnr) then
    api.nvim_set_option_value('bufhidden', 'wipe', { buf = bufnr })
    api.nvim_buf_delete(bufnr, { force = true })
  end
  self:set_bufnr(-1)
  self:set_jobid(-1)
end

---Open Lazygit
---@param path string
function LazyGit:open(path)
  self:create_buffer()
  self:create_window()
  self:start_job(path)
end

local M = {}

---Open Lazygit
---@param path string?
---@param use_last boolean?
function M.open(path, use_last)
  local gitdir = LazyGit.get_root(
    ---@diagnostic disable-next-line
    path
      or use_last ~= false and LazyGit:get_last_path()
      or (vim.uv.cwd or vim.loop.cwd)()
  )
  if not gitdir then
    vim.notify('not a git repo', vim.log.levels.ERROR, { title = 'Lazygit' })
    return
  end
  if gitdir ~= LazyGit:get_last_path() then
    LazyGit:drop()
    vim.wait(25, function()
      return false
    end)
  end
  LazyGit:open(gitdir)
end

---Configure plugin options
---@param opts LazyGitConfig?
function M.setup(opts)
  opts = opts or {}
  vim.validate({
    scope = {
      opts.scope,
      function(v)
        return v == nil or v == 'global' or v == 'tabpage'
      end,
      "'global' or 'tabpage'",
    },
    winscale = {
      opts.winscale,
      function(v)
        return v == nil or v >= 0 and v <= 1
      end,
      'value between 0 and 1',
    },
  })
  LazyGit.config = vim.tbl_extend('force', LazyGit.config, opts)
end

return M