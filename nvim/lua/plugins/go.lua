return {
  {
    "ray-x/go.nvim",
    dependencies = {
      "ray-x/guihua.lua",
      "neovim/nvim-lspconfig",
      "nvim-treesitter/nvim-treesitter",
      "mfussenegger/nvim-dap", -- Важная зависимость для GoRun
    },
    config = function()
      require("go").setup({
        go = "go", -- Убедитесь, что это соответствует пути к вашему исполняемому файлу go
        format = {
          enable = true,
          auto_format = true,
          formatter = "gofumpt",
        },
        run = {
          enable = true,
          cmd = "go run", -- Явная команда для GoRun
          split = "vs", -- Поведение разделения для вывода
        },
        dap_debug = false,
        lsp_gofumpt = true,
        lsp_inlay_hints = {
          enable = true,
        },
        -- Убедитесь, что команды для тестов и запуска загружены
        test = {
          enable = true,
        },
        -- Убедитесь, что команды регистрируются
        commands = {
          load = true,
        },
      })

      -- Альтернативный вариант - создаем собственную команду, которая просто запускает go run через терминал
      vim.api.nvim_create_user_command("GoRun", function()
        -- Получаем текущий буфер/файл
        local filename = vim.fn.expand("%:p")
        -- Создаем команду для запуска
        local cmd = string.format("term go run %s", filename)
        -- Выполняем команду
        vim.cmd(cmd)
      end, {})

      -- Еще один вариант - запуск через системную команду!
      vim.api.nvim_create_user_command("GoRunS", function()
        -- Получаем текущий буфер/файл
        local filename = vim.fn.expand("%:p")
        -- Создаем команду для запуска
        local cmd = string.format("!go run %s", filename)
        -- Выполняем команду
        vim.cmd(cmd)
      end, {})

      -- Запускать форматирование при сохранении
      local format_sync_grp = vim.api.nvim_create_augroup("GoFormat", {})
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.go",
        callback = function()
          require("go.format").goimport()
        end,
        group = format_sync_grp,
      })
    end,
    event = { "BufReadPost", "BufNewFile" },
    ft = { "go", "gomod" },
    build = ':lua require("go.install").update_all_sync()',
  },
}
