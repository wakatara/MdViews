-- MdViews: UI Components
-- Telescope picker and floating window for displaying query results

local M = {}

--- Format a value for display
---@param value any
---@return string
local function format_value(value)
  if value == nil then
    return ""
  end
  if type(value) == "table" then
    if value._type == "date" then
      return value.raw or ""
    end
    -- Array
    if #value > 0 then
      local parts = {}
      for _, v in ipairs(value) do
        table.insert(parts, tostring(v))
      end
      return table.concat(parts, ", ")
    end
    return ""
  end
  if type(value) == "boolean" then
    return value and "yes" or "no"
  end
  return tostring(value)
end

--- Get display width of a string (handles emoji/unicode correctly)
---@param str string
---@return number
local function display_width(str)
  return vim.fn.strdisplaywidth(str)
end

--- Calculate column widths for table display
---@param results table[] query results
---@param fields string[] fields to display
---@return table<string, number> field -> width
local function calculate_widths(results, fields)
  local widths = {}

  -- Start with header widths
  for _, field in ipairs(fields) do
    widths[field] = display_width(field)
  end

  -- Check all values (use display width for emoji/unicode support)
  for _, row in ipairs(results) do
    for _, field in ipairs(fields) do
      local formatted = format_value(row[field])
      widths[field] = math.max(widths[field], display_width(formatted))
    end
  end

  return widths
end

--- Generate markdown table from results
---@param results table[] query results
---@param fields string[] fields to display
---@param opts table|nil options { numbered = bool }
---@return string[] lines of markdown table
function M.to_markdown_table(results, fields, opts)
  opts = opts or {}
  local numbered = opts.numbered or false

  if #results == 0 then
    return { "No results found." }
  end

  local widths = calculate_widths(results, fields)
  local lines = {}

  -- Calculate width for row numbers
  local num_width = numbered and #tostring(#results) or 0

  -- Header row
  local header_parts = {}
  if numbered then
    table.insert(header_parts, string.format("%-" .. num_width .. "s", "#"))
  end
  for _, field in ipairs(fields) do
    table.insert(header_parts, string.format("%-" .. widths[field] .. "s", field))
  end
  table.insert(lines, "| " .. table.concat(header_parts, " | ") .. " |")

  -- Separator row
  local sep_parts = {}
  if numbered then
    table.insert(sep_parts, string.rep("-", num_width))
  end
  for _, field in ipairs(fields) do
    table.insert(sep_parts, string.rep("-", widths[field]))
  end
  table.insert(lines, "|-" .. table.concat(sep_parts, "-|-") .. "-|")

  -- Data rows
  for i, row in ipairs(results) do
    local row_parts = {}
    if numbered then
      table.insert(row_parts, string.format("%-" .. num_width .. "s", tostring(i)))
    end
    for _, field in ipairs(fields) do
      local value = format_value(row[field])
      table.insert(row_parts, string.format("%-" .. widths[field] .. "s", value))
    end
    table.insert(lines, "| " .. table.concat(row_parts, " | ") .. " |")
  end

  return lines
end

--- Show results in a floating window
---@param results table[] query results
---@param fields string[] fields to display
---@param opts table|nil options { title, numbered }
function M.show_float(results, fields, opts)
  opts = opts or {}
  local title = opts.title or "MdViews"

  local lines = M.to_markdown_table(results, fields, { numbered = opts.numbered })

  -- Calculate window size
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, #line)
  end

  local width = math.min(max_width + 4, math.floor(vim.o.columns * 0.9))
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- Create window
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set window options
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  -- Store results for navigation
  vim.b[buf].mdviews_results = results

  -- Keymaps for the float
  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local open_file = function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row_idx = cursor[1] - 2 -- Account for header and separator
    if row_idx >= 1 and row_idx <= #results then
      local result = results[row_idx]
      if result._file and result._file.path then
        close()
        vim.cmd("edit " .. vim.fn.fnameescape(result._file.path))
      end
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })
  vim.keymap.set("n", "<CR>", open_file, { buffer = buf, silent = true })
end

