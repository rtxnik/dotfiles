-- =============================================================================
-- Plugins
-- =============================================================================

return {
    -- -------------------------------------------------------------------------
    -- Colorscheme
    -- -------------------------------------------------------------------------
    {
        "wittyjudge/gruvbox-material.nvim",
        lazy = false,
        priority = 1000,
    },
    {
        "LazyVim/LazyVim",
        opts = {
            colorscheme = "gruvbox-material",
        },
    },

    -- -------------------------------------------------------------------------
    -- Disabled defaults
    -- -------------------------------------------------------------------------
    { "echasnovski/mini.pairs", enabled = false },
    { "folke/noice.nvim", enabled = false },
    { "rcarriga/nvim-notify", enabled = false },

    -- -------------------------------------------------------------------------
    -- LazyVim extras
    -- -------------------------------------------------------------------------
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.toml" },
    { import = "lazyvim.plugins.extras.lang.yaml" },
    { import = "lazyvim.plugins.extras.editor.telescope" },

    -- -------------------------------------------------------------------------
    -- Telescope
    -- -------------------------------------------------------------------------
    {
        "nvim-telescope/telescope.nvim",
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
        },
        opts = {
            pickers = {
                find_files = {
                    find_command = { "rg", "--files", "--glob", "!**/.git/*", "-L" },
                },
            },
        },
    },
    {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        config = function()
            require("telescope").load_extension("fzf")
        end,
    },
    { "nvim-telescope/telescope-symbols.nvim" },

    -- -------------------------------------------------------------------------
    -- Treesitter
    -- -------------------------------------------------------------------------
    {
        "nvim-treesitter/nvim-treesitter",
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
            },
            highlight = {
                disable = function(lang)
                    -- Disable on terraform fixture files
                    if lang == "terraform" and vim.fn.expand("%"):find("fixture") then
                        return true
                    end
                end,
            },
        },
    },

    -- -------------------------------------------------------------------------
    -- Utilities
    -- -------------------------------------------------------------------------
    {
        "shortcuts/no-neck-pain.nvim",
        cmd = "NoNeckPain",
        keys = { { "<leader>nn", "<cmd>NoNeckPain<cr>", desc = "No Neckpain" } },
        opts = {},
    },
    {
        "sotte/presenting.nvim",
        cmd = "Presenting",
        opts = {
            separator = {
                markdown = "^#+ ",
                pandoc = "^#+ ",
            },
        },
    },
}
