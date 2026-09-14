local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local CollectionTree = require 'CollectionTree'
local ExportCollection = require 'ExportCollection'
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

local function runExport(context, properties, selected)
  local exportSettings, err = Utils.loadExportSettings(properties.presetPath)
  if err then
    LrDialogs.message('Collections2Folders',
      'The export preset could not be read, so Lightroom defaults were used.\n\n' .. err,
      'warning')
  end

  local progress = LrDialogs.showModalProgressDialog {
    title = 'Exporting collections',
    caption = '',
    cannotCancel = false,
    functionContext = context,
  }

  local photoCount, done = 0, 0

  for index, collection in ipairs(selected) do
    if progress:isCanceled() then
      break
    end
    progress:setCaption(collection:getName())
    progress:setPortionComplete(index - 1, #selected)

    photoCount = photoCount + ExportCollection.exportCollection(
      collection, properties.rootPath, exportSettings)
    done = done + 1
  end

  progress:done()

  local summary = string.format('Exported %d photos from %d of %d collections.',
    photoCount, done, #selected)
  if progress:isCanceled() then
    summary = 'Export canceled. ' .. summary
  end
  LrDialogs.message('Collections2Folders', summary, 'info')
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

    for index, node in ipairs(collectionNodes) do
      node.key = 'collection_' .. index
      properties[node.key] = options.selectAll == true
    end

    local function recount()
      local count = 0
      for _, node in ipairs(collectionNodes) do
        if properties[node.key] then
          count = count + 1
        end
      end
      properties.selectedCount = count
    end

    for _, node in ipairs(collectionNodes) do
      properties:addObserver(node.key, recount)
    end
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
            key = 'selectedCount',
            transform = function(value)
              return string.format('%d of %d collections selected',
                value or 0, #collectionNodes)
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
      if properties[node.key] then
        selected[#selected + 1] = node.object
      end
    end

    if #selected == 0 then
      LrDialogs.message('Collections2Folders',
        'Select at least one collection before exporting.', 'critical')
      return
    end

    runExport(context, properties, selected)
  end)
end

return ExportDialog
