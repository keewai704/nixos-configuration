vim.lsp.config("nixd", {
  settings = {
    nixd = {
      formatting = { command = { "nixfmt" } },
    },
  },
  before_init = function(_, config)
    local flake = "(builtins.getFlake " .. vim.json.encode(config.root_dir) .. ")"
    local host = vim.env.NVIM_NIXOS_HOST or vim.uv.os_gethostname()
    local configuration = flake .. ".nixosConfigurations." .. vim.json.encode(host)
    config.settings.nixd.nixpkgs = {
      expr = "import " .. flake .. ".inputs.nixpkgs { }",
    }
    config.settings.nixd.options = {
      nixos = { expr = configuration .. ".options" },
      home_manager = { expr = configuration .. ".options.home-manager.users.type.getSubOptions []" },
    }
  end,
})

vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      diagnostics = { globals = { "vim" } },
      workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
      telemetry = { enable = false },
    },
  },
})

vim.lsp.enable({ "nixd", "lua_ls", "bashls" })

require("conform").setup({
  formatters_by_ft = {
    nix = { "nixfmt" },
    lua = { "stylua" },
    sh = { "shfmt" },
    bash = { "shfmt" },
  },
})
