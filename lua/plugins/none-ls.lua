if true then return {} end -- WARN: REMOVE THIS LINE TO ACTIVATE THIS FILE

-- Customize None-ls sources

---@type LazySpec
return {
  "nvimtools/none-ls.nvim",
  opts = function(_, opts)
    -- opts variable is the default configuration table for the setup function call
    local null_ls = require "null-ls"

    -- Check supported formatters and linters
    -- https://github.com/nvimtools/none-ls.nvim/tree/main/lua/null-ls/builtins/formatting
    -- https://github.com/nvimtools/none-ls.nvim/tree/main/lua/null-ls/builtins/diagnostics

    -- Only insert new sources, do not replace the existing ones
    -- (If you wish to replace, use `opts.sources = {}` instead of the `list_insert_unique` function)
    opts.sources = require("astrocore").list_insert_unique(opts.sources, {
      -- Formatters
      null_ls.builtins.formatting.stylua, -- Lua formatter

      -- Diagnostics (Linters)
      -- null_ls.builtins.diagnostics.misspell, -- Removed - using Vim's built-in spell checking instead

      -- You can add more formatters/linters here
      -- null_ls.builtins.formatting.prettier, -- JavaScript/TypeScript formatter
      -- null_ls.builtins.diagnostics.eslint, -- JavaScript linter
    })
  end,
}
