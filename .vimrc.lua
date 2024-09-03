local dap = require('dap')
local vim = vim

local debug_config = {
    type = "dart",
    request = "launch",
    name = "Launch Flutter Program",
    -- The nvim-dap plugin populates this variable with the filename of the current buffer
    program = "${workspaceFolder}/lib/main.dart",
    -- The nvim-dap plugin populates this variable with the editor's current working directory
    cwd = "${workspaceFolder}",
    -- This gets forwarded to the Flutter CLI tool, substitute `linux` for whatever device you wish to launch
    toolArgs = { "-d", "linux" }
}


vim.keymap.set('n', '<F5>', function()
    dap.run(debug_config)
    dap.repl.open()
end)
