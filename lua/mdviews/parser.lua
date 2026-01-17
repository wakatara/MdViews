-- MdViews: YAML Frontmatter Parser
-- Pure Lua parser for simple YAML frontmatter in markdown files

local M = {}

--- Parse a YAML value string into appropriate Lua type
---@param value string
---@return any
local function parse_value(value)
  if value == nil or value == "" then
    return nil
  end

  -- Trim whitespace
  value = value:match("^%s*(.-)%s*$")

  -- Empty after trim
  if value == "" then
    return nil
  end

  -- Boolean
  if value == "true" then
    return true
  elseif value == "false" then
    return false
  end

  -- Null
  if value == "null" or value == "~" then
    return nil
  end

  -- Number (integer or float)
  local num = tonumber(value)
  if num then
    return num
  end

  -- Date (YYYY-MM-DD)
  local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if year then
    return {
      _type = "date",
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      raw = value,
    }
  end

  -- Quoted string - remove quotes
  local quoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
  if quoted then
    return quoted
  end

  -- Plain string
  return value
end

--- Parse YAML list (simple inline format: [item1, item2])
---@param value string
---@return table|nil
local function parse_inline_list(value)
  local inner = value:match("^%[(.*)%]$")
  if not inner then
    return nil
  end

  local items = {}
  for item in inner:gmatch("[^,]+") do
    item = item:match("^%s*(.-)%s*$")
    if item ~= "" then
      table.insert(items, parse_value(item))
    end
  end
  return items
end

--- Extract frontmatter block from markdown content
---@param content string
---@return string|nil frontmatter block without delimiters
local function extract_frontmatter(content)
  -- Must start with ---
  if not content:match("^%-%-%-") then
    return nil
  end

  -- Find closing ---
  local _, fm_end = content:find("\n%-%-%-", 4)
  if not fm_end then
    return nil
  end

  return content:sub(5, fm_end - 4)
end

--- Parse frontmatter string into Lua table
---@param frontmatter string
---@return table
local function parse_frontmatter(frontmatter)
  local result = {}
  local current_list_key = nil
  local current_list = nil

  for line in frontmatter:gmatch("[^\n]+") do
    -- Skip empty lines and comments
    if line:match("^%s*$") or line:match("^%s*#") then
      goto continue
    end

    -- Check for list item (starts with -)
    local list_indent, list_item = line:match("^(%s*)%-%s+(.+)$")
    if list_item and current_list_key then
      table.insert(current_list, parse_value(list_item))
      goto continue
    end

    -- Regular key: value pair
    local key, value = line:match("^([%w_]+):%s*(.*)$")
    if key then
      -- Save previous list if any
      if current_list_key then
        result[current_list_key] = current_list
        current_list_key = nil
        current_list = nil
      end

      -- Check for inline list
      local inline_list = parse_inline_list(value)
      if inline_list then
        result[key] = inline_list
      elseif value == "" then
        -- Empty value might start a list
        current_list_key = key
        current_list = {}
      else
        result[key] = parse_value(value)
      end
    end

    ::continue::
  end

  -- Save final list if any
  if current_list_key then
    result[current_list_key] = current_list
  end

  return result
end

--- Parse a single markdown file and extract frontmatter
---@param filepath string
---@return table|nil frontmatter, string|nil error
function M.parse_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Could not open file: " .. filepath
  end

  local content = file:read("*all")
  file:close()

  local frontmatter = extract_frontmatter(content)
  if not frontmatter then
    return {}, nil -- No frontmatter, return empty table
  end

  local parsed = parse_frontmatter(frontmatter)

  -- Add file metadata
  local filename = filepath:match("([^/]+)$")
  local title = filename:gsub("%.md$", "")
  parsed._file = {
    path = filepath,
    name = filename,
    title = title,
  }

  return parsed, nil
end

--- Scan directory for markdown files and parse all frontmatter
---@param dir string directory path
---@param recursive boolean|nil whether to scan recursively (default: false)
---@return table[] list of parsed frontmatter tables
function M.scan_directory(dir, recursive)
  local results = {}

  -- Expand ~ to home directory
  dir = dir:gsub("^~", os.getenv("HOME") or "")

  -- Use vim.fn.glob for file discovery
  local pattern = recursive and (dir .. "/**/*.md") or (dir .. "/*.md")
  local files = vim.fn.glob(pattern, false, true)

  for _, filepath in ipairs(files) do
    local parsed, err = M.parse_file(filepath)
    if parsed and not err then
      table.insert(results, parsed)
    end
  end

  return results
end

return M
