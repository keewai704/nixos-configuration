vim.opt.number = true
vim.opt.relativenumber = false
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
vim.opt.sessionoptions = { "buffers", "curdir", "folds", "tabpages", "winsize", "winpos" }

require("mini.ai").setup()
require("mini.comment").setup()
require("mini.completion").setup()
require("mini.diff").setup()
require("mini.extra").setup()
require("mini.bufremove").setup()
require("mini.git").setup()
require("mini.move").setup()
require("mini.pairs").setup()
require("mini.pick").setup()
require("mini.align").setup()
require("mini.splitjoin").setup()
require("mini.statusline").setup({ use_icons = false })
require("mini.surround").setup()
require("which-key").setup({ icons = { mappings = false } })
require("conform").setup()
require("neo-tree").setup({
  close_if_last_window = true,
  window = { width = 32 },
  filesystem = {
    use_libuv_file_watcher = true,
    filtered_items = { hide_dotfiles = false },
  },
})
local delete_buffer = require("mini.bufremove").delete
require("bufferline").setup({
  options = {
    diagnostics = "nvim_lsp",
    offsets = { { filetype = "neo-tree", text = "Files" } },
    close_command = delete_buffer,
    right_mouse_command = delete_buffer,
  },
})
require("toggleterm").setup({
  open_mapping = [[<C-\>]],
  direction = "float",
  float_opts = { border = "rounded" },
})
require("persistence").setup()
require("trouble").setup({ focus = true, open_no_results = true, warn_no_results = false })

local starter = require("mini.starter")
starter.setup({
  header = "Neovim",
  items = {
    { name = "Find files [Space ff]", action = "Pick files", section = "Files" },
    { name = "Browse files [Space e]", action = "Neotree toggle", section = "Files" },
    { name = "Search contents [Space fg]", action = "Pick grep_live", section = "Files" },
    {
      name = "Restore this workspace [Space sr]",
      action = function()
        require("persistence").load()
      end,
      section = "Workspace",
    },
    { name = "Terminal [Space t]", action = "ToggleTerm", section = "Workspace" },
    { name = "Key bindings [Space ?]", action = "WhichKey", section = "Help" },
    { name = "Plugin manager [Space l]", action = "Lazy", section = "Help" },
    starter.sections.recent_files(5, true),
  },
  footer = "Space opens the key guide.  :Tutor opens the Neovim tutorial.",
})

require("which-key").add({
  { "<leader>f", group = "Find" },
  { "<leader>g", group = "Git" },
  { "<leader>c", group = "Code" },
  { "<leader>b", group = "Buffers" },
  { "<leader>s", group = "Sessions" },
  { "<leader>w", group = "Windows" },
  { "<leader>x", group = "Diagnostics" },
})

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("PersonalTreesitter", { clear = true }),
  callback = function(event)
    pcall(vim.treesitter.start, event.buf)
  end,
})

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
map("n", "<leader>fr", function()
  require("mini.extra").pickers.oldfiles()
end, { desc = "Recent files" })
map("n", "<leader>gc", function()
  require("mini.extra").pickers.git_commits()
end, { desc = "Git history" })
map("n", "<leader>e", "<cmd>Neotree toggle<CR>", { desc = "File explorer" })
map("n", "<leader>ge", "<cmd>Neotree git_status toggle<CR>", { desc = "Git changes explorer" })
map("n", "<leader>t", "<cmd>ToggleTerm<CR>", { desc = "Toggle terminal" })
map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Leave terminal input mode" })
map("n", "[b", "<cmd>BufferLineCyclePrev<CR>", { desc = "Previous buffer" })
map("n", "]b", "<cmd>BufferLineCycleNext<CR>", { desc = "Next buffer" })
map("n", "<leader>bd", delete_buffer, { desc = "Close buffer" })
map("n", "<leader>sr", function()
  require("persistence").load()
end, { desc = "Restore this workspace" })
map("n", "<leader>ss", function()
  require("persistence").select()
end, { desc = "Select saved workspace" })
map("n", "<leader>sd", function()
  require("persistence").stop()
end, { desc = "Stop saving this session" })
map("n", "<leader>ws", "<C-w>s", { desc = "Split horizontally" })
map("n", "<leader>wv", "<C-w>v", { desc = "Split vertically" })
map("n", "<leader>wc", "<C-w>c", { desc = "Close window" })
map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>", { desc = "Workspace diagnostics" })
map("n", "<leader>xb", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", { desc = "Buffer diagnostics" })
map("n", "<leader>cs", "<cmd>Trouble symbols toggle<CR>", { desc = "Document symbols" })
map("n", "<leader>?", "<cmd>WhichKey<CR>", { desc = "Key bindings" })
map("n", "<leader>h", function()
  require("mini.starter").open()
end, { desc = "Home screen" })
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
