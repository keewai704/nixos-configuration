vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.undofile = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.timeoutlen = 400
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.scrolloff = 5
vim.opt.termguicolors = true

require("mini.ai").setup()
require("mini.comment").setup()
require("mini.completion").setup()
require("mini.diff").setup()
require("mini.files").setup()
require("mini.git").setup()
require("mini.pairs").setup()
require("mini.pick").setup()
require("mini.statusline").setup({ use_icons = false })
require("mini.surround").setup()
require("which-key").setup({ icons = { mappings = false } })
require("conform").setup()

vim.diagnostic.config({ severity_sort = true, underline = true, virtual_text = false })

local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
map("n", "<leader>ff", function()
  require("mini.pick").builtin.files()
end, { desc = "Find files" })
map("n", "<leader>fg", function()
  require("mini.pick").builtin.grep_live()
end, { desc = "Search file contents" })
map("n", "<leader>fb", function()
  require("mini.pick").builtin.buffers()
end, { desc = "Find buffers" })
map("n", "<leader>fh", function()
  require("mini.pick").builtin.help()
end, { desc = "Search help" })
map("n", "<leader>e", function()
  local path = vim.api.nvim_buf_get_name(0)
  require("mini.files").open(path ~= "" and path or vim.uv.cwd())
end, { desc = "Explore files" })
map("n", "<leader>gd", function()
  require("mini.diff").toggle_overlay(0)
end, { desc = "Toggle Git diff" })
map("n", "<leader>gg", "<cmd>Git status<CR>", { desc = "Git status" })
map("n", "<leader>l", "<cmd>Lazy<CR>", { desc = "Plugin manager" })
map({ "n", "v" }, "<leader>cf", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format buffer or selection" })
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Show diagnostic" })
map("n", "<leader>cq", vim.diagnostic.setqflist, { desc = "Diagnostics list" })

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("PersonalLsp", { clear = true }),
  callback = function(event)
    for key, action in pairs({
      gd = { vim.lsp.buf.definition, "Go to definition" },
      gr = { vim.lsp.buf.references, "Find references" },
      K = { vim.lsp.buf.hover, "Hover documentation" },
      ["<leader>cr"] = { vim.lsp.buf.rename, "Rename symbol" },
      ["<leader>ca"] = { vim.lsp.buf.code_action, "Code action" },
    }) do
      map("n", key, action[1], { buffer = event.buf, desc = action[2] })
    end
  end,
})

local project_config = vim.env.NVIM_PROJECT_CONFIG
if project_config and project_config ~= "" then
  dofile(project_config)
end
