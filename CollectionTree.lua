local CollectionTree = {}

-- Reads every name up front, then sorts on the plain strings.
-- table.sort is a C call and a comparator that touched the catalog would
-- have to yield inside it, which Lua refuses.
local function toNodes(objects, kind, depth)
  local nodes = {}

  for _, object in ipairs(objects) do
    nodes[#nodes + 1] = {
      kind = kind,
      name = object:getName(),
      depth = depth,
      object = object,
    }
  end

  table.sort(nodes, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  return nodes
end

-- Walks a catalog or a collection set. Both answer the same two methods,
-- so the catalog root needs no special case.
local function walk(parent, depth, nodes)
  local collections = toNodes(parent:getChildCollections(), 'collection', depth)
  local sets = toNodes(parent:getChildCollectionSets(), 'set', depth)

  for _, node in ipairs(collections) do
    nodes[#nodes + 1] = node
  end

  for _, node in ipairs(sets) do
    nodes[#nodes + 1] = node
    walk(node.object, depth + 1, nodes)
  end

  return nodes
end

-- Flattens the whole hierarchy into display order, collection sets included
-- so the dialog can show where each collection sits.
function CollectionTree.flatten(catalog)
  return walk(catalog, 0, {})
end

return CollectionTree
