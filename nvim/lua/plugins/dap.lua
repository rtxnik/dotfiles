return {
  {
    "mfussenegger/nvim-dap",
    config = function()
      -- Базовая конфигурация DAP
      local dap = require("dap")

      -- Базовая конфигурация для Go
      dap.adapters.go = {
        type = "executable",
        command = "node",
        args = { vim.fn.stdpath("data") .. "/mason/packages/delve/extension/adapter/goDebug.js" },
      }

      dap.configurations.go = {
        {
          type = "go",
          name = "Debug",
          request = "launch",
          program = "${file}",
        },
      }

      -- Горячие клавиши для основных операций
      vim.keymap.set("n", "<leader>db", function()
        require("dap").toggle_breakpoint()
      end)
      vim.keymap.set("n", "<leader>dc", function()
        require("dap").continue()
      end)
      vim.keymap.set("n", "<leader>do", function()
        require("dap").step_over()
      end)
      vim.keymap.set("n", "<leader>di", function()
        require("dap").step_into()
      end)
      vim.keymap.set("n", "<leader>du", function()
        require("dap").step_out()
      end)
    end,
  },

  -- Упрощенная конфигурация для DAP UI
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap" },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      dapui.setup({
        -- Минимальная конфигурация
        layouts = {
          {
            elements = {
              { id = "scopes", size = 0.5 },
              { id = "watches", size = 0.5 },
            },
            size = 0.3,
            position = "left",
          },
          {
            elements = {
              { id = "repl", size = 1.0 },
            },
            size = 0.3,
            position = "bottom",
          },
        },
      })

      -- Автоматически открывать UI при начале отладки
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
      end)
    end,
  },

  -- Упрощенная конфигурация для виртуального текста
  {
    "theHamsta/nvim-dap-virtual-text",
    dependencies = { "mfussenegger/nvim-dap" },
    config = function()
      require("nvim-dap-virtual-text").setup({
        enabled = true,
        enabled_commands = true,
      })
    end,
  },
}
