return {
  {
    "ray-x/go.nvim",
    dependencies = {
      "ray-x/guihua.lua",
      "neovim/nvim-lspconfig",
    },
    config = function()
      require("go").setup({
        go = "go",
        format = {
          enable = true,
          auto_format = true,
          formatter = "gofumpt",
        },
        -- Добавьте явную настройку для run
        run = {
          enable = true,
        },
        dap_debug = false,
        lsp_gofumpt = true,
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
