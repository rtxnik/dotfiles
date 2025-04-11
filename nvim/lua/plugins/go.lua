return {
  {
    "ray-x/go.nvim",
    dependencies = {
      "ray-x/guihua.lua",
      "neovim/nvim-lspconfig",
      "nvim-treesitter/nvim-treesitter",
      "mfussenegger/nvim-dap",
    },
    config = function()
      require("go").setup({
        go = "go",
        format = {
          enable = true,
          auto_format = true,
          formatter = "gofumpt",
        },
        run = {
          enable = true,
          cmd = "go run",
          split = "vs",
        },
        dap_debug = false,
        -- Игнорируем предупреждение golangci-lint
        linter = {
          enable = false,
        },
        lsp_gofumpt = true,
        lsp_inlay_hints = {
          enable = true,
        },
        -- Базовые команды
        test = {
          enable = true,
        },
        commands = {
          load = true,
        },
      })

      -- Запускать форматирование при сохранении
      local format_sync_grp = vim.api.nvim_create_augroup("GoFormat", {})
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.go",
        callback = function()
          require("go.format").goimport()
        end,
        group = format_sync_grp,
      })

      -- Ручная регистрация команд запуска Go
      vim.api.nvim_create_user_command("GoRun", function()
        local filename = vim.fn.expand("%:p")
        local cmd = string.format("term go run %s", filename)
        vim.cmd(cmd)
      end, {})

      vim.api.nvim_create_user_command("GoRunS", function()
        local filename = vim.fn.expand("%:p")
        local cmd = string.format("!go run %s", filename)
        vim.cmd(cmd)
      end, {})

      -- Новые горячие клавиши для Go
      vim.keymap.set("n", "<leader>mr", "<cmd>GoRun<CR>", { desc = "Go Run" })
      vim.keymap.set("n", "<leader>mt", "<cmd>GoTest<CR>", { desc = "Go Test" })
      vim.keymap.set("n", "<leader>mf", "<cmd>GoTestFunc<CR>", { desc = "Go Test Function" })
      vim.keymap.set("n", "<leader>mc", "<cmd>GoCoverage<CR>", { desc = "Go Coverage" })
      vim.keymap.set("n", "<leader>mi", "<cmd>GoImport<CR>", { desc = "Go Import" })
      vim.keymap.set("n", "<leader>ms", "<cmd>GoRunS<CR>", { desc = "Go Run (System)" })
    end,
    event = { "BufReadPost", "BufNewFile" },
    ft = { "go", "gomod" },
    build = ':lua require("go.install").update_all_sync()',
  },
}
