local M = {}

function M.get_root(path)
  return vim.fs.dirname(vim.fs.find('.git', {
    path = vim.fs.normalize(path),
    upward = true,
    type = 'directory',
  })[1])
end

return M
