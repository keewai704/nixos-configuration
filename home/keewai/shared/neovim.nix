{ lib, pkgs, ... }:
let
  plugins = {
    "mini.nvim" = pkgs.vimPlugins.mini-nvim;
    "which-key.nvim" = pkgs.vimPlugins.which-key-nvim;
    "nvim-lspconfig" = pkgs.vimPlugins.nvim-lspconfig;
    "conform.nvim" = pkgs.vimPlugins.conform-nvim;
  };
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
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: plugin: ''{ name = "${name}", dir = "${plugin}" },'') plugins
        )}
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
