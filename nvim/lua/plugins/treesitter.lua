return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    opts = {
      ensure_installed = {
        "bash",
        "vimdoc",
        "html",
        "json",
        "lua",
        "python",
        "query",
        "regex",
        "vim",
        "yaml",
        "go",
        "bicep",
        "terraform",
        "c_sharp",
        "sql",
        "gotmpl",
        "comment",
        "gomod",
        "gosum",
        "gowork",
      },
      sync_install = false,
      auto_install = false,
      highlight = {
        enable = true,
        disable = function(lang)
          local buf_name = vim.fn.expand("%")
          if lang == "terraform" and string.find(buf_name, "fixture") then
            return true
          end
        end,
      },
      indent = { enable = true },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },
}
