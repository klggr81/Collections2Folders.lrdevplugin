local LrApplication = import 'LrApplication'

local PhotoFilter = {}

PhotoFilter.COLORS = {
  { key = 'red', title = 'Red' },
  { key = 'yellow', title = 'Yellow' },
  { key = 'green', title = 'Green' },
  { key = 'blue', title = 'Blue' },
  { key = 'purple', title = 'Purple' },
}

PhotoFilter.FLAG_ITEMS = {
  { title = 'Picked', value = 'picked' },
  { title = 'Not rejected', value = 'notRejected' },
  { title = 'Unflagged', value = 'unflagged' },
  { title = 'Rejected', value = 'rejected' },
}

PhotoFilter.RATING_OP_ITEMS = {
  { title = 'at least', value = 'atLeast' },
  { title = 'exactly', value = 'exactly' },
  { title = 'at most', value = 'atMost' },
}

PhotoFilter.RATING_ITEMS = {
  { title = '1 star', value = 1 },
  { title = '2 stars', value = 2 },
  { title = '3 stars', value = 3 },
  { title = '4 stars', value = 4 },
  { title = '5 stars', value = 5 },
}

-- pickStatus is 1 for a pick, 0 for unflagged and -1 for a reject.
local FLAG_TESTS = {
  picked = function(status) return status == 1 end,
  notRejected = function(status) return status ~= -1 end,
  unflagged = function(status) return status == 0 end,
  rejected = function(status) return status == -1 end,
}

local RATING_TESTS = {
  atLeast = function(rating, wanted) return rating >= wanted end,
  exactly = function(rating, wanted) return rating == wanted end,
  atMost = function(rating, wanted) return rating <= wanted end,
}

-- Turns the dialog's filter properties into criteria for apply.
-- Returns nil when every photo should be exported, or nil and a message
-- when the filter is switched on but would match nothing sensible.
function PhotoFilter.fromProperties(properties)
  if properties.photoFilter ~= 'filtered' then
    return nil
  end

  local criteria = { matchAll = properties.matchMode ~= 'any' }
  local count = 0

  if properties.useFlag then
    criteria.flag = properties.flag
    count = count + 1
  end

  if properties.useRating then
    criteria.ratingOp = properties.ratingOp
    criteria.rating = properties.rating
    count = count + 1
  end

  if properties.useColor then
    local colors, any = {}, false
    for _, color in ipairs(PhotoFilter.COLORS) do
      if properties['color_' .. color.key] then
        colors[color.key] = true
        any = true
      end
    end
    if not any then
      return nil, 'Tick at least one colour label, or untick Color label.'
    end
    criteria.colors = colors
    count = count + 1
  end

  if count == 0 then
    return nil, 'Tick at least one criterion, or choose All photos.'
  end
  return criteria
end

local function matches(criteria, metadata)
  local results = {}

  if criteria.flag then
    results[#results + 1] = FLAG_TESTS[criteria.flag](metadata.pickStatus or 0)
  end
  if criteria.rating then
    results[#results + 1] = RATING_TESTS[criteria.ratingOp](metadata.rating or 0, criteria.rating)
  end
  if criteria.colors then
    results[#results + 1] = criteria.colors[metadata.colorNameForLabel] == true
  end

  for _, result in ipairs(results) do
    if criteria.matchAll and not result then
      return false
    end
    if not criteria.matchAll and result then
      return true
    end
  end
  return criteria.matchAll
end

-- Returns the photos that pass the criteria, or all of them without any.
-- Reads the metadata in one batch, since a catalog read per photo is slow
-- on large collections. Must run on a task.
function PhotoFilter.apply(photos, criteria)
  if not criteria or #photos == 0 then
    return photos
  end

  local catalog = LrApplication.activeCatalog()
  local metadata = catalog:batchGetRawMetadata(photos,
    { 'pickStatus', 'rating', 'colorNameForLabel' })

  local kept = {}
  for _, photo in ipairs(photos) do
    if matches(criteria, metadata[photo] or {}) then
      kept[#kept + 1] = photo
    end
  end
  return kept
end

return PhotoFilter
