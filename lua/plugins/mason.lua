-- Customize Mason

---@type LazySpec
return {
  -- use mason-tool-installer for automatically installing Mason packages
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- overrides `require("mason-tool-installer").setup(...)`
    opts = {
      -- Make sure to use the names found in `:Mason`
      ensure_installed = {
        -- install language servers
        "lua-language-server",
        "elixir-ls", -- Re-enabled since Elixir is installed

        -- install formatters
        "stylua",

        -- install linters/diagnostics
        -- "misspell", -- Removed - using Vim's built-in spell checking instead

        -- install debuggers
        -- "debugpy",

        -- install any other package
        -- "tree-sitter-cli",
        -- "shellcheck",
      },
      
      -- automatically install tools without prompting
      auto_update = false,
      run_on_start = true,
      start_delay = 3000, -- 3 seconds delay before starting installation
      debounce_hours = 5, -- only check for new installs every 5 hours
    },
  },
}
