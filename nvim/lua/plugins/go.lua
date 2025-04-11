return {
  {
    "ray-x/go.nvim",
    dependencies = {
      "ray-x/guihua.lua",
      "neovim/nvim-lspconfig",
    },
    config = function()
      require("go").setup({
        -- Путь к Go
        go = "go",
        -- Используем format.auto_format вместо устаревшего goimport
        format = {
          enable = true,
          auto_format = true,
          formatter = "gofumpt",
        },
        -- Отключаем отладку
        dap_debug = false,
        -- Другие настройки форматирования
        lsp_gofumpt = true, -- true: использовать gofumpt вместо gofmt в gopls
        lsp_inlay_hints = {
          enable = true,
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
    end,
    -- Изменим event для более надежной загрузки плагина
    event = { "BufReadPost", "BufNewFile" },
    ft = { "go", "gomod" },
    build = ':lua require("go.install").update_all_sync()',
  },
}
