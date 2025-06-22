-- Custom bash functions and commands
---@type LazySpec

-- Global table to track running gport processes
_G.gport_processes = _G.gport_processes or {}

-- Function to update status line
local function update_gport_status()
  local count = 0
  for pid, info in pairs(_G.gport_processes) do
    -- Check if process is still running
    local handle = vim.loop.spawn("kill", {
      args = { "-0", tostring(pid) },
    }, function(code, signal)
      if code ~= 0 then
        -- Process not running, remove from table
        _G.gport_processes[pid] = nil
      end
    end)
    if handle then
      count = count + 1
    end
  end
  
  -- Update global variable for status line
  vim.g.gport_count = count
  return count
end

-- Function to add process to tracking
local function track_gport_process(pid, project, port_mapping, user, ssh_key)
  _G.gport_processes[pid] = {
    project = project,
    port_mapping = port_mapping,
    user = user or "current",
    ssh_key = ssh_key or "default",
    started = os.time(),
  }
  update_gport_status()
end

-- Set up periodic status updates
vim.defer_fn(function()
  local timer = vim.loop.new_timer()
  timer:start(0, 10000, vim.schedule_wrap(function() -- Update every 10 seconds
    update_gport_status()
  end))
end, 1000)

-- Status line component for gport processes
local function gport_status_component()
  local count = vim.g.gport_count or 0
  if count > 0 then
    return "📡 " .. count .. " gport"
  end
  return ""
end

-- Add to status line if using AstroUI
vim.g.gport_status_component = gport_status_component

