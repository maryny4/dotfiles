-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { "Failed to clone lazy.nvim:\n", "ErrorMsg" }, { out } }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Options
local o = vim.opt
o.clipboard = "unnamedplus"
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.termguicolors = true
o.ignorecase = true
o.smartcase = true
o.undofile = true
o.scrolloff = 6
o.splitright = true
o.splitbelow = true
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.mouse = "a"
o.updatetime = 250

-- Plugins
require("lazy").setup({
  { "folke/tokyonight.nvim", priority = 1000, config = function()
      require("tokyonight").setup({
        transparent = true,
        styles = { sidebars = "transparent", floats = "transparent" },
      })
      vim.cmd.colorscheme("tokyonight-night")
  end },

  { "nvim-treesitter/nvim-treesitter", branch = "main", build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install({ "lua", "bash", "toml", "json",
        "markdown", "markdown_inline", "vim", "vimdoc", "python", "diff" })
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev) pcall(vim.treesitter.start, ev.buf) end,
      })
  end },

  { "ibhagwan/fzf-lua", dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>f", function() require("fzf-lua").files() end,      desc = "Find files" },
      { "<leader>g", function() require("fzf-lua").live_grep() end,  desc = "Grep" },
      { "<leader>b", function() require("fzf-lua").buffers() end,    desc = "Buffers" },
      { "<leader>h", function() require("fzf-lua").helptags() end,   desc = "Help" },
    } },

  { "lewis6991/gitsigns.nvim", event = "BufReadPre", opts = {} },

  { "mason-org/mason.nvim", opts = {} },
  { "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason.nvim", "neovim/nvim-lspconfig" },
    opts = { ensure_installed = { "lua_ls", "bashls", "taplo", "jsonls", "marksman" } } },

  { "saghen/blink.cmp", version = "1.*",
    opts = { completion = { documentation = { auto_show = true } } } },

  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },

  { "echasnovski/mini.pairs", event = "InsertEnter", opts = {} },
}, {
  ui = { border = "rounded" },
  change_detection = { notify = false },
  rocks = { enabled = false },
})

-- LSP keymaps
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local b = ev.buf
    local function m(k, fn, d) vim.keymap.set("n", k, fn, { buffer = b, desc = d }) end
    m("gd", vim.lsp.buf.definition,     "Go to definition")
    m("<leader>rn", vim.lsp.buf.rename, "Rename")
    m("<leader>ca", vim.lsp.buf.code_action, "Code action")
  end,
})

-- CUA shortcuts
local map = vim.keymap.set

map("v", "<C-c>", '"+y', { desc = "Copy" })

map("v", "<C-x>", '"+d', { desc = "Cut" })

map("n", "<C-v>", '"+p', { desc = "Paste" })
map("v", "<C-v>", '"+P', { desc = "Paste" })
map("i", "<C-v>", "<C-r><C-o>+", { desc = "Paste" })
map("c", "<C-v>", "<C-r>+", { desc = "Paste" })

-- Blockwise visual, moved off Ctrl+V
map("n", "<C-q>", "<C-v>", { desc = "Visual block" })

map("n", "<C-a>", "ggVG", { desc = "Select all" })
map("i", "<C-a>", "<Esc>ggVG", { desc = "Select all" })

-- Needs `stty -ixon`, see ~/.bashrc
map({ "n", "i", "v" }, "<C-s>", "<cmd>write<CR>", { desc = "Save" })

map("n", "<C-z>", "u", { desc = "Undo" })
map("i", "<C-z>", "<C-o>u", { desc = "Undo" })
map("n", "<C-y>", "<C-r>", { desc = "Redo" })
