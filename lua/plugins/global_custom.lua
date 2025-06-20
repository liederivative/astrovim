
---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
  ---@type AstroCoreOpts
    opts = {
    -- vim options can be configured here
    options = {
      opt = { -- vim.opt.<key>
        relativenumber = false, -- sets vim.opt.relativenumber
        number = true, -- sets vim.opt.number
        spell = true, -- sets vim.opt.spell
        wrap = true, -- sets vim.opt.wrap
      },
      }
    },
  },
}

