-- =============================================================================
-- Zettelkasten Workflow
-- =============================================================================

local map = vim.keymap.set

-- -----------------------------------------------------------------------------
-- Create note from [[link]]
-- -----------------------------------------------------------------------------

local function create_zk_note()
    local line = vim.api.nvim_get_current_line()
    local title = line:match("%[%[(.-)%]%]")

    if not title then
        vim.notify("No [[title]] found on current line", vim.log.levels.WARN)
        return
    end

    local output = vim.fn.system(string.format('zk new --vim "%s"', title))
    local file_path = output:match("New note created: (.+)")

    if not file_path then
        vim.notify("Failed to create note: " .. title, vim.log.levels.ERROR)
        return
    end

    -- Clean path and open
    file_path = file_path:gsub("%z", ""):gsub("\n", ""):gsub("^%s*(.-)%s*$", "%1")
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    vim.notify("Created: " .. title)
end

-- -----------------------------------------------------------------------------
-- Open note from [[link]]
-- -----------------------------------------------------------------------------

local function open_zk_link()
    vim.cmd("normal! yi]")
    local text = vim.fn.getreg('"'):gsub("%[%[(.-)%]%]", "%1")

    if text == "" then
        vim.notify("No link found", vim.log.levels.WARN)
        return
    end

    require("telescope.builtin").find_files({
        search_file = vim.fn.escape(text, "\\."),
        hidden = true,
        no_ignore = true,
        follow = true,
    })
end

-- -----------------------------------------------------------------------------
-- Commands & Keymaps
-- -----------------------------------------------------------------------------

vim.api.nvim_create_user_command("ZkNew", create_zk_note, {})
vim.api.nvim_create_user_command("ZkOpen", open_zk_link, {})

map("n", "<leader>zn", "<cmd>ZkNew<cr>", { desc = "Create note from [[link]]" })
map("n", "<leader>zo", "<cmd>ZkOpen<cr>", { desc = "Open note from [[link]]" })
