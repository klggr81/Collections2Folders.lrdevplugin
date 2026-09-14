local LrApplication = import 'LrApplication'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Utils = {}

local ILLEGAL_CHARS = '[/\\:%*%?"<>|]'

local function childPath(base, ...)
  local path = base
  for _, segment in ipairs({...}) do
    path = LrPathUtils.child(path, segment)
  end
  return path
end

-- Everything in this module runs on a task, and Lua cannot yield across a
-- plain pcall, so protected calls here must go through LrTasks.pcall.
local function standardPath(which)
  local ok, path = LrTasks.pcall(LrPathUtils.getStandardFilePath, which)
  if ok then
    return path
  end
  return nil
end

-- Collection names are free text, so strip anything a file system would reject.
function Utils.sanitize(name)
  local clean = tostring(name or ''):gsub(ILLEGAL_CHARS, '-')
  clean = clean:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%.+$', '')
  if clean == '' then
    clean = 'Untitled'
  end
  return clean
end

function Utils.createFolder(path)
  if not LrFileUtils.exists(path) then
    LrFileUtils.createAllDirectories(path)
  end
  return path
end

function Utils.defineDestination(root, name)
  return Utils.createFolder(LrPathUtils.child(root, Utils.sanitize(name)))
end

-- Mirrors the collection's place in the catalog hierarchy under root,
-- creating every folder on the way down.
function Utils.collectionDestination(collection, root)
  local parts = {}

  local parent = collection:getParent()
  while parent do
    table.insert(parts, 1, Utils.sanitize(parent:getName()))
    parent = parent:getParent()
  end
  table.insert(parts, Utils.sanitize(collection:getName()))

  local path = root
  for _, part in ipairs(parts) do
    path = LrPathUtils.child(path, part)
  end
  return Utils.createFolder(path)
end

function Utils.len(array)
  local count = 0
  for _ in pairs(array) do
    count = count + 1
  end
  return count
end

-- An .lrtemplate file is a Lua chunk that assigns a global table named s.
-- Run it in a private environment so it cannot touch the plug-in's globals.
local function parseTemplate(path)
  local file = io.open(path, 'r')
  if not file then
    return nil, 'could not read ' .. tostring(path)
  end

  local content = file:read('*all')
  file:close()

  if not content then
    return nil, 'could not read ' .. tostring(path)
  end

  local chunk, err = loadstring(content .. '\nreturn s')
  if not chunk then
    return nil, tostring(err)
  end

  -- Run the template in its own environment where that is allowed, so it
  -- cannot touch the plug-in's globals. Lightroom's sandbox does not always
  -- expose setfenv, in which case the chunk just assigns a global.
  if setfenv then
    setfenv(chunk, {})
  end

  local ran, template = pcall(chunk)
  if not ran or type(template) ~= 'table' then
    return nil, 'could not parse ' .. tostring(path)
  end
  return template
end

function Utils.presetTitle(path)
  local template = parseTemplate(path)
  if template and type(template.title) == 'string' and template.title ~= '' then
    return template.title
  end
  return LrPathUtils.removeExtension(LrPathUtils.leafName(path))
end

-- Returns a settings table ready for LrExportSession.
-- Presets store the keys without the LR_ prefix that the SDK expects, so
-- passing the raw table through leaves every setting at its default.
function Utils.loadExportSettings(path)
  if not path or path == '' then
    return {}
  end

  local template, err = parseTemplate(path)
  if not template or type(template.value) ~= 'table' then
    return {}, err or ('no export settings found in ' .. tostring(path))
  end

  local settings = {}
  for key, value in pairs(template.value) do
    if key:sub(1, 3) == 'LR_' then
      settings[key] = value
    else
      settings['LR_' .. key] = value
    end
  end
  return settings
end

local function presetRoots()
  local bases = {}

  local appData = standardPath('appData')
  if appData then
    bases[#bases + 1] = appData
    bases[#bases + 1] = childPath(appData, 'Adobe', 'Lightroom')
  end

  local home = standardPath('home')
  if home then
    bases[#bases + 1] = childPath(home, 'AppData', 'Roaming', 'Adobe', 'Lightroom')
    bases[#bases + 1] = childPath(home, 'Library', 'Application Support', 'Adobe', 'Lightroom')
  end

  -- Covers "Store presets with this catalog".
  local catalog = LrApplication.activeCatalog()
  local catalogDir = catalog and LrPathUtils.parent(catalog:getPath())
  if catalogDir then
    bases[#bases + 1] = childPath(catalogDir, 'Lightroom Settings')
  end

  local roots, seen = {}, {}
  for _, base in ipairs(bases) do
    local root = LrPathUtils.child(base, 'Export Presets')
    if not seen[root] and LrFileUtils.exists(root) == 'directory' then
      seen[root] = true
      roots[#roots + 1] = root
    end
  end
  return roots
end

-- Every export preset Lightroom knows about, user and built-in alike.
function Utils.getExportPresets()
  local presets, seen = {}, {}

  -- A preset folder that cannot be scanned should cost us that folder,
  -- not the whole dialog. The scan yields, so it needs LrTasks.pcall.
  for _, root in ipairs(presetRoots()) do
    LrTasks.pcall(function()
      for file in LrFileUtils.recursiveFiles(root) do
        if file:lower():sub(-11) == '.lrtemplate' and not seen[file] then
          seen[file] = true
          presets[#presets + 1] = {
            title = Utils.presetTitle(file),
            value = file,
            group = LrPathUtils.leafName(LrPathUtils.parent(file)),
          }
        end
      end
    end)
  end

  table.sort(presets, function(a, b)
    if a.group ~= b.group then
      return a.group:lower() < b.group:lower()
    end
    return a.title:lower() < b.title:lower()
  end)
  return presets
end

return Utils
