---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    opts = {
      mappings = {
        n = {
          ["<leader>k"] = { name = "Kulala" },  -- top-level group name
          ["<leader>ks"] = { function() require("kulala").run() end, desc = "Send current request" },
          ["<leader>ka"] = { function() require("kulala").run_all() end, desc = "Send all requests" },
          ["<leader>kr"] = { function() require("kulala").replay() end, desc = "Replay last request" },
          ["<leader>kv"] = { function() require("kulala").toggle_view() end, desc = "Toggle response view" },
        },
      },
    },
  },
  {
    "mistweaverco/kulala.nvim",
    ft = "http",
    opts = {},
  },
}

