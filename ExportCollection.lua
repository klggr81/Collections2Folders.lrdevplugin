local LrExportSession = import 'LrExportSession'

local Utils = require 'Utils'

-- Exports one collection into its mirrored folder and returns the photo count.
-- Must run on a task, since it drives the export session on the current one.
local function exportCollection(collection, rootPath, exportSettings)
  local photos = collection:getPhotos()
  if #photos == 0 then
    return 0
  end

  local outputPath = Utils.collectionDestination(collection, rootPath)

  local settings = {}
  for key, value in pairs(exportSettings or {}) do
    settings[key] = value
  end

  -- The preset's own destination is whatever the user last exported to,
  -- so override it rather than inherit it.
  settings.LR_export_destinationType = 'specificFolder'
  settings.LR_export_destinationPathPrefix = outputPath
  settings.LR_export_destinationPathSuffix = ''
  settings.LR_export_useSubfolder = false
  settings.LR_export_useParentFolder = false

  if settings.LR_exportServiceProvider == nil then
    settings.LR_exportServiceProvider = 'com.adobe.ag.export.file'
    settings.LR_exportServiceProviderTitle = 'Hard Drive'
  end

  local session = LrExportSession({
    photosToExport = photos,
    exportSettings = settings,
  })
  session:doExportOnCurrentTask()

  return #photos
end

return {
  exportCollection = exportCollection,
}
