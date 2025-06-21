-- Minimal Elixir support (LSP handled by AstroLSP)
---@type LazySpec
return {
  -- Treesitter parsers for Elixir
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if opts.ensure_installed ~= "all" then
        opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, {
          "elixir",
          "heex",
          "eex",
        })
      end
    end,
  },

  -- Enhanced Elixir syntax highlighting
  {
    "elixir-editors/vim-elixir",
    ft = { "elixir", "eex", "heex", "surface" },
  },
}
