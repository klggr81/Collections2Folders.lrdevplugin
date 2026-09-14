local LrDialogs = import 'LrDialogs'

-- Report anything that goes wrong before the dialog's own handler is armed,
-- so a failure here is never silent.
local ok, err = pcall(function()
  local ExportDialog = require 'ExportDialog'
  ExportDialog.show {
    title = 'Export collections to folders',
    selectAll = true,
  }
end)

if not ok then
  LrDialogs.message('Collections2Folders could not start', tostring(err), 'critical')
end
