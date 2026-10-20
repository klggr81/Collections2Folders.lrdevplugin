local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local CollectionTree = require 'CollectionTree'
local ConflictDialog = require 'ConflictDialog'
local ExportCollection = require 'ExportCollection'
local PhotoFilter = require 'PhotoFilter'
local Utils = require 'Utils'

local ExportDialog = {}

local NO_PRESET = ''
local INDENT_WIDTH = 18

local function buildPresetItems()
  local items = {
    { title = 'Lightroom defaults (no preset)', value = NO_PRESET },
  }

  -- Scanning the preset folders yields, so a plain pcall would trip the
  -- "yielding is not allowed" guard.
  local ok, presets = LrTasks.pcall(Utils.getExportPresets)
  if not ok or type(presets) ~= 'table' then
    return items
  end

  for _, preset in ipairs(presets) do
    items[#items + 1] = {
      title = preset.group .. ' / ' .. preset.title,
      value = preset.value,
    }
  end
  return items
end

-- Returns the argument table for f:column, with one row per node.
local function buildList(f, nodes)
  local rows = { spacing = 2 }

  for _, node in ipairs(nodes) do
    local control
    if node.kind == 'set' then
      control = f:static_text {
        title = node.name,
        font = '<system/bold/small>',
      }
    elseif node.smart then
      control = f:checkbox {
        title = node.name .. '  (smart)',
        value = LrView.bind(node.key),
        enabled = LrView.bind('includeSmart'),
      }
    else
      control = f:checkbox {
        title = node.name,
        value = LrView.bind(node.key),
      }
    end

    if node.depth > 0 then
      rows[#rows + 1] = f:row {
        spacing = 0,
        f:spacer { width = node.depth * INDENT_WIDTH },
        control,
      }
    else
      rows[#rows + 1] = control
    end
  end

  return rows
end

-- A criterion's controls are live only while filtering is on, and its
-- value controls only while the criterion itself is ticked too.
local function whenFiltering(key)
  if not key then
    return LrView.bind {
      key = 'photoFilter',
      transform = function(value) return value == 'filtered' end,
    }
  end
  return LrView.bind {
    keys = { 'photoFilter', key },
    operation = function(_, values)
      return values.photoFilter == 'filtered' and values[key] == true
    end,
  }
end

local function buildFilterBox(f)
  local labelWidth = LrView.share('criterionLabel')

  local colorBoxes = { spacing = f:label_spacing() }
  for _, color in ipairs(PhotoFilter.COLORS) do
    colorBoxes[#colorBoxes + 1] = f:checkbox {
      title = color.title,
      value = LrView.bind('color_' .. color.key),
      enabled = whenFiltering('useColor'),
    }
  end

  local function criterion(title, key, ...)
    return f:row {
      f:spacer { width = INDENT_WIDTH },
      f:checkbox {
        title = title,
        value = LrView.bind(key),
        enabled = whenFiltering(),
        width = labelWidth,
      },
      ...
    }
  end

  return f:group_box {
    title = 'Photos to export',
    fill_horizontal = 1,

    f:row {
      f:radio_button {
        title = 'All photos',
        value = LrView.bind('photoFilter'),
        checked_value = 'all',
      },
      f:radio_button {
        title = 'Only photos matching',
        value = LrView.bind('photoFilter'),
        checked_value = 'filtered',
      },
      f:popup_menu {
        value = LrView.bind('matchMode'),
        items = {
          { title = 'all of', value = 'all' },
          { title = 'any of', value = 'any' },
        },
        enabled = whenFiltering(),
      },
      f:static_text { title = 'these:' },
    },

    criterion('Flag:', 'useFlag',
      f:popup_menu {
        value = LrView.bind('flag'),
        items = PhotoFilter.FLAG_ITEMS,
        enabled = whenFiltering('useFlag'),
      }),

    criterion('Rating:', 'useRating',
      f:popup_menu {
        value = LrView.bind('ratingOp'),
        items = PhotoFilter.RATING_OP_ITEMS,
        enabled = whenFiltering('useRating'),
      },
      f:popup_menu {
        value = LrView.bind('rating'),
        items = PhotoFilter.RATING_ITEMS,
        enabled = whenFiltering('useRating'),
      }),

    criterion('Color label:', 'useColor', f:row(colorBoxes)),
  }
end

local function runExport(context, properties, selected, criteria)
  local exportSettings, err = Utils.loadExportSettings(properties.presetPath)
  if err then
    LrDialogs.message('Collections2Folders',
      'The export preset could not be read, so Lightroom defaults were used.\n\n' .. err,
      'warning')
  end

  -- One progress window serves the whole run. Lightroom only closes a
  -- modal progress dialog when its function context ends, so a separate
  -- one for the destination check would linger behind the export.
  local progress = LrDialogs.showModalProgressDialog {
    title = 'Exporting collections',
    caption = 'Checking destination folders',
    cannotCancel = false,
    functionContext = context,
  }

  -- Look at the destination before writing anything, so the user can
  -- decide what happens to files that are already there.
  local jobs, emptyCount = ExportCollection.plan(selected, properties.rootPath, criteria, progress)
  if not jobs then
    progress:done()
    return
  end

  if #jobs == 0 then
    progress:done()
    LrDialogs.message('Collections2Folders',
      'Nothing to export: the selected collections are empty, or no photo matches the filter.',
      'info')
    return
  end

  local conflicts = {}
  for _, job in ipairs(jobs) do
    if #job.existingFiles > 0 then
      conflicts[#conflicts + 1] = job
    end
  end

  local choice
  if #conflicts > 0 then
    progress:setCaption('Waiting for your choice about existing files')
    choice = ConflictDialog.ask(conflicts, #jobs)
    if not choice then
      progress:done()
      return
    end
  end

  local skippedCollections = 0
  if choice == 'skipCollections' then
    local remaining = {}
    for _, job in ipairs(jobs) do
      if #job.existingFiles == 0 then
        remaining[#remaining + 1] = job
      end
    end
    skippedCollections = #jobs - #remaining
    jobs = remaining
  elseif choice == 'emptyFolders' then
    -- Two collections can share a folder, so collect each file once.
    local files, seen = {}, {}
    for _, job in ipairs(conflicts) do
      for _, file in ipairs(job.existingFiles) do
        if not seen[file] then
          seen[file] = true
          files[#files + 1] = file
        end
      end
    end

    progress:setCaption(string.format('Moving %d existing files to the %s',
      #files, WIN_ENV and 'Recycle Bin' or 'Trash'))
    local failed = Utils.moveToTrash(files)
    if #failed > 0 then
      progress:done()
      LrDialogs.message('Collections2Folders',
        string.format('%d existing files could not be moved to the %s, so nothing was exported. '
          .. 'The first one was:\n\n%s', #failed, WIN_ENV and 'Recycle Bin' or 'Trash', failed[1]),
        'critical')
      return
    end
  end

  local collisionHandling = ConflictDialog.collisionHandling(choice)

  local totalPhotos = 0
  for _, job in ipairs(jobs) do
    totalPhotos = totalPhotos + #job.photos
  end

  local written, failed, processed, done = 0, 0, 0, 0
  local currentJob, currentIndex

  local function showProgress()
    progress:setPortionComplete(processed, totalPhotos)
    if progress:isCanceled() then
      progress:setCaption('Canceling: finishing the photos Lightroom has already started')
      return
    end
    progress:setCaption(string.format('%s (collection %d of %d)  -  %d of %d photos left',
      currentJob.name, currentIndex, #jobs, totalPhotos - processed, totalPhotos))
  end

  local function photoDone()
    processed = processed + 1
    showProgress()
  end

  local canceled, partial = false, nil
  for index, job in ipairs(jobs) do
    if progress:isCanceled() then
      canceled = true
      break
    end
    currentJob, currentIndex = job, index
    showProgress()

    local jobWritten, jobFailed, jobCanceled = ExportCollection.export(
      job, exportSettings, collisionHandling, progress, photoDone)
    written = written + jobWritten
    failed = failed + jobFailed

    if jobCanceled then
      partial = { job = job, processed = jobWritten + jobFailed }
    else
      done = done + 1
    end
    if progress:isCanceled() then
      canceled = true
      break
    end
  end

  progress:done()

  local lines = {}
  if canceled then
    lines[#lines + 1] = string.format('Export canceled after %d of %d photos.',
      processed, totalPhotos)
    lines[#lines + 1] = string.format('Exported %d photos. Collections finished: %d of %d.',
      written, done, #jobs)
    if partial then
      lines[#lines + 1] = string.format('Stopped partway: %s (%d of %d photos).',
        partial.job.label, partial.processed, #partial.job.photos)
    end
    local notStarted = #jobs - done - (partial and 1 or 0)
    if notStarted > 0 then
      lines[#lines + 1] = string.format('Not started: %d collections.', notStarted)
    end
  else
    lines[#lines + 1] = string.format('Exported %d photos from %d collections.',
      written, done)
  end
  if failed > 0 then
    lines[#lines + 1] = string.format('%d photos were skipped or could not be exported.', failed)
  end
  if skippedCollections > 0 then
    lines[#lines + 1] = string.format(
      '%d collections were skipped because their folder already contained files.',
      skippedCollections)
  end
  if emptyCount > 0 then
    lines[#lines + 1] = string.format('%d collections had no photos to export.', emptyCount)
  end

  -- Shown from a new task so this one can end first, which is what closes
  -- the progress window behind the summary.
  LrTasks.startAsyncTask(function()
    LrDialogs.message('Collections2Folders', table.concat(lines, '\n'), 'info')
  end)
end

-- options.title      dialog title
-- options.selectAll  whether every collection starts checked
function ExportDialog.show(options)
  options = options or {}

  -- The dialog is populated from the catalog, which can only be read on a
  -- task. Starting the task here keeps the function context (and with it the
  -- property table the checkboxes bind to) alive for the whole dialog.
  LrFunctionContext.postAsyncTaskWithContext('Collections2Folders', function(context)
    -- Without this an error in here kills the task quietly and no window
    -- ever opens.
    context:addFailureHandler(function(_, message)
      -- Reporting on its own task, since the handler itself may run where
      -- yielding is refused.
      LrTasks.startAsyncTask(function()
        LrDialogs.message('Collections2Folders stopped',
          tostring(message), 'critical')
      end)
    end)

    local catalog = LrApplication.activeCatalog()
    local nodes = CollectionTree.flatten(catalog)

    local collectionNodes = {}
    for _, node in ipairs(nodes) do
      if node.kind == 'collection' then
        collectionNodes[#collectionNodes + 1] = node
      end
    end

    if #collectionNodes == 0 then
      LrDialogs.message('Collections2Folders',
        'This catalog has no collections to export.',
        'info')
      return
    end

    local f = LrView.osFactory()
    local properties = LrBinding.makePropertyTable(context)
    properties.rootPath = ''
    properties.presetPath = NO_PRESET
    properties.presetItems = buildPresetItems()
    properties.includeSmart = true

    properties.photoFilter = 'all'
    properties.matchMode = 'all'
    properties.useFlag = false
    properties.flag = 'picked'
    properties.useRating = false
    properties.ratingOp = 'atLeast'
    properties.rating = 3
    properties.useColor = false
    for _, color in ipairs(PhotoFilter.COLORS) do
      properties['color_' .. color.key] = false
    end

    for index, node in ipairs(collectionNodes) do
      node.key = 'collection_' .. index
      properties[node.key] = options.selectAll == true
    end

    -- A smart collection stays ticked while smart collections are excluded,
    -- so switching them back on restores the earlier choice.
    local function isIncluded(node)
      return not node.smart or properties.includeSmart
    end

    local function recount()
      local count, available = 0, 0
      for _, node in ipairs(collectionNodes) do
        if isIncluded(node) then
          available = available + 1
          if properties[node.key] then
            count = count + 1
          end
        end
      end
      properties.availableCount = available
      properties.selectedCount = count
    end

    for _, node in ipairs(collectionNodes) do
      properties:addObserver(node.key, recount)
    end
    properties:addObserver('includeSmart', recount)
    recount()

    local function setAll(value)
      for _, node in ipairs(collectionNodes) do
        properties[node.key] = value
      end
    end

    local contents = f:column {
      bind_to_object = properties,
      spacing = f:control_spacing(),

      f:row {
        f:push_button { title = 'Select all', action = function() setAll(true) end },
        f:push_button { title = 'Select none', action = function() setAll(false) end },
        f:static_text {
          title = LrView.bind {
            keys = { 'selectedCount', 'availableCount' },
            operation = function(_, values)
              return string.format('%d of %d collections selected',
                values.selectedCount or 0, values.availableCount or 0)
            end,
          },
          alignment = 'right',
          width = 240,
        },
      },

      f:scrolled_view {
        width = 560,
        height = 340,
        horizontal_scroller = false,
        f:column(buildList(f, nodes)),
      },

      f:checkbox {
        title = 'Include smart collections',
        value = LrView.bind('includeSmart'),
      },

      buildFilterBox(f),

      f:row {
        f:push_button {
          title = 'Choose destination folder...',
          -- Button actions are called from C, where yielding is refused, so
          -- anything that opens a panel has to hop onto a task first.
          action = function()
            LrTasks.startAsyncTask(function()
              local result = LrDialogs.runOpenPanel {
                canChooseDirectories = true,
                canChooseFiles = false,
                allowsMultipleSelection = false,
              }
              if result then
                properties.rootPath = result[1]
              end
            end)
          end,
        },
        f:static_text {
          title = LrView.bind {
            key = 'rootPath',
            transform = function(value)
              if not value or value == '' then
                return 'No folder chosen yet'
              end
              return value
            end,
          },
          truncation = 'middle',
          width = 380,
        },
      },

      f:row {
        f:static_text { title = 'Export preset:' },
        f:popup_menu {
          value = LrView.bind('presetPath'),
          items = LrView.bind('presetItems'),
          width = 320,
        },
        f:push_button {
          title = 'Other file...',
          action = function()
            LrTasks.startAsyncTask(function()
              local result = LrDialogs.runOpenPanel {
                canChooseFiles = true,
                canChooseDirectories = false,
                allowsMultipleSelection = false,
                fileTypes = { 'lrtemplate' },
                prompt = 'Select an export preset',
              }
              if not result then
                return
              end

              local file = result[1]
              if file:lower():sub(-11) ~= '.lrtemplate' then
                LrDialogs.message('Collections2Folders',
                  'Please choose a .lrtemplate file.', 'critical')
                return
              end

              -- Rebuild the list so the bound popup picks up the new entry.
              local items = {}
              for _, item in ipairs(properties.presetItems) do
                items[#items + 1] = item
              end
              items[#items + 1] = { title = 'Other / ' .. Utils.presetTitle(file), value = file }
              properties.presetItems = items
              properties.presetPath = file
            end)
          end,
        },
      },

      f:static_text {
        title = 'Each collection is written to a folder that mirrors its place in the catalog.',
        font = '<system/small>',
        fill_horizontal = 1,
      },
    }

    local action = LrDialogs.presentModalDialog {
      title = options.title or 'Collections2Folders',
      contents = contents,
      actionVerb = 'Export',
    }

    if action ~= 'ok' then
      return
    end

    if properties.rootPath == '' then
      LrDialogs.message('Collections2Folders',
        'Choose a destination folder before exporting.', 'critical')
      return
    end

    local selected = {}
    for _, node in ipairs(collectionNodes) do
      if properties[node.key] and isIncluded(node) then
        selected[#selected + 1] = node.object
      end
    end

    if #selected == 0 then
      LrDialogs.message('Collections2Folders',
        'Select at least one collection before exporting.', 'critical')
      return
    end

    local criteria, filterError = PhotoFilter.fromProperties(properties)
    if filterError then
      LrDialogs.message('Collections2Folders', filterError, 'critical')
      return
    end

    runExport(context, properties, selected, criteria)
  end)
end

return ExportDialog
