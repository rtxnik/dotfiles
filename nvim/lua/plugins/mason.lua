return {
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        -- LSPs
        "gopls", -- Go language server
        "delve", -- Go debugger

        -- Linters
        "golangci-lint",

        -- Formatters
        "gofumpt",
        "goimports",
        "gomodifytags",
        "gotests",
        "impl",

        -- Другие инструменты, которые могут понадобиться
        "stylua",
        "shellcheck",
        "shfmt",
      },
    },
  },
}
