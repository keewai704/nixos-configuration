{ lib, pkgs, ... }:
let
  plugins = {
    "mini.nvim" = pkgs.vimPlugins.mini-nvim;
    "which-key.nvim" = pkgs.vimPlugins.which-key-nvim;
    "nvim-lspconfig" = pkgs.vimPlugins.nvim-lspconfig;
    "conform.nvim" = pkgs.vimPlugins.conform-nvim;
    "neo-tree.nvim" = pkgs.vimPlugins.neo-tree-nvim;
    "nvim-web-devicons" = pkgs.vimPlugins.nvim-web-devicons;
    "bufferline.nvim" = pkgs.vimPlugins.bufferline-nvim;
    "toggleterm.nvim" = pkgs.vimPlugins.toggleterm-nvim;
    "persistence.nvim" = pkgs.vimPlugins.persistence-nvim;
    "trouble.nvim" = pkgs.vimPlugins.trouble-nvim;
    "nvim-treesitter" = pkgs.vimPlugins.nvim-treesitter.withPlugins (
      parsers: with parsers; [
        bash
        c
        cpp
        css
        html
        javascript
        json
        lua
        markdown
        markdown_inline
        nix
        python
        regex
        toml
        tsx
        typescript
        vim
        vimdoc
        yaml
      ]
    );
  };
  renderPluginSpec =
    name: plugin:
    let
      dependencies = plugin.dependencies or [ ];
      dependencySpecs = map (
        dependency: renderPluginSpec (lib.getName dependency) dependency
      ) dependencies;
    in
    ''
      {
        name = "${name}",
        dir = "${plugin}",
        dependencies = {
          ${lib.concatStringsSep ",\n" dependencySpecs}
        },
      }
    '';

in
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    extraPackages = [
      pkgs.fd
      pkgs.git
      pkgs.ripgrep
    ];
    initLua = ''
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "
      vim.opt.rtp:prepend("${pkgs.vimPlugins.lazy-nvim}")
      require("lazy").setup({
        ${lib.concatStringsSep ",\n" (lib.mapAttrsToList renderPluginSpec plugins)}
      }, {
        local_spec = false,
        lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
        install = { missing = false },
        checker = { enabled = false },
        rocks = { enabled = false },
        pkg = { enabled = false },
        change_detection = { enabled = false },
        performance = { reset_packpath = false, rtp = { reset = false } },
      })
    ''
    + builtins.readFile ./neovim.lua;
  };
}