--- Show results in Telescope picker
---@param results table[] query results
---@param fields string[] fields to display
---@param opts table|nil options { title, numbered }
function M.show_telescope(results, fields, opts)
  local ok, telescope = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify("Telescope not available, falling back to float", vim.log.levels.WARN)
    return M.show_float(results, fields, opts)
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")
  local previewers = require("telescope.previewers")

  opts = opts or {}
  local title = opts.title or "MdViews"
  local numbered = opts.numbered or false

  if #results == 0 then
    vim.notify("No results found", vim.log.levels.INFO)
    return
  end

  -- Calculate column widths
  local widths = calculate_widths(results, fields)

  -- Calculate width for row numbers
  local num_width = numbered and #tostring(#results) or 0

  -- Build displayer
  local displayer_items = {}
  if numbered then
    table.insert(displayer_items, { width = num_width + 1 })
  end
  for _, field in ipairs(fields) do
    table.insert(displayer_items, { width = widths[field] + 1 })
  end

  local displayer = entry_display.create({
    separator = " ",
    items = displayer_items,
  })

  local show_headers = opts.show_headers or false

  local make_display = function(entry)
    local display_items = {}
    -- Header row (row_num = 0)
    if entry.is_header then
      if numbered then
        table.insert(display_items, { "#", "TelescopeResultsTitle" })
      end
      for _, field in ipairs(fields) do
        table.insert(display_items, { field, "TelescopeResultsTitle" })
      end
      return displayer(display_items)
    end
    -- Regular data row
    if numbered then
      table.insert(display_items, tostring(entry.row_num))
    end
    for _, field in ipairs(fields) do
      table.insert(display_items, format_value(entry.value[field]))
    end
    return displayer(display_items)
  end

  -- Add row_num to results for numbering (using row_num to avoid telescope's internal index)
  local indexed_results = {}
  -- Add header row if enabled
  if show_headers then
    table.insert(indexed_results, { row_num = 0, result = {}, is_header = true })
  end
  local data_row = 1
  for _, result in ipairs(results) do
    table.insert(indexed_results, { row_num = data_row, result = result })
    data_row = data_row + 1
  end

  -- Generate reversed markdown table for yanking
  local function yank_table_reversed()
    local reversed_results = {}
    for i = #results, 1, -1 do
      table.insert(reversed_results, results[i])
    end
    local lines = M.to_markdown_table(reversed_results, fields, { numbered = numbered })
    local text = table.concat(lines, "\n")
    vim.fn.setreg("+", text)
    vim.fn.setreg('"', text)
    vim.notify("Copied " .. #results .. " rows to clipboard (reversed)", vim.log.levels.INFO)
  end

  -- Generate markdown table for yanking (original order)
  local function yank_table()
    local lines = M.to_markdown_table(results, fields, { numbered = numbered })
    local text = table.concat(lines, "\n")
    vim.fn.setreg("+", text)
    vim.fn.setreg('"', text)
    vim.notify("Copied " .. #results .. " rows to clipboard", vim.log.levels.INFO)
  end

  telescope.new(opts, {
    prompt_title = title .. " (y=yank, Y=yank reversed)",
    sorting_strategy = "ascending", -- Show results top-to-bottom (header first)
    finder = finders.new_table({
      results = indexed_results,
      entry_maker = function(item)
        -- Header row (no path - previewer handles this)
        if item.is_header then
          return {
            value = {},
            row_num = 0,
            is_header = true,
            display = make_display,
            ordinal = "000000 _header", -- Sort to top (space before underscore)
          }
        end
        -- Regular data row
        local result = item.result
        local title_val = result._file and result._file.title or result.title or "Unknown"
        return {
          value = result,
          row_num = item.row_num,
          display = make_display,
          -- Numeric prefix preserves sort order while allowing title search
          ordinal = string.format("%06d %s", item.row_num, title_val),
          path = result._file and result._file.path,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = "Preview",
      define_preview = function(self, entry, status)
        -- Skip entries without valid paths (e.g., header row)
        if not entry.path or type(entry.path) ~= "string" then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "" })
          return
        end
        -- Use the default file previewer logic
        conf.buffer_previewer_maker(entry.path, self.state.bufnr, {
          bufname = self.state.bufname,
          winid = self.state.winid,
        })
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        -- Skip header row
        if selection and selection.is_header then
          return
        end
        actions.close(prompt_bufnr)
        if selection and selection.path then
          vim.cmd("edit " .. vim.fn.fnameescape(selection.path))
        end
      end)

      -- Yank table (original order)
      map("n", "y", function()
        yank_table()
      end)

      -- Yank table (reversed order)
      map("n", "Y", function()
        yank_table_reversed()
      end)

      return true
    end,
  }):find()
end

--- Show view selector using Telescope
---@param views table<string, table> available views
---@param run_view function callback to run a view
function M.show_view_picker(views, run_view)
  local ok, telescope = pcall(require, "telescope.pickers")
  if not ok then
    -- Fallback to vim.ui.select
    local view_names = vim.tbl_keys(views)
    table.sort(view_names)
    vim.ui.select(view_names, { prompt = "Select view:" }, function(choice)
      if choice then
        run_view(choice)
      end
    end)
    return
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local view_list = {}
  for name, view in pairs(views) do
    table.insert(view_list, {
      name = name,
      from = view.from or "",
      description = view.description or "",
    })
  end

  table.sort(view_list, function(a, b)
    -- Sort by description (title) first, then by name
    local a_title = a.description ~= "" and a.description or a.name
    local b_title = b.description ~= "" and b.description or b.name
    return a_title < b_title
  end)

  telescope.new({}, {
    prompt_title = "MdViews",
    sorting_strategy = "ascending", -- Show results at top of window
    finder = finders.new_table({
      results = view_list,
      entry_maker = function(entry)
        local display
        if entry.description ~= "" then
          display = entry.description .. " :: " .. entry.name
        else
          display = entry.name
        end
        return {
          value = entry,
          display = display,
          -- Allow searching by both description and name
          ordinal = (entry.description or "") .. " " .. entry.name,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          run_view(selection.value.name)
        end
      end)
      return true
    end,
  }):find()
end

return M
