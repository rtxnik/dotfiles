return {
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        -- LSPs
        "gopls",

        -- Отладчик
        "delve",

        -- Форматировщики
        "gofumpt",
        "goimports",

        -- Другие инструменты
        "stylua",
      },
    },
  },
}
