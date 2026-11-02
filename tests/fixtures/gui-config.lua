local wezterm = require 'wezterm'
local run = @RUN@
local nonce = @NONCE@
local appearance_written = false
local serial = 0
wezterm.on('format-window-title', function() return 'MAVERGREEN-' .. nonce end)
wezterm.on('update-status', function(window, pane)
  if not appearance_written then
    local f = assert(io.open(run .. '/appearance.txt', 'w'))
    f:write(window:get_appearance(), '\n')
    f:close()
    appearance_written = true
  end
  local f = io.open(run .. '/command', 'r')
  if not f then return end
  local command = f:read('*l')
  f:close()
  os.remove(run .. '/command')
  serial = serial + 1
  local timeout = command == 'expire' and 3000 or 20000
  local request = assert(io.open(run .. '/requested.txt', 'a'))
  request:write(command, ' ', nonce, ' ', tostring(serial), '\n')
  request:close()
  window:toast_notification('MAVERGREEN ' .. nonce .. ' ' .. tostring(serial),
    command == 'expire' and 'Three-second expiry test. No URL.' or 'Click this test banner. No URL will open.', nil, timeout)
end)
return {
  front_end = 'OpenGL',
  check_for_updates = false,
  automatically_reload_config = false,
  enable_tab_bar = false,
  initial_cols = 88,
  initial_rows = 24,
  font_size = 14,
  status_update_interval = 500,
  quit_when_all_windows_are_closed = true,
  window_decorations = 'TITLE|RESIZE|MACOS_USE_BACKGROUND_COLOR_AS_TITLEBAR_COLOR',
  default_prog = {'/bin/sh', @SHELL@, run, nonce, @MODE@},
}
