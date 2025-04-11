return {
  {
    "nvim-neotest/nvim-nio",
    lazy = false,
    priority = 110,
  },
  {
    "rcarriga/nvim-dap-ui",
    dependencies = {
      "mfussenegger/nvim-dap",
      "nvim-neotest/nvim-nio",
    },
    lazy = false,
    priority = 100,
    config = function()
      -- Настраиваем dap-ui только после того, как он загружен
      local ok, dapui = pcall(require, "dapui")
      if not ok then
        print("Ошибка загрузки dapui:", dapui)
        return
      end

      dapui.setup({
        -- Минимальная конфигурация
        icons = { expanded = "▾", collapsed = "▸" },
        layouts = {
          {
            elements = {
              "scopes",
              "breakpoints",
              "stacks",
              "watches",
            },
            size = 40,
            position = "left",
          },
          {
            elements = {
              "repl",
              "console",
            },
            size = 10,
            position = "bottom",
          },
        },
      })

      -- Автоматически открывать UI при начале отладки
      local dap = require("dap")
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end

      -- Клавиша для ручного открытия/закрытия UI
      vim.keymap.set("n", "<leader>dui", function()
        dapui.toggle()
      end, { desc = "Toggle Debug UI" })
    end,
  },
}
