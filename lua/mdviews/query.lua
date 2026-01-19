-- MdViews: Query Engine
-- Filter, sort, and select fields from parsed frontmatter

local M = {}

--- Compare two date tables
---@param a table date table with year, month, day
---@param b table date table with year, month, day
---@return number -1 if a < b, 0 if equal, 1 if a > b
local function compare_dates(a, b)
  if a.year ~= b.year then
    return a.year < b.year and -1 or 1
  end
  if a.month ~= b.month then
    return a.month < b.month and -1 or 1
  end
  if a.day ~= b.day then
    return a.day < b.day and -1 or 1
  end
  return 0
end

--- Compare two values for sorting
---@param a any
---@param b any
---@return number -1 if a < b, 0 if equal, 1 if a > b
local function compare_values(a, b)
  -- Handle nil
  if a == nil and b == nil then
    return 0
  end
  if a == nil then
    return 1 -- nil sorts last
  end
  if b == nil then
    return -1
  end

  -- Handle dates
  if type(a) == "table" and a._type == "date" then
    if type(b) == "table" and b._type == "date" then
      return compare_dates(a, b)
    end
    a = a.raw
  end
  if type(b) == "table" and b._type == "date" then
    b = b.raw
  end

  -- Handle other types
  if type(a) ~= type(b) then
    return tostring(a) < tostring(b) and -1 or 1
  end

  if a == b then
    return 0
  end
  return a < b and -1 or 1
end

--- Check if a record matches a single condition
---@param record table the frontmatter record
---@param field string the field to check
---@param condition any the condition (value, table with op, or function)
---@return boolean
local function matches_condition(record, field, condition)
  local value = record[field]

  -- Function condition
  if type(condition) == "function" then
    return condition(value, record)
  end

  -- Table with operator
  if type(condition) == "table" and condition.op then
    local op = condition.op
    local target = condition.value

    if op == "eq" or op == "=" or op == "==" then
      if type(value) == "table" and value._type == "date" then
        return value.raw == target
      end
      return value == target
    elseif op == "ne" or op == "!=" or op == "<>" then
      if type(value) == "table" and value._type == "date" then
        return value.raw ~= target
      end
      return value ~= target
    elseif op == "gt" or op == ">" then
      return compare_values(value, target) > 0
    elseif op == "gte" or op == ">=" then
      return compare_values(value, target) >= 0
    elseif op == "lt" or op == "<" then
      return compare_values(value, target) < 0
    elseif op == "lte" or op == "<=" then
      return compare_values(value, target) <= 0
    elseif op == "contains" then
      if type(value) == "string" then
        return value:lower():find(target:lower(), 1, true) ~= nil
      elseif type(value) == "table" then
        for _, v in ipairs(value) do
          if v == target then
            return true
          end
        end
      end
      return false
    elseif op == "not_contains" then
      if value == nil then
        return true -- nil doesn't contain anything
      end
      if type(value) == "string" then
        return value:lower():find(target:lower(), 1, true) == nil
      elseif type(value) == "table" then
        for _, v in ipairs(value) do
          if v == target then
            return false
          end
        end
        return true
      end
      return true
    elseif op == "in" then
      if type(target) == "table" then
        for _, t in ipairs(target) do
          if value == t then
            return true
          end
        end
      end
      return false
    elseif op == "exists" then
      return value ~= nil
    elseif op == "not_exists" then
      return value == nil
    end

    return false
  end

  -- Direct value comparison (handles nil, boolean, string, number)
  if condition == nil then
    return value == nil
  end

  if type(condition) == "boolean" then
    -- For "killed = false", we want to match both nil and false
    if condition == false then
      return value == false or value == nil or value == ""
    end
    return value == condition
  end

  -- String/number direct match
  if type(value) == "table" and value._type == "date" then
    return value.raw == condition
  end

  return value == condition
end

--- Filter records based on where conditions
---@param records table[] list of frontmatter records
---@param where table|nil conditions to filter by
---@return table[] filtered records
function M.filter(records, where)
  if not where or next(where) == nil then
    return records
  end

  local filtered = {}
  for _, record in ipairs(records) do
    local matches = true
    for field, condition in pairs(where) do
      if not matches_condition(record, field, condition) then
        matches = false
        break
      end
    end
    if matches then
      table.insert(filtered, record)
    end
  end

  return filtered
end

--- Sort records by a field
---@param records table[] list of frontmatter records
---@param sort table|nil sort configuration { field = "fieldname", order = "asc"|"desc" }
---@return table[] sorted records (new table, original unchanged)
function M.sort(records, sort)
  if not sort or not sort.field then
    return records
  end

  local sorted = {}
  for _, r in ipairs(records) do
    table.insert(sorted, r)
  end

  local field = sort.field
  local desc = sort.order == "desc"

  table.sort(sorted, function(a, b)
    local cmp = compare_values(a[field], b[field])
    if desc then
      return cmp > 0
    else
      return cmp < 0
    end
  end)

  return sorted
end

--- Select specific fields from records
---@param records table[] list of frontmatter records
---@param fields string[]|nil fields to select (nil = all fields)
---@return table[] records with only selected fields
function M.select(records, fields)
  if not fields or #fields == 0 then
    return records
  end

  local selected = {}
  for _, record in ipairs(records) do
    local row = {}
    for _, field in ipairs(fields) do
      if field == "title" or field == "name" or field == "path" then
        row[field] = record._file and record._file[field] or record[field]
      else
        row[field] = record[field]
      end
    end
    -- Always include _file for navigation
    row._file = record._file
    table.insert(selected, row)
  end

  return selected
end

--- Execute a full query
---@param records table[] list of frontmatter records
---@param opts table query options { fields, where, sort, limit }
---@return table[] query results
function M.query(records, opts)
  opts = opts or {}

  local results = records

  -- Filter
  if opts.where then
    results = M.filter(results, opts.where)
  end

  -- Sort
  if opts.sort then
    results = M.sort(results, opts.sort)
  end

  -- Limit
  if opts.limit and opts.limit > 0 and #results > opts.limit then
    local limited = {}
    for i = 1, opts.limit do
      table.insert(limited, results[i])
    end
    results = limited
  end

  -- Select fields
  if opts.fields then
    results = M.select(results, opts.fields)
  end

  return results
end

-- Convenience helpers for building conditions
M.eq = function(value)
  return { op = "eq", value = value }
end
M.ne = function(value)
  return { op = "ne", value = value }
end
M.gt = function(value)
  return { op = "gt", value = value }
end
M.gte = function(value)
  return { op = "gte", value = value }
end
M.lt = function(value)
  return { op = "lt", value = value }
end
M.lte = function(value)
  return { op = "lte", value = value }
end
M.contains = function(value)
  return { op = "contains", value = value }
end
M.not_contains = function(value)
  return { op = "not_contains", value = value }
end
M.is_in = function(values)
  return { op = "in", value = values }
end
M.exists = { op = "exists" }
M.not_exists = { op = "not_exists" }

return M