return {
  {
    "AstroNvim/astrocore",
    opts = {
      -- Custom commands
      commands = {
        -- Google Cloud port forwarding command
                Gport = {
          function(opts)
            local args = opts.fargs
            if #args < 1 then
              vim.notify("Usage: :Gport <project-name> [port-mapping] [ssh-user] [ssh-key-file]", vim.log.levels.ERROR)
              vim.notify("Example: :Gport test", vim.log.levels.INFO)
              vim.notify("Example: :Gport test 5432:localhost:5432", vim.log.levels.INFO)
              vim.notify("Example: :Gport test 5432:localhost:5432 myuser", vim.log.levels.INFO)
              vim.notify("Example: :Gport test 5432:localhost:5432 myuser ~/.ssh/my_key", vim.log.levels.INFO)
              vim.notify("Default port mapping: 5432:localhost:5432", vim.log.levels.INFO)
              vim.notify("Default SSH user: current user", vim.log.levels.INFO)
              vim.notify("Default SSH key: google_compute_engine", vim.log.levels.INFO)
              return
            end
            
            local project_name = args[1]
            local port_mapping = args[2] or "5432:localhost:5432"
            local ssh_user = args[3] or ""
            local ssh_key = args[4] or ""

            -- Create temporary script file
            local temp_script = vim.fn.tempname() .. ".sh"
            local script_content = string.format(
              [[#!/bin/bash
# Get project ID
PROJ_ID=$(gcloud projects list --filter labels.active=true | grep "%s " | awk '{ print $1 }')

if [ -z "$PROJ_ID" ]; then
  echo "Error: No project found with name '%s'"
  exit 1
fi

echo "Found project: $PROJ_ID"

# Get zone
zone=$(gcloud compute instances list --project $PROJ_ID --filter="Name:util-1" --format='value(zone)')

if [ -z "$zone" ]; then
  echo "Error: No util-1 instance found in project $PROJ_ID"
  exit 1
fi

echo "Found zone: $zone"
echo "Connecting with port forwarding: %s"

# Connect with SSH port forwarding
gcloud compute ssh --zone $zone --project $PROJ_ID util-1 --ssh-flag='-A' --ssh-flag='-L' --ssh-flag='%s'

# Clean up
rm -f %s
]],
              project_name,
              project_name,
              port_mapping,
              port_mapping,
              temp_script
            )

                        -- Write the script
            local file = io.open(temp_script, "w")
            if file then
              file:write(script_content)
              file:close()
              os.execute("chmod +x " .. temp_script)
              
              -- Execute in terminal first for password input
              vim.notify("🚀 Starting port forwarding: " .. project_name .. " -> " .. port_mapping, vim.log.levels.INFO)
              vim.notify("🔐 Enter password when prompted, then press Ctrl+Z to background the process", vim.log.levels.INFO)
              vim.notify("💡 Use 'bg' command to continue in background after Ctrl+Z", vim.log.levels.INFO)
              
                             -- Create a wrapper script with better backgrounding
               local wrapper_script = vim.fn.tempname() .. "_wrapper.sh"
               local wrapper_content = string.format([[#!/bin/bash
echo "🔐 Google Cloud SSH Port Forwarding"
echo "📡 Connecting to: %s"
echo "🔗 Port mapping: %s"
echo ""
echo "📋 Instructions:"
echo "  1. Enter your password when prompted"
echo "  2. After authentication succeeds, press Enter"  
echo "  3. The connection will continue in background"
echo "  4. Close this terminal with :q when ready"
echo ""
echo "🚀 Starting connection..."
echo ""

# Modified script for better backgrounding
MODIFIED_SCRIPT=$(mktemp).sh
cat > "$MODIFIED_SCRIPT" << 'SCRIPT_EOF'
#!/bin/bash
# Get project ID
PROJ_ID=$(gcloud projects list --filter labels.active=true | grep "%s " | awk '{ print $1 }')

if [ -z "$PROJ_ID" ]; then
  echo "Error: No project found with name '%s'"
  exit 1
fi

echo "Found project: $PROJ_ID"

# Get zone
zone=$(gcloud compute instances list --project $PROJ_ID --filter="Name:util-1" --format='value(zone)')

if [ -z "$zone" ]; then
  echo "Error: No util-1 instance found in project $PROJ_ID"
  exit 1
fi

echo "Found zone: $zone"
echo "Connecting with port forwarding: %s"
%s
%s
echo ""

# Build and show the final command
FINAL_CMD="%s"
echo "🚀 Executing command:"
echo "   $FINAL_CMD"
echo ""
echo "💡 Please authenticate when prompted, then the connection will stay active"
echo "📋 Instructions:"
echo "   1. Enter your password/passphrase when asked"
echo "   2. Once connected, the terminal will show connection details"
echo "   3. You can close this terminal - the connection will continue running"
echo ""

# Start the connection normally - let user manage backgrounding
echo "🔗 Starting connection..."
echo "💡 You will be prompted for authentication"
echo ""
echo "📋 To background after authentication:"
echo "   1. Enter your password when prompted (it will be hidden normally)"
echo "   2. Once connected, press Ctrl+C to stop, then run again"
echo "   3. Or keep this terminal open (connection stays active)"
echo ""

# Just run the command normally
$FINAL_CMD

# If we get here, the command completed/failed
echo ""
echo "💡 Command completed. Press Enter to close..."
read

echo ""
echo "💡 Press Enter to continue..."
read

# Clean up this script
rm -f "$MODIFIED_SCRIPT" &
SCRIPT_EOF

chmod +x "$MODIFIED_SCRIPT"
exec "$MODIFIED_SCRIPT"
]], project_name, port_mapping, project_name, project_name, port_mapping, 
    ssh_user ~= "" and ("echo \"SSH User: " .. ssh_user .. "\"") or "echo \"SSH User: (current user)\"",
    ssh_key ~= "" and ("echo \"SSH Key: " .. ssh_key .. "\"") or "echo \"SSH Key: (default google_compute_engine)\"",
    -- Build the gcloud command with conditional SSH key and user
    (function()
      local cmd = "gcloud compute ssh --zone $zone --project $PROJ_ID util-1 --ssh-flag='-A' --ssh-flag='-L' --ssh-flag='" .. port_mapping .. "'"
      
      if ssh_key ~= "" then
        -- Expand tilde to home directory
        local expanded_key = ssh_key:gsub("^~", "$HOME")
        cmd = cmd .. " --ssh-key-file=" .. expanded_key
      end
      
      if ssh_user ~= "" then
        cmd = cmd .. " --ssh-flag='-l' --ssh-flag='" .. ssh_user .. "'"
      end
      
      return cmd
    end)())
              
              local wrapper_file = io.open(wrapper_script, "w")
              if wrapper_file then
                wrapper_file:write(wrapper_content)
                wrapper_file:close()
                os.execute("chmod +x " .. wrapper_script)
                
                -- Store connection info for tracking (we'll get PID from terminal output)
                vim.g.pending_gport = {
                  project = project_name,
                  port_mapping = port_mapping,
                  user = ssh_user ~= "" and ssh_user or "current",
                  ssh_key = ssh_key ~= "" and ssh_key or "default"
                }
                
                -- Open in terminal split
                vim.cmd("split")
                vim.cmd("terminal " .. wrapper_script)
                
                -- Clean up wrapper script after a delay
                vim.defer_fn(function()
                  os.remove(wrapper_script)
                end, 30000) -- 30 seconds delay
              else
                vim.notify("❌ Failed to create wrapper script", vim.log.levels.ERROR)
              end
            else
              vim.notify("❌ Failed to create temporary script", vim.log.levels.ERROR)
            end
          end,
          nargs = "*",
          desc = "Google Cloud port forwarding",
        },

        -- Create system script
        GportInstall = {
          function()
            local script_content = [[#!/bin/bash
# Google Cloud port forwarding script
# Usage: gport <project-name> <port-mapping>
# Example: gport test 5432:localhost:5432

 function gport() {
  if [ $# -lt 1 ]; then
    echo "Usage: gport <project-name> [port-mapping] [ssh-user] [ssh-key-file]"
    echo "Example: gport test"
    echo "Example: gport test 5432:localhost:5432"
    echo "Example: gport test 5432:localhost:5432 myuser"
    echo "Example: gport test 5432:localhost:5432 myuser ~/.ssh/my_key"
    echo "Default port mapping: 5432:localhost:5432"
    echo "Default SSH user: current user"
    echo "Default SSH key: google_compute_engine"
    return 1
  fi
  
  local project_name="$1"
  local port_mapping="${2:-5432:localhost:5432}"
  local ssh_user="$3"
  local ssh_key="$4"
  
  # Get project ID
  PROJ_ID=$(gcloud projects list --filter labels.active=true | grep "${project_name} " | awk '{ print $1 }')
  
  if [ -z "$PROJ_ID" ]; then
    echo "Error: No project found with name '${project_name}'"
    return 1
  fi
  
  echo "Found project: $PROJ_ID"
  
  # Get zone
  zone=$(gcloud compute instances list --project ${PROJ_ID} --filter="Name:util-1" --format='value(zone)')
  
  if [ -z "$zone" ]; then
    echo "Error: No util-1 instance found in project $PROJ_ID"
    return 1
  fi
  
  echo "Found zone: $zone"
  echo "Connecting with port forwarding: $port_mapping"
  [ -n "$ssh_user" ] && echo "SSH User: $ssh_user" || echo "SSH User: (current user)"
  [ -n "$ssh_key" ] && echo "SSH Key: $ssh_key" || echo "SSH Key: (default google_compute_engine)"
  echo ""
  
  # Build gcloud command with conditional SSH key and user
  cmd="gcloud compute ssh --zone ${zone} --project ${PROJ_ID} util-1 --ssh-flag='-A' --ssh-flag='-T' --ssh-flag='-L' --ssh-flag='$port_mapping'"
  
  if [ -n "$ssh_key" ]; then
    # Expand tilde to home directory if present
    expanded_key="${ssh_key/#\~/$HOME}"
    cmd="$cmd --ssh-key-file=$expanded_key"
  fi
  
  if [ -n "$ssh_user" ]; then
    cmd="$cmd --ssh-flag='-l' --ssh-flag='$ssh_user'"
  fi
  
  # Show the final command
  echo "🚀 Executing command:"
  echo "   $cmd"
  echo ""
  
  # Execute the command
  eval "$cmd"
}

# Call the function with all arguments
gport "$@"
]]

            -- Write script to ~/.local/bin/gport
            local script_path = vim.fn.expand "~/.local/bin/gport"
            local file = io.open(script_path, "w")
            if file then
              file:write(script_content)
              file:close()

              -- Make executable
              os.execute("chmod +x " .. script_path)

              vim.notify("✅ gport script installed to: " .. script_path, vim.log.levels.INFO)
              vim.notify("💡 Make sure ~/.local/bin is in your PATH", vim.log.levels.INFO)
              vim.notify("🚀 You can now use: gport test 5432:localhost:5432", vim.log.levels.INFO)
            else
              vim.notify("❌ Failed to create script at: " .. script_path, vim.log.levels.ERROR)
            end
          end,
          desc = "Install gport script to system PATH",
        },
        
        -- Status and management commands
        GportStatus = {
          function()
            update_gport_status()
            local count = vim.g.gport_count or 0
            
            if count == 0 then
              vim.notify("📡 No gport processes running", vim.log.levels.INFO)
              return
            end
            
            vim.notify("📡 Active gport processes: " .. count, vim.log.levels.INFO)
            
            for pid, info in pairs(_G.gport_processes) do
              local duration = os.time() - info.started
              local hours = math.floor(duration / 3600)
              local minutes = math.floor((duration % 3600) / 60)
              local time_str = string.format("%02d:%02d", hours, minutes)
              
              vim.notify(string.format("  🔗 PID:%s | %s -> %s | User:%s | Key:%s | Time:%s", 
                pid, info.project, info.port_mapping, info.user, info.ssh_key or "default", time_str), vim.log.levels.INFO)
            end
          end,
          desc = "Show running gport processes",
        },
        
        GportKill = {
          function(opts)
            local args = opts.fargs
            if #args < 1 then
              vim.notify("Usage: :GportKill <pid|all>", vim.log.levels.ERROR)
              vim.notify("Example: :GportKill 12345", vim.log.levels.INFO)
              vim.notify("Example: :GportKill all", vim.log.levels.INFO)
              return
            end
            
            local target = args[1]
            
            if target == "all" then
              local count = 0
              for pid, info in pairs(_G.gport_processes) do
                os.execute("kill " .. pid)
                count = count + 1
              end
              _G.gport_processes = {}
              vim.g.gport_count = 0
              vim.notify("🛑 Killed " .. count .. " gport processes", vim.log.levels.INFO)
            else
              local pid = tonumber(target)
              if pid and _G.gport_processes[pid] then
                os.execute("kill " .. pid)
                _G.gport_processes[pid] = nil
                vim.notify("🛑 Killed gport process " .. pid, vim.log.levels.INFO)
                update_gport_status()
              else
                vim.notify("❌ Process " .. target .. " not found", vim.log.levels.ERROR)
              end
            end
          end,
          nargs = 1,
          desc = "Kill gport process(es)",
        },
        
        -- Foreground/interaction commands
        GportLogs = {
          function(opts)
            local args = opts.fargs
            if #args < 1 then
              vim.notify("Usage: :GportLogs <pid>", vim.log.levels.ERROR)
              vim.notify("Example: :GportLogs 12345", vim.log.levels.INFO)
              return
            end
            
            local pid = tonumber(args[1])
            if not (pid and _G.gport_processes[pid]) then
              vim.notify("❌ Process " .. args[1] .. " not found", vim.log.levels.ERROR)
              return
            end
            
            local log_file = "/tmp/gcloud_port_forward_" .. pid .. ".log"
            
            -- Check if log file exists
            local file = io.open(log_file, "r")
            if not file then
              vim.notify("❌ Log file not found: " .. log_file, vim.log.levels.ERROR)
              return
            end
            file:close()
            
            vim.notify("📋 Opening logs for PID " .. pid, vim.log.levels.INFO)
            
            -- Open in split and tail the log file
            vim.cmd("split")
            vim.cmd("terminal tail -f " .. log_file)
          end,
          nargs = 1,
          desc = "View gport process logs",
        },
        
        GportReconnect = {
          function(opts)
            local args = opts.fargs
            if #args < 1 then
              vim.notify("Usage: :GportReconnect <pid>", vim.log.levels.ERROR)
              vim.notify("Example: :GportReconnect 12345", vim.log.levels.INFO)
              return
            end
            
            local pid = tonumber(args[1])
            if not (pid and _G.gport_processes[pid]) then
              vim.notify("❌ Process " .. args[1] .. " not found", vim.log.levels.ERROR)
              return
            end
            
            local info = _G.gport_processes[pid]
            vim.notify("🔄 Reconnecting to: " .. info.project .. " -> " .. info.port_mapping, vim.log.levels.INFO)
            
            -- Create a reconnection script
            local reconnect_script = vim.fn.tempname() .. "_reconnect.sh"
            local reconnect_content = string.format([[#!/bin/bash
echo "🔄 Reconnecting to existing gport session"
echo "📡 Project: %s"
echo "🔗 Port mapping: %s"
echo "👤 User: %s"
echo "🆔 Original PID: %s"
echo ""
echo "📋 Options:"
echo "  1. View connection logs (tail -f /tmp/gcloud_port_forward_%s.log)"
echo "  2. Test connection (netstat -tulpn | grep %s)"
echo "  3. Create new parallel connection"
echo "  4. Exit"
echo ""

while true; do
  read -p "Choose option (1-4): " choice
  case $choice in
    1)
      echo "📋 Showing logs (Ctrl+C to exit)..."
      tail -f /tmp/gcloud_port_forward_%s.log
      break
      ;;
    2)
      echo "🔍 Testing connection..."
      echo "Port listening status:"
      netstat -tulpn | grep %s || echo "No local port found listening"
      echo ""
      echo "Process status:"
      ps aux | grep %s | grep -v grep || echo "Process not found in ps"
      echo ""
      ;;
    3)
      echo "🚀 Creating new parallel connection..."
      echo "Command to execute:"
      echo "   %s"
      echo ""
      # Re-run the original command (user will need to re-auth)
      %s
      break
      ;;
    4)
      echo "👋 Exiting..."
      break
      ;;
    *)
      echo "❌ Invalid option. Please choose 1-4."
      ;;
  esac
done

echo "Press Enter to close..."
read
]], info.project, info.port_mapping, info.user, pid, pid, 
    info.port_mapping:match("^(%d+)"), -- Extract local port
    pid, info.port_mapping:match("^(%d+)"), pid,
    -- Reconstruct the original gcloud command (for display)
    (function()
      local cmd_base = string.format("gcloud compute ssh --zone $(gcloud compute instances list --project $(gcloud projects list --filter labels.active=true | grep '%s ' | awk '{ print $1 }') --filter='Name:util-1' --format='value(zone)') --project $(gcloud projects list --filter labels.active=true | grep '%s ' | awk '{ print $1 }') util-1 --ssh-flag='-A' --ssh-flag='-T' --ssh-flag='-L' --ssh-flag='%s'", info.project, info.project, info.port_mapping)
      
      if info.ssh_key and info.ssh_key ~= "default" then
        local expanded_key = info.ssh_key:gsub("^~", "$HOME")
        cmd_base = cmd_base .. " --ssh-key-file=" .. expanded_key
      end
      
      if info.user and info.user ~= "current" then
        cmd_base = cmd_base .. " --ssh-flag='-l' --ssh-flag='" .. info.user .. "'"
      end
      
      return cmd_base
    end)(),
    -- Reconstruct the original gcloud command (for execution)
    (function()
      local cmd_base = string.format("gcloud compute ssh --zone $(gcloud compute instances list --project $(gcloud projects list --filter labels.active=true | grep '%s ' | awk '{ print $1 }') --filter='Name:util-1' --format='value(zone)') --project $(gcloud projects list --filter labels.active=true | grep '%s ' | awk '{ print $1 }') util-1 --ssh-flag='-A' --ssh-flag='-T' --ssh-flag='-L' --ssh-flag='%s'", info.project, info.project, info.port_mapping)
      
      if info.ssh_key and info.ssh_key ~= "default" then
        local expanded_key = info.ssh_key:gsub("^~", "$HOME")
        cmd_base = cmd_base .. " --ssh-key-file=" .. expanded_key
      end
      
      if info.user and info.user ~= "current" then
        cmd_base = cmd_base .. " --ssh-flag='-l' --ssh-flag='" .. info.user .. "'"
      end
      
      return cmd_base
    end)()
)
            
            local reconnect_file = io.open(reconnect_script, "w")
            if reconnect_file then
              reconnect_file:write(reconnect_content)
              reconnect_file:close()
              os.execute("chmod +x " .. reconnect_script)
              
              -- Open in terminal split
              vim.cmd("split")
              vim.cmd("terminal " .. reconnect_script)
              
              -- Clean up after delay
              vim.defer_fn(function()
                os.remove(reconnect_script)
              end, 60000)
            else
              vim.notify("❌ Failed to create reconnection script", vim.log.levels.ERROR)
            end
          end,
          nargs = 1,
          desc = "Reconnect to gport session",
        },
        
        GportTest = {
          function(opts)
            local args = opts.fargs
            if #args < 1 then
              vim.notify("Usage: :GportTest <pid>", vim.log.levels.ERROR)
              return
            end
            
            local pid = tonumber(args[1])
            if not (pid and _G.gport_processes[pid]) then
              vim.notify("❌ Process " .. args[1] .. " not found", vim.log.levels.ERROR)
              return
            end
            
            local info = _G.gport_processes[pid]
            local local_port = info.port_mapping:match("^(%d+)")
            
            vim.notify("🧪 Testing connection for PID " .. pid, vim.log.levels.INFO)
            
            -- Test if process is running
            local handle = vim.loop.spawn("kill", {
              args = { "-0", tostring(pid) },
            }, function(code, signal)
              if code == 0 then
                vim.notify("✅ Process " .. pid .. " is running", vim.log.levels.INFO)
              else
                vim.notify("❌ Process " .. pid .. " is not running", vim.log.levels.WARN)
                _G.gport_processes[pid] = nil
                update_gport_status()
              end
            end)
            
            -- Test if port is listening
            if local_port then
              local port_handle = vim.loop.spawn("netstat", {
                args = { "-tulpn" },
              }, function(code, signal)
                -- This will be handled in on_stdout
              end)
              
              if port_handle then
                port_handle:read_start(function(err, data)
                  if data and data:find(":" .. local_port .. " ") then
                    vim.notify("✅ Port " .. local_port .. " is listening", vim.log.levels.INFO)
                  else
                    vim.notify("⚠️ Port " .. local_port .. " not found listening", vim.log.levels.WARN)
                  end
                end)
              end
            end
          end,
          nargs = 1,
          desc = "Test gport connection",
        },
        
        -- Alternative background command
        GportBg = {
          function(opts)
            local args = opts.fargs
            if #args < 1 then
              vim.notify("Usage: :GportBg <project-name> [port-mapping] [ssh-user] [ssh-key-file]", vim.log.levels.ERROR)
              vim.notify("This version runs in foreground for authentication, then you can close terminal", vim.log.levels.INFO)
              return
            end
            
            local project_name = args[1]
            local port_mapping = args[2] or "5432:localhost:5432"
            local ssh_user = args[3] or ""
            local ssh_key = args[4] or ""
            
            -- Create a simple foreground script
            local simple_script = vim.fn.tempname() .. ".sh"
            local script_content = string.format([[#!/bin/bash
echo "🔐 Google Cloud SSH Port Forwarding"
echo "📡 Connecting to: %s"
echo "🔗 Port mapping: %s"
%s
%s
echo ""

# Get project ID
PROJ_ID=$(gcloud projects list --filter labels.active=true | grep "%s " | awk '{ print $1 }')

if [ -z "$PROJ_ID" ]; then
  echo "Error: No project found with name '%s'"
  exit 1
fi

echo "Found project: $PROJ_ID"

# Get zone
zone=$(gcloud compute instances list --project $PROJ_ID --filter="Name:util-1" --format='value(zone)')

if [ -z "$zone" ]; then
  echo "Error: No util-1 instance found in project $PROJ_ID"
  exit 1
fi

echo "Found zone: $zone"
echo "Connecting with port forwarding: %s"
echo ""

# Build the gcloud command
%s

echo "🚀 Executing command:"
echo "   $FINAL_CMD"
echo ""
echo "💡 Authenticating and connecting..."
echo "💡 After connection is established, you can close this terminal"
echo "💡 The port forwarding will continue running"
echo ""

# Run the command
exec $FINAL_CMD
]], project_name, port_mapping,
    ssh_user ~= "" and ("echo \"SSH User: " .. ssh_user .. "\"") or "echo \"SSH User: (current user)\"",
    ssh_key ~= "" and ("echo \"SSH Key: " .. ssh_key .. "\"") or "echo \"SSH Key: (default google_compute_engine)\"",
    project_name, project_name, port_mapping,
         -- Build command same as before
     (function()
       local cmd = "FINAL_CMD=\"gcloud compute ssh --zone $zone --project $PROJ_ID util-1 --ssh-flag='-A' --ssh-flag='-L' --ssh-flag='" .. port_mapping .. "'"
       
       if ssh_key ~= "" then
         -- Expand tilde to home directory
         local expanded_key = ssh_key:gsub("^~", "$HOME")
         cmd = cmd .. " --ssh-key-file=" .. expanded_key
       end
       
       if ssh_user ~= "" then
         cmd = cmd .. " --ssh-flag='-l' --ssh-flag='" .. ssh_user .. "'"
       end
       
       return cmd .. "\""
     end)())
            
            local file = io.open(simple_script, "w")
            if file then
              file:write(script_content)
              file:close()
              os.execute("chmod +x " .. simple_script)
              
              -- Store for tracking
              vim.g.pending_gport = {
                project = project_name,
                port_mapping = port_mapping,
                user = ssh_user ~= "" and ssh_user or "current",
                ssh_key = ssh_key ~= "" and ssh_key or "default"
              }
              
              -- Open in terminal split
              vim.cmd("split")
              vim.cmd("terminal " .. simple_script)
              
              -- Clean up after delay
              vim.defer_fn(function()
                os.remove(simple_script)
              end, 30000)
            else
              vim.notify("❌ Failed to create script", vim.log.levels.ERROR)
            end
          end,
          nargs = "*",
          desc = "Google Cloud port forward (background-friendly)",
        },
      },

            -- Keybindings
      mappings = {
        n = {
          ["<leader>G"] = { name = "󰊭 Google Cloud" },
          ["<leader>Gp"] = { 
            function()
              vim.ui.input({ prompt = "Project name: " }, function(project)
                if not project then return end
                vim.ui.input({ 
                  prompt = "Port mapping (default: 5432:localhost:5432): ",
                  default = "5432:localhost:5432",
                }, function(port)
                  if not port or port == "" then port = "5432:localhost:5432" end
                  vim.ui.input({
                    prompt = "SSH user (optional): ",
                  }, function(user)
                    vim.ui.input({
                      prompt = "SSH key file (optional, e.g., ~/.ssh/my_key): ",
                    }, function(key)
                      local cmd = "Gport " .. project .. " " .. port
                      if user and user ~= "" then
                        cmd = cmd .. " " .. user
                      else
                        cmd = cmd .. " ''"  -- Empty user placeholder
                      end
                      if key and key ~= "" then
                        cmd = cmd .. " " .. key
                      end
                      vim.cmd(cmd)
                    end)
                  end)
                end)
              end)
            end, 
            desc = "Google Cloud port forward",
          },
          ["<leader>Gi"] = { "<cmd>GportInstall<cr>", desc = "Install gport script" },
          ["<leader>Gs"] = { "<cmd>GportStatus<cr>", desc = "Show gport status" },
          ["<leader>Gk"] = { 
            function()
              vim.ui.input({ prompt = "Kill PID (or 'all'): " }, function(pid)
                if pid and pid ~= "" then
                  vim.cmd("GportKill " .. pid)
                end
              end)
            end, 
            desc = "Kill gport process" 
          },
          ["<leader>Gl"] = { 
            function()
              vim.ui.input({ prompt = "View logs for PID: " }, function(pid)
                if pid and pid ~= "" then
                  vim.cmd("GportLogs " .. pid)
                end
              end)
            end, 
            desc = "View gport logs" 
          },
          ["<leader>Gr"] = { 
            function()
              vim.ui.input({ prompt = "Reconnect to PID: " }, function(pid)
                if pid and pid ~= "" then
                  vim.cmd("GportReconnect " .. pid)
                end
              end)
            end, 
            desc = "Reconnect to gport" 
          },
          ["<leader>Gt"] = { 
            function()
              vim.ui.input({ prompt = "Test PID: " }, function(pid)
                if pid and pid ~= "" then
                  vim.cmd("GportTest " .. pid)
                end
              end)
            end, 
            desc = "Test gport connection" 
          },
          ["<leader>Gb"] = { 
            function()
              vim.ui.input({ prompt = "Project name: " }, function(project)
                if not project then return end
                vim.ui.input({ 
                  prompt = "Port mapping (default: 5432:localhost:5432): ",
                  default = "5432:localhost:5432",
                }, function(port)
                  if not port or port == "" then port = "5432:localhost:5432" end
                  vim.ui.input({
                    prompt = "SSH user (optional): ",
                  }, function(user)
                    vim.ui.input({
                      prompt = "SSH key file (optional): ",
                    }, function(key)
                      local cmd = "GportBg " .. project .. " " .. port
                      if user and user ~= "" then
                        cmd = cmd .. " " .. user
                      else
                        cmd = cmd .. " ''"
                      end
                      if key and key ~= "" then
                        cmd = cmd .. " " .. key
                      end
                      vim.cmd(cmd)
                    end)
                  end)
                end)
              end)
            end, 
            desc = "Google Cloud port forward (simple background)" 
          },
        },
      },
      
      -- Autocommands
      autocmds = {
        gport_tracking = {
          {
            event = "TermClose",
            callback = function()
              -- Check if there's a pending gport and PID file
              if vim.g.pending_gport then
                local pid_file = "/tmp/gport_pid_latest.txt"
                local file = io.open(pid_file, "r")
                if file then
                  local pid = tonumber(file:read("*line"))
                  file:close()
                  
                  if pid then
                    -- Track the process
                    track_gport_process(pid, vim.g.pending_gport.project, 
                      vim.g.pending_gport.port_mapping, vim.g.pending_gport.user, vim.g.pending_gport.ssh_key)
                    
                    vim.notify("📡 Gport tracked: PID " .. pid .. " (" .. vim.g.pending_gport.project .. ")", vim.log.levels.INFO)
                    
                    -- Clean up
                    os.remove(pid_file)
                  end
                end
                vim.g.pending_gport = nil
              end
            end,
          },
        },
      },
    },
  },
}
