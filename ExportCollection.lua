local LrExportSession = import 'LrExportSession'

local PhotoFilter = require 'PhotoFilter'
local Utils = require 'Utils'

local ExportCollection = {}

-- Photos per export session. A cancel lets the current chunk finish, so
-- this bounds how long a cancel takes; smaller chunks give Lightroom fewer
-- photos to render in parallel.
local CHUNK_SIZE = 5

-- Image # and Total # count photos within one export session and cannot be
-- carried across chunks the way the sequence number can, so a preset that
-- renames with them has to export each collection in one session.
local function countsWithinSession(settings)
  local tokens = settings.LR_tokens
  if not settings.LR_renamingTokensOn or type(tokens) ~= 'string' then
    return false
  end
  tokens = tokens:lower()
  return tokens:find('imagenumber', 1, true) ~= nil
    or tokens:find('total', 1, true) ~= nil
end

local function buildSettings(exportSettings, outputPath, collisionHandling)
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

  if collisionHandling then
    settings.LR_collisionHandling = collisionHandling
  end

  if settings.LR_exportServiceProvider == nil then
    settings.LR_exportServiceProvider = 'com.adobe.ag.export.file'
    settings.LR_exportServiceProviderTitle = 'Hard Drive'
  end

  return settings
end

-- Works out what each collection will export, where it goes and what is
-- already there, before anything is written. Collections left without
-- photos are dropped. Returns the jobs and how many were dropped, or nil
-- if the user cancels. Must run on a task.
function ExportCollection.plan(collections, rootPath, criteria, progress)
  local jobs, empty = {}, 0

  for index, collection in ipairs(collections) do
    if progress:isCanceled() then
      return nil
    end
    local name = collection:getName()
    progress:setCaption(string.format('Checking destination folders: %s (%d of %d)',
      name, index, #collections))
    progress:setPortionComplete(index - 1, #collections)

    local photos = PhotoFilter.apply(collection:getPhotos(), criteria)
    if #photos == 0 then
      empty = empty + 1
    else
      local path, parts = Utils.collectionPath(collection, rootPath)
      jobs[#jobs + 1] = {
        name = name,
        label = table.concat(parts, ' / '),
        photos = photos,
        path = path,
        existingFiles = Utils.filesIn(path),
      }
    end
  end

  return jobs, empty
end

-- Exports one planned job into its folder. Returns the number of photos
-- written, the number skipped or failed, and whether a cancel left part of
-- the collection unexported. Must run on a task.
--
-- An export session cannot be stopped once it starts: Lightroom queues every
-- photo for rendering at once and finishes them in the background whatever
-- the plugin does. So the photos go out in small sessions, and a cancel
-- takes effect when the current one is done.
function ExportCollection.export(job, exportSettings, collisionHandling, progress, onPhotoDone)
  local base = buildSettings(exportSettings, Utils.createFolder(job.path), collisionHandling)
  local chunkSize = countsWithinSession(base) and #job.photos or CHUNK_SIZE
  local firstNumber = tonumber(base.LR_initialSequenceNumber) or 1

  local written, failed = 0, 0
  for first = 1, #job.photos, chunkSize do
    if progress:isCanceled() then
      return written, failed, true
    end

    local chunk = {}
    for index = first, math.min(first + chunkSize - 1, #job.photos) do
      chunk[#chunk + 1] = job.photos[index]
    end

    -- Each session restarts the sequence number, so carry it on from the
    -- previous chunk to keep the numbering running through the collection.
    local settings = {}
    for key, value in pairs(base) do
      settings[key] = value
    end
    settings.LR_initialSequenceNumber = firstNumber + first - 1

    local session = LrExportSession({
      photosToExport = chunk,
      exportSettings = settings,
    })
    for _, rendition in session:renditions() do
      if rendition:waitForRender() then
        written = written + 1
      else
        failed = failed + 1
      end
      onPhotoDone()
    end
  end

  return written, failed, false
end

return ExportCollection
