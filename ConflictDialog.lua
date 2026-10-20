local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrView = import 'LrView'

local ConflictDialog = {}

local MAX_LISTED = 8

-- collisionHandling is the LR_collisionHandling value the choice forces.
-- The two choices without one leave the preset's own setting alone, since
-- the folders they export into hold nothing to collide with.
local CHOICES = {
  {
    value = 'skipFiles',
    title = 'Skip photos whose file already exists',
    collisionHandling = 'skip',
  },
  {
    value = 'overwrite',
    title = 'Overwrite files that already exist',
    collisionHandling = 'overwrite',
  },
  {
    value = 'rename',
    title = 'Keep both, giving the new files a unique name',
    collisionHandling = 'rename',
  },
  {
    value = 'skipCollections',
    title = 'Skip collections whose folder already contains files',
  },
  {
    value = 'emptyFolders',
    title = 'Move the existing files to the '
      .. (WIN_ENV and 'Recycle Bin' or 'Trash') .. ' first',
  },
}

function ConflictDialog.collisionHandling(choice)
  for _, item in ipairs(CHOICES) do
    if item.value == choice then
      return item.collisionHandling
    end
  end
  return nil
end

local function plural(count, word)
  return string.format('%d %s%s', count, word, count == 1 and '' or 's')
end

-- Asks what to do about destination folders that already hold files.
-- Returns one of the choice values, or nil when the user cancels.
function ConflictDialog.ask(conflicts, jobCount)
  local result

  LrFunctionContext.callWithContext('ConflictDialog', function(context)
    local f = LrView.osFactory()
    local properties = LrBinding.makePropertyTable(context)
    properties.choice = 'skipFiles'

    local fileCount = 0
    local listed = { spacing = 2 }
    for index, job in ipairs(conflicts) do
      fileCount = fileCount + #job.existingFiles
      if index <= MAX_LISTED then
        listed[#listed + 1] = f:static_text {
          title = job.label .. '  (' .. plural(#job.existingFiles, 'file') .. ')',
          font = '<system/small>',
        }
      end
    end
    if #conflicts > MAX_LISTED then
      listed[#listed + 1] = f:static_text {
        title = string.format('... and %d more', #conflicts - MAX_LISTED),
        font = '<system/small>',
      }
    end

    local choices = { spacing = f:label_spacing() }
    for _, item in ipairs(CHOICES) do
      choices[#choices + 1] = f:radio_button {
        title = item.title,
        value = LrView.bind('choice'),
        checked_value = item.value,
      }
    end

    local contents = f:column {
      bind_to_object = properties,
      spacing = f:control_spacing(),

      f:static_text {
        title = string.format('%d of %d destination folders already contain files, %s in total:',
          #conflicts, jobCount, plural(fileCount, 'file')),
      },
      f:column(listed),
      f:static_text { title = 'What should happen to them?' },
      f:column(choices),
      f:static_text {
        title = 'An existing file is recognised by its name, so a photo only counts as '
          .. 'already exported if the preset names it the same way as last time. '
          .. "Only files directly inside a collection's folder are affected.",
        font = '<system/small>',
        width = 460,
        height_in_lines = 3,
      },
    }

    local action = LrDialogs.presentModalDialog {
      title = 'Destination already contains files',
      contents = contents,
      actionVerb = 'Export',
    }

    if action == 'ok' then
      result = properties.choice
    end
  end)

  return result
end

return ConflictDialog
