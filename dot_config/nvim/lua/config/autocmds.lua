-- =============================================================================
-- Autocmds
-- =============================================================================

local autocmd = vim.api.nvim_create_autocmd

-- -----------------------------------------------------------------------------
-- Zettelkasten Index
-- -----------------------------------------------------------------------------

-- Disable formatting and LSP on Index file for cleaner view
autocmd("BufEnter", {
    pattern = "00.00 Index.md",
    callback = function()
        if vim.bo.filetype ~= "markdown" then
            return
        end

        vim.cmd("RenderMarkdown disable")
        vim.cmd("LspStop")
        vim.b.autoformat = false

        -- Conceal wiki-style links
        vim.o.conceallevel = 2
        vim.o.concealcursor = "nvic"
        vim.fn.matchadd("Conceal", "\\[\\[", 10, -1, { conceal = "" })
        vim.fn.matchadd("Conceal", "\\]\\]", 10, -1, { conceal = "" })
        vim.cmd([[syntax region WikiLink start=/\[\[/ end=/\]\]/ concealends]])
    end,
})

-- Filter out noisy Marksman diagnostics on Index
autocmd("LspAttach", {
    pattern = "00.00 Index.md",
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client or client.name ~= "marksman" then
            return
        end

        client.handlers["textDocument/publishDiagnostics"] = function(_, result, ctx, config)
            local filtered = {}
            for _, diagnostic in ipairs(result.diagnostics) do
                local msg = diagnostic.message
                if not msg:match("Link to non%-existent document") and not msg:match("Ambiguous link") then
                    table.insert(filtered, diagnostic)
                end
            end
            result.diagnostics = filtered
            vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx, config)
        end
    end,
})
