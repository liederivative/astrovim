-- Database plugin configuration with vim-dadbod
---@type LazySpec
return {
  -- Dotenv plugin to load .env files
  {
    "tpope/vim-dotenv",
    lazy = false,
    priority = 1000, -- Load early
  },

  -- Core dadbod plugin
  {
    "tpope/vim-dadbod",
    cmd = "DB",
  },

  -- UI for dadbod - using specific version to avoid compatibility issues
  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      "tpope/vim-dadbod",
      "tpope/vim-dotenv",
    },
    lazy = true,
    cmd = {
      "DBUI",
      "DBUIToggle",
      "DBUIAddConnection",
      "DBUIFindBuffer",
      "DBUIRenameBuffer",
      "DBUILastQueryInfo",
    },
    keys = {
      { "<leader>Do", "<cmd>DBUI<cr>", desc = "Open DB UI" },
    },
    init = function()
      -- Configuration for dadbod-ui
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_force_echo_notifications = 0 -- Disable query status messages
      vim.g.db_ui_winwidth = 30
      -- vim.g.db_ui_use_nvim_notify = 1
      vim.g.db_ui_auto_execute_table_helpers = 1
      vim.g.db_ui_save_location = vim.fn.stdpath "data" .. "/dadbod_ui"

      -- Connection and timeout settings to prevent hanging
      vim.g.db_ui_execute_on_save = 0
      vim.g.db_ui_disable_mappings = 1
      vim.g.db_ui_hide_schemas = { "information_schema", "pg_catalog", "pg_toast" }
      vim.g.db_ui_show_help = 1

      -- Prevent paging and "Press ENTER" prompts
      vim.g.db_ui_debug = 0
      vim.g.db_ui_tmp_query_location = vim.fn.stdpath "data" .. "/dadbod_ui/tmp"

      -- Set vim options to prevent paging and reduce messages
      vim.opt.more = false -- Don't pause for "Press ENTER" prompts
      vim.opt.cmdheight = 2 -- Increase command line height to reduce prompts
      vim.opt.shortmess:append "c" -- Reduce completion messages
      vim.opt.shortmess:append "F" -- Don't give file info when editing
      vim.opt.shortmess:append "W" -- Don't give "written" when writing
      vim.opt.shortmess:append "S" -- Don't show search count message
      vim.opt.shortmess:append "I" -- Don't show intro message
      vim.opt.shortmess:append "T" -- Truncate messages to avoid hit-enter prompts
      vim.opt.report = 9999 -- Never report number of lines changed
      
      -- Additional message suppression for database operations
      vim.g.db_ui_disable_progress_bar = 1
      vim.g.db_ui_disable_mappings_info = 1

      -- Configure PostgreSQL display settings for expanded output
      vim.env.PSQL_PAGER = "" -- Disable pager
      vim.env.PAGER = "" -- Disable system pager
      vim.env.MANPAGER = "" -- Disable manual pager
      
      -- PostgreSQL client settings to prevent prompts
      vim.env.PGPASSWORD = "" -- Will be set per connection
      vim.env.PSQL_HISTORY = "/dev/null" -- Disable history
      
      -- Additional database client settings
      vim.env.MYSQL_PAGER = ""
      vim.env.SQLITE_PAGER = ""

      -- Function to load .env file manually as fallback
      local function load_env_file(filepath)
        local env_vars = {}
        filepath = filepath or ".env"

        -- Get Neovim config directory
        local config_dir = vim.fn.stdpath "config"
        local cwd = vim.fn.getcwd()

        -- Priority search locations
        local locations = {
          config_dir .. "/.env", -- ~/.config/nvim/.env (highest priority)
          cwd .. "/.env", -- current working directory
          ".env", -- relative to cwd
          "../.env", -- parent directory
          "../../.env", -- grandparent directory
        }

        local env_file = ""
        for _, loc in ipairs(locations) do
          if vim.fn.filereadable(loc) == 1 then
            env_file = loc
            break
          end
        end

        if env_file ~= "" and vim.fn.filereadable(env_file) == 1 then
          -- Read the entire file at once to handle encoding issues
          local file = io.open(env_file, "rb") -- Open in binary mode
          if not file then
            vim.notify("❌ Could not open .env file", vim.log.levels.ERROR)
            return env_vars
          end

          local content = file:read "*all"
          file:close()

          -- Check for and remove BOM
          if content:sub(1, 3) == "\239\187\191" then
            content = content:sub(4)
          elseif content:sub(1, 2) == "\255\254" or content:sub(1, 2) == "\254\255" then
            vim.notify("❌ UTF-16 encoding detected - please save .env file as UTF-8", vim.log.levels.ERROR)
            return env_vars
          end

          -- Split into lines
          local lines = {}
          for line in content:gmatch "[^\r\n]+" do
            table.insert(lines, line)
          end

          for i, line in ipairs(lines) do
            -- Trim whitespace
            line = line:gsub("^%s+", ""):gsub("%s+$", "")

            -- Skip comments and empty lines
            if not line:match "^#" and line:match "%S" then
              -- More flexible regex pattern
              local key, value = line:match "^([%w_]+)%s*=%s*(.*)$"

              if key and value then
                -- Remove quotes if present
                value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")

                env_vars[key] = value
                -- Also set in environment for os.getenv to work
                vim.fn.setenv(key, value)
              end
            end
          end
        else
          vim.notify("❌ No .env file found in any of the searched locations", vim.log.levels.WARN)
        end

        return env_vars
      end

      -- Load .env file
      local env_vars = load_env_file()

      -- Set environment variables status (silent loading)
      if next(env_vars) then
        local count = 0
        for _ in pairs(env_vars) do
          count = count + 1
        end
        -- Set global variable for status tracking
        vim.g.env_loaded_count = count
        vim.g.env_loaded_status = "󰌋 " .. count .. " env vars"
      else
        vim.g.env_loaded_count = 0
        vim.g.env_loaded_status = "󰌋 no env"
      end

      -- Helper function to get environment variable (from .env or system)
      local function get_env(key, default) return env_vars[key] or os.getenv(key) or default end

      -- URL encode function for special characters in passwords
      local function url_encode(str)
        if not str then return str end
        str = string.gsub(str, "([^%w%-%.%_%~])", function(c) return string.format("%%%02X", string.byte(c)) end)
        return str
      end

      -- Helper function to build connection URL with timeout and compatibility settings
      local function build_postgres_url(user, password, host, port, database)
        -- URL encode the password to handle special characters
        local encoded_password = url_encode(password)
        local encoded_user = url_encode(user)

        -- Add comprehensive options to prevent prompts and paging
        local options = {
          "connect_timeout=10",
          "application_name=vim-dadbod",
          "options=--client-min-messages=warning",
          -- Additional PostgreSQL options to prevent prompts
          "sslmode=prefer", -- Avoid SSL prompts
        }
        
        return string.format(
          "postgresql://%s:%s@%s:%s/%s?%s",
          encoded_user,
          encoded_password,
          host,
          port,
          database,
          table.concat(options, "&")
        )
      end

      -- Build database connections dynamically from environment variables
      local dbs = {}

      -- Always add basic PostgreSQL development connection
      table.insert(dbs, {
        name = "postgres_dev",
        url = build_postgres_url(
          get_env("POSTGRES_USER", "postgres"),
          get_env("POSTGRES_PASSWORD", "password"),
          get_env("POSTGRES_HOST", "localhost"),
          get_env("POSTGRES_PORT", "5432"),
          get_env("POSTGRES_DB_DEV", "postgres")
        ),
      })

      -- Add alternative postgres_dev connection using older scheme (fallback)
      table.insert(dbs, {
        name = "postgres_dev_alt",
        url = string.format(
          "postgres://%s:%s@%s:%s/%s",
          url_encode(get_env("POSTGRES_USER", "postgres")),
          url_encode(get_env("POSTGRES_PASSWORD", "password")),
          get_env("POSTGRES_HOST", "localhost"),
          get_env("POSTGRES_PORT", "5432"),
          get_env("POSTGRES_DB_DEV", "postgres")
        ),
      })

      -- Add SQLite connection
      table.insert(dbs, {
        name = "sqlite_local",
        url = "sqlite:" .. get_env("SQLITE_PATH", vim.fn.expand "~/database.db"),
      })

      -- Add PostgreSQL Production if environment variables are set
      if get_env "POSTGRES_PROD_USER" and get_env "POSTGRES_PROD_PASSWORD" then
        table.insert(dbs, {
          name = "postgres_production",
          url = build_postgres_url(
            get_env "POSTGRES_PROD_USER",
            get_env "POSTGRES_PROD_PASSWORD",
            get_env("POSTGRES_PROD_HOST", "localhost"),
            get_env("POSTGRES_PROD_PORT", "5432"),
            get_env("POSTGRES_PROD_DB", "postgres")
          ),
        })
      end

      -- Add MySQL if environment variables are set
      if get_env "MYSQL_USER" and get_env "MYSQL_PASSWORD" then
        table.insert(dbs, {
          name = "mysql_dev",
          url = string.format(
            "mysql://%s:%s@%s:%s/%s",
            get_env "MYSQL_USER",
            get_env "MYSQL_PASSWORD",
            get_env("MYSQL_HOST", "localhost"),
            get_env("MYSQL_PORT", "3306"),
            get_env("MYSQL_DB", "mysql")
          ),
        })
      end

                    -- Set the databases
              vim.g.dbs = dbs
              
              -- Set up autocmds to prevent intermittent "Press ENTER" prompts
              vim.api.nvim_create_augroup("DadbodMessageSuppression", { clear = true })
              
              -- Apply message suppression when entering SQL files
              vim.api.nvim_create_autocmd({ "FileType" }, {
                group = "DadbodMessageSuppression",
                pattern = { "sql", "pgsql", "mysql", "plsql" },
                callback = function()
                  vim.opt_local.more = false
                  vim.opt_local.report = 9999
                  -- Ensure completion settings are applied
                  vim.g.db_completion_show_messages = 0
                end,
              })
              
              -- Apply message suppression before any DB command
              vim.api.nvim_create_autocmd({ "CmdlineEnter" }, {
                group = "DadbodMessageSuppression",
                pattern = "*",
                callback = function()
                  local cmdline = vim.fn.getcmdline()
                  if cmdline:match("^DB") or cmdline:match("^'<,'>DB") then
                    vim.opt.more = false
                    vim.opt.report = 9999
                  end
                end,
              })
              
              -- Override shell execution to suppress prompts
              vim.api.nvim_create_autocmd({ "User" }, {
                group = "DadbodMessageSuppression", 
                pattern = "DBExecutePre",
                callback = function()
                  -- Set environment variables right before execution
                  vim.env.PSQL_PAGER = ""
                  vim.env.PAGER = ""
                  vim.env.MANPAGER = ""
                  vim.opt.more = false
                  vim.opt.report = 9999
                end,
              })
              
              -- Silence output after DB execution
              vim.api.nvim_create_autocmd({ "User" }, {
                group = "DadbodMessageSuppression",
                pattern = "DBExecutePost", 
                callback = function()
                  -- Clear command line after execution
                  vim.cmd("redraw!")
                end,
              })
            end,
  },

  -- SQL autocompletion for vim-dadbod
  {
    "kristijanhusak/vim-dadbod-completion",
    dependencies = {
      "tpope/vim-dadbod",
      "kristijanhusak/vim-dadbod-ui",
    },
    lazy = true,
    ft = { "sql", "mysql", "plsql", "pgsql" },
    init = function()
      -- Configure completion settings
      vim.g.db_completion_enabled = 1
      vim.g.completion_matching_strategy_list = { "exact", "substring", "fuzzy" }

      -- Suppress vim-dadbod-completion messages
      -- vim.g.db_completion_debug = 0
      -- vim.g.db_completion_show_messages = 0
    end,
  },

  -- Enhanced syntax highlighting for SQL
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if opts.ensure_installed ~= "all" then
        opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, {
          "sql",
        })
      end
    end,
  },

  -- Keybindings and commands
  {
    "AstroNvim/astrocore",
    opts = {
      mappings = {
        n = {
          ["<leader>D"] = { name = "󰆼 Database" },
          ["<leader>Do"] = { "<cmd>DBUI<cr>", desc = "Open DB UI" },
          ["<leader>Dt"] = { "<cmd>DBUIToggle<cr>", desc = "Toggle DB UI" },
          ["<leader>Df"] = { "<cmd>DBUIFindBuffer<cr>", desc = "Find DB buffer" },
          ["<leader>Dr"] = { "<cmd>DBUIRenameBuffer<cr>", desc = "Rename DB buffer" },
          ["<leader>Dl"] = { "<cmd>DBUILastQueryInfo<cr>", desc = "Last query info" },
          ["<leader>Da"] = { "<cmd>DBUIAddConnection<cr>", desc = "Add DB connection" },
          ["<leader>Dv"] = {
            function()
              -- Environment variables status
              local env_status = vim.g.env_loaded_status or "󰌋 no env status"
              local env_count = vim.g.env_loaded_count or 0

              -- Database status
              local db_auto = vim.g.db_auto_selected
              local db_count = vim.g.db_total_count or 0

              local messages = {}

              -- Add env status
              if env_count > 0 then
                table.insert(messages, "✅ " .. env_status)
              else
                table.insert(messages, "⚠️  " .. env_status)
              end

              -- Add database status
              if db_auto then
                table.insert(messages, "🗄️  Auto-selected: " .. db_auto)
                if db_count > 1 then
                  table.insert(messages, "💡 " .. db_count .. " databases available (use <leader>Ds to change)")
                end
              else
                table.insert(messages, "🗄️  No database auto-selected")
              end

              -- Add completion status
              if vim.tbl_contains({ "sql", "pgsql" }, vim.bo.filetype) then
                table.insert(messages, "🔤 SQL completion enabled (Ctrl+X Ctrl+O or auto-complete)")
              else
                table.insert(messages, "🔤 SQL completion available in .sql/.pgsql files")
              end

              -- Show all status info
              for _, msg in ipairs(messages) do
                vim.notify(msg, vim.log.levels.INFO)
              end
            end,
            desc = "Check env & db status",
          },
          ["<leader>Dx"] = {
            function()
              -- Comprehensive fix for paging and messaging issues
              vim.opt.more = false
              vim.opt.cmdheight = 2
              vim.opt.shortmess:append "cFWSIT"
              vim.opt.report = 9999
              
              -- Database UI settings
              vim.g.db_ui_force_echo_notifications = 0
              vim.g.db_ui_disable_progress_bar = 1
              vim.g.db_ui_disable_mappings_info = 1
              
              -- Completion settings
              vim.g.db_completion_debug = 0
              vim.g.db_completion_show_messages = 0
              
              -- Disable various message sources
              vim.g.db_ui_debug = 0
              vim.g.db_ui_show_help = 0
              
              -- Environment settings to prevent paging
              vim.env.PSQL_PAGER = ""
              vim.env.PAGER = ""
              vim.env.MANPAGER = ""
              
              vim.notify("🔧 Applied comprehensive DB message suppression", vim.log.levels.INFO)
            end,
            desc = "Fix DB paging & messages",
          },
          ["<leader>Dc"] = {
            function()
              -- Test both postgres_dev connections
              vim.ui.select({ "postgres_dev", "postgres_dev_alt", "manual_test" }, {
                prompt = "Choose connection test:",
              }, function(choice)
                if choice == "manual_test" then
                  -- Manual test using DB command directly
                  local function url_encode(str)
                    if not str then return str end
                    str = string.gsub(
                      str,
                      "([^%w%-%.%_%~])",
                      function(c) return string.format("%%%02X", string.byte(c)) end
                    )
                    return str
                  end

                  local user = os.getenv "POSTGRES_USER" or "postgres"
                  local pass = os.getenv "POSTGRES_PASSWORD" or "password"
                  local host = os.getenv "POSTGRES_HOST" or "localhost"
                  local port = os.getenv "POSTGRES_PORT" or "5432"
                  local db = os.getenv "POSTGRES_DB_DEV" or "postgres"

                  local url =
                    string.format("postgresql://%s:%s@%s:%s/%s", url_encode(user), url_encode(pass), host, port, db)
                  vim.notify("Testing direct DB command...", vim.log.levels.INFO)
                  vim.cmd("DB " .. url .. " SELECT 'Connection successful!' as status, version() as version")
                  return
                end

                local selected_db = nil
                if vim.g.dbs then
                  for _, db_config in ipairs(vim.g.dbs) do
                    if db_config.name == choice then
                      selected_db = db_config
                      break
                    end
                  end
                end

                if selected_db then
                  vim.notify("Testing " .. choice .. " connection...", vim.log.levels.INFO)
                  vim.cmd "split"
                  vim.cmd "enew"
                  vim.bo.filetype = "sql"
                  vim.b.db = selected_db.url
                  local test_query = "SELECT 'Connection successful!' as status, version() as postgres_version;"
                  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                    "-- Testing " .. choice .. " connection",
                    "-- URL: " .. selected_db.url:gsub("://([^:]+):([^@]+)@", "://%1:***@"),
                    "",
                    test_query,
                  })
                  vim.cmd "normal! G"
                  vim.notify("Run <leader>DL to test connection", vim.log.levels.INFO)
                else
                  vim.notify(choice .. " database not found", vim.log.levels.ERROR)
                end
              end)
            end,
            desc = "Test postgres connections",
          },
          ["<leader>Dd"] = {
            function()
              -- Diagnostic information for vim-dadbod
              vim.notify("=== VIM-DADBOD DIAGNOSTICS ===", vim.log.levels.INFO)

              -- Check vim settings that might cause paging
              vim.notify("=== VIM SETTINGS ===", vim.log.levels.INFO)
              vim.notify("more: " .. tostring(vim.opt.more:get()), vim.log.levels.INFO)
              vim.notify("cmdheight: " .. tostring(vim.opt.cmdheight:get()), vim.log.levels.INFO)
              vim.notify("shortmess: " .. vim.opt.shortmess:get(), vim.log.levels.INFO)

              -- Check if psql is available
              local psql_check = vim.fn.system "which psql"
              if vim.v.shell_error == 0 then
                vim.notify("✅ psql found: " .. psql_check:gsub("\n", ""), vim.log.levels.INFO)
              else
                vim.notify("❌ psql not found in PATH", vim.log.levels.ERROR)
              end

              -- Check PostgreSQL connection with psql using environment variables
              local user = os.getenv "POSTGRES_USER" or "postgres"
              local host = os.getenv "POSTGRES_HOST" or "localhost"
              local port = os.getenv "POSTGRES_PORT" or "5432"
              local db = os.getenv "POSTGRES_DB_DEV" or "postgres"
              local password = os.getenv "POSTGRES_PASSWORD" or "password"

              vim.notify("Testing psql connection...", vim.log.levels.INFO)
              local psql_cmd = string.format(
                "PGPASSWORD='%s' psql -h %s -p %s -U %s -d %s -c 'SELECT version();' -t",
                password,
                host,
                port,
                user,
                db
              )

              local result = vim.fn.system(psql_cmd)
              if vim.v.shell_error == 0 then
                vim.notify("✅ psql connection successful", vim.log.levels.INFO)
                vim.notify("PostgreSQL version: " .. result:gsub("^%s*(.-)%s*$", "%1"), vim.log.levels.INFO)
              else
                vim.notify("❌ psql connection failed: " .. result, vim.log.levels.ERROR)
              end

              -- Show connection URLs
              vim.notify("=== CONNECTION URLS ===", vim.log.levels.INFO)
              if vim.g.dbs then
                for _, db_config in ipairs(vim.g.dbs) do
                  if db_config.name:match "postgres" then
                    local safe_url = db_config.url:gsub("://([^:]+):([^@]+)@", "://%1:***@")
                    vim.notify(db_config.name .. ": " .. safe_url, vim.log.levels.INFO)
                  end
                end
              end
            end,
            desc = "Diagnose vim-dadbod issues",
          },
          -- SQL file specific mappings
          ["<leader>DE"] = {
            function()
              local filetype = vim.bo.filetype
              if not vim.tbl_contains({ "sql", "pgsql" }, filetype) then
                vim.notify("Not in a SQL file", vim.log.levels.WARN)
                return
              end
              
              -- Silent execution wrapper
              local function silent_db_execute(cmd)
                -- Save current settings
                local old_more = vim.opt.more:get()
                local old_report = vim.opt.report:get()
                local old_cmdheight = vim.opt.cmdheight:get()
                
                -- Apply silent settings
                vim.opt.more = false
                vim.opt.report = 9999
                vim.opt.cmdheight = 3
                vim.env.PSQL_PAGER = ""
                vim.env.PAGER = ""
                vim.env.MANPAGER = ""
                
                -- Execute command silently
                local ok, err = pcall(function()
                  vim.cmd("silent! " .. cmd)
                end)
                
                -- Restore settings
                vim.opt.more = old_more
                vim.opt.report = old_report  
                vim.opt.cmdheight = old_cmdheight
                
                -- Force redraw to clear any lingering messages
                vim.cmd("redraw!")
                
                if not ok then
                  vim.notify("DB execution error: " .. tostring(err), vim.log.levels.ERROR)
                end
              end
              
              silent_db_execute("%DB")
            end,
            desc = "Execute entire SQL buffer",
          },
          ["<leader>DL"] = {
            function()
              local filetype = vim.bo.filetype
              if not vim.tbl_contains({ "sql", "pgsql" }, filetype) then
                vim.notify("Not in a SQL file", vim.log.levels.WARN)
                return
              end
              
              -- Silent execution wrapper for single line
              vim.opt.more = false
              vim.opt.report = 9999
              vim.env.PSQL_PAGER = ""
              vim.env.PAGER = ""
              
              local ok, err = pcall(function()
                vim.cmd("silent! .DB")
              end)
              
              vim.cmd("redraw!")
              
              if not ok then
                vim.notify("DB execution error: " .. tostring(err), vim.log.levels.ERROR)
              end
            end,
            desc = "Execute current SQL line",
          },
          ["<leader>Ds"] = {
            function()
              if not vim.g.dbs or #vim.g.dbs == 0 then
                vim.notify("No databases configured", vim.log.levels.ERROR)
                return
              end

              vim.ui.select(vim.g.dbs, {
                prompt = "Select database for this SQL file:",
                format_item = function(item) return item.name end,
              }, function(choice)
                if choice then
                  vim.b.db = choice.url
                  vim.notify("Database set to: " .. choice.name, vim.log.levels.INFO)
                end
              end)
            end,
            desc = "Select database for SQL file",
          },
          ["<leader>Dw"] = {
            function()
              if vim.tbl_contains({ "sql", "pgsql" }, vim.bo.filetype) then
                vim.fn.append(vim.fn.line ".", "\\x")
                vim.notify("Added \\x (expanded display toggle)", vim.log.levels.INFO)
              else
                vim.notify("⚠️  This command works only in SQL/PGSQL files", vim.log.levels.WARN)
              end
            end,
            desc = "Add PostgreSQL \\x (expanded display)",
          },
          ["<leader>Dy"] = {
            function()
              if vim.tbl_contains({ "sql", "pgsql" }, vim.bo.filetype) then
                vim.fn.append(vim.fn.line ".", "\\timing")
                vim.notify("Added \\timing (show query timing)", vim.log.levels.INFO)
              else
                vim.notify("⚠️  This command works only in SQL/PGSQL files", vim.log.levels.WARN)
              end
            end,
            desc = "Add PostgreSQL \\timing",
          },

        },
        v = {
          ["<leader>S"] = {
            function()
              local filetype = vim.bo.filetype
              if not vim.tbl_contains({ "sql", "pgsql" }, filetype) then
                vim.notify("Not in a SQL file", vim.log.levels.WARN)
                return
              end
              
              -- Silent execution wrapper for visual selection
              vim.opt.more = false
              vim.opt.report = 9999
              vim.env.PSQL_PAGER = ""
              vim.env.PAGER = ""
              
              local ok, err = pcall(function()
                vim.cmd("silent! '<,'>DB")
              end)
              
              vim.cmd("redraw!")
              
              if not ok then
                vim.notify("DB execution error: " .. tostring(err), vim.log.levels.ERROR)
              end
            end,
            desc = "Execute SQL selection",
          },
        },
      },
      -- Auto commands for SQL files
      autocmds = {
        dadbod_sql = {
          {
            event = { "FileType", "BufEnter", "BufWinEnter" },
            pattern = { "sql", "pgsql" },
            callback = function()
              -- Store original cmdheight if not already stored
              if not vim.g._dadbod_original_cmdheight then
                vim.g._dadbod_original_cmdheight = vim.opt.cmdheight:get()
              end
              
              -- Force apply message suppression settings every time we enter SQL buffer
              vim.opt_local.more = false
              vim.opt_local.report = 9999
              vim.opt.cmdheight = 2  -- Only for SQL files
              vim.opt.shortmess:append("cFWSIT")
              
              -- Database-specific environment settings
              vim.env.PSQL_PAGER = ""
              vim.env.PAGER = ""
              vim.env.MANPAGER = ""
              
              -- Disable all database UI messages
              vim.g.db_ui_force_echo_notifications = 0
              vim.g.db_ui_disable_progress_bar = 1
              vim.g.db_ui_disable_mappings_info = 1
              vim.g.db_ui_debug = 0
              vim.g.db_completion_show_messages = 0
              vim.g.db_completion_debug = 0

              -- Enable SQL completion
              vim.bo.omnifunc = "vim_dadbod_completion#omni"

              -- Add manual completion keybind as fallback
              vim.keymap.set("i", "<C-x><C-o>", "<C-x><C-o>", { buffer = true, desc = "Manual SQL completion" })

              -- Auto-select postgres_dev as default database (silent)
              if vim.g.dbs and #vim.g.dbs > 0 and not vim.b.db then
                -- Look for postgres_dev first
                local default_db = nil
                for _, db in ipairs(vim.g.dbs) do
                  if db.name == "postgres_dev" then
                    default_db = db
                    break
                  end
                end

                -- If postgres_dev not found, use the first database
                if not default_db then default_db = vim.g.dbs[1] end

                vim.b.db = default_db.url
                -- Store auto-selected database info for status check
                vim.g.db_auto_selected = default_db.name
                vim.g.db_total_count = #vim.g.dbs
              end
            end,
          },
          -- Store original settings and restore when leaving SQL files
          {
            event = "BufLeave",
            pattern = { "sql", "pgsql" },
            callback = function()
              -- Restore original cmdheight when leaving SQL files
              if vim.g._dadbod_original_cmdheight then
                vim.opt.cmdheight = vim.g._dadbod_original_cmdheight
              end
            end,
          },
          -- Restore settings when entering SQL files after being in other files
          {
            event = "BufEnter",
            pattern = { "sql", "pgsql" },
            callback = function()
              -- Force reapply settings when entering SQL buffer from any other buffer
              vim.schedule(function()
                -- Store original cmdheight if not already stored
                if not vim.g._dadbod_original_cmdheight then
                  vim.g._dadbod_original_cmdheight = vim.opt.cmdheight:get()
                end
                
                vim.opt.more = false
                vim.opt.report = 9999
                vim.opt.cmdheight = 2  -- Only for SQL files
                vim.opt.shortmess:append("cFWSIT")
                
                -- Reset environment variables
                vim.env.PSQL_PAGER = ""
                vim.env.PAGER = ""
                vim.env.MANPAGER = ""
                
                -- Reset all database message settings
                vim.g.db_ui_force_echo_notifications = 0
                vim.g.db_completion_show_messages = 0
                vim.g.db_completion_debug = 0
              end)
            end,
          },
          -- Restore original cmdheight when entering specific non-SQL file types
          {
            event = "FileType",
            pattern = { "lua", "elixir", "javascript", "typescript", "python", "go", "rust", "c", "cpp", "java", "vim", "markdown", "text", "json", "yaml", "toml", "html", "css", "scss" },
            callback = function()
              -- Restore cmdheight for common file types (not SQL)
              if vim.g._dadbod_original_cmdheight then
                vim.schedule(function()
                  vim.opt.cmdheight = vim.g._dadbod_original_cmdheight
                end)
              end
            end,
          },
        },
      },
    },
  },

  -- Configure blink.cmp to work with vim-dadbod-completion
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        per_filetype = {
          sql = { "vim_dadbod_completion", "buffer" },
          pgsql = { "vim_dadbod_completion", "buffer" },
        },
        providers = {
          vim_dadbod_completion = {
            name = "vim_dadbod_completion",
            module = "vim_dadbod_completion.blink",
          },
        },
      },
    },
  },
}
