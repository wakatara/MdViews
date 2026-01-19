-- MdViews: Markdown Frontmatter Query and View Plugin
-- Similar to Obsidian Dataview, but pure Lua for Neovim

local parser = require("mdviews.parser")
local query = require("mdviews.query")
local ui = require("mdviews.ui")

local M = {}

-- Default configuration
M.config = {
  -- Default display mode: "telescope" or "float"
  display = "telescope",
  -- Predefined views
  views = {},
  -- Default vault/home directory (expanded at runtime)
  home = nil,
}

--- Setup the plugin
---@param opts table|nil configuration options
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  -- Expand home path
  if M.config.home then
    M.config.home = vim.fn.expand(M.config.home)
  end

  -- Register commands
  vim.api.nvim_create_user_command("MdViews", function(cmd_opts)
    local args = cmd_opts.args
    if args == "" or args == "list" then
      M.list_views()
    elseif args == "pick" then
      M.pick_view()
    else
      M.run_view(args)
    end
  end, {
    nargs = "?",
    complete = function()
      local names = vim.tbl_keys(M.config.views)
      table.sort(names)
      table.insert(names, 1, "list")
      table.insert(names, 2, "pick")
      return names
    end,
    desc = "MdViews: Query markdown frontmatter",
  })

  -- Register MdViewsQuery for ad-hoc queries
  vim.api.nvim_create_user_command("MdViewsQuery", function(cmd_opts)
    -- Simple query: MdViewsQuery path/to/dir
    local dir = cmd_opts.args
    if dir == "" then
      dir = M.config.home or vim.fn.getcwd()
    end
    M.run_query({
      from = dir,
      fields = { "title", "type", "rating", "start", "end" },
      sort = { field = "start", order = "desc" },
    })
  end, {
    nargs = "?",
    complete = "dir",
    desc = "MdViews: Run ad-hoc query on directory",
  })
end

--- Run a query and display results
---@param opts table query options { from, fields, where, sort, limit, display, title }
function M.run_query(opts)
  opts = opts or {}

  local from = opts.from
  if not from then
    vim.notify("MdViews: 'from' directory is required", vim.log.levels.ERROR)
    return
  end

  -- Expand path
  from = vim.fn.expand(from)

  -- Handle relative paths if home is set
  if M.config.home and not from:match("^[/~]") then
    from = M.config.home .. "/" .. from
  end

  -- Parse all files in directory
  local records = parser.scan_directory(from, true)

  if #records == 0 then
    vim.notify("MdViews: No markdown files found in " .. from, vim.log.levels.WARN)
    return
  end

  -- Run query
  local results = query.query(records, {
    fields = opts.fields,
    where = opts.where,
    sort = opts.sort,
    limit = opts.limit,
  })

  -- Display
  local display_mode = opts.display or M.config.display
  local fields = opts.fields or { "title", "type", "rating", "start", "end" }
  -- display_fields allows showing only a subset of fields (hide query-only fields)
  local display_fields = opts.display_fields or fields
  local title = opts.title or "MdViews"
  local numbered = opts.numbered or false
  local show_headers = opts.show_headers or false

  local ui_opts = {
    title = title,
    numbered = numbered,
    show_headers = show_headers,
  }

  if display_mode == "float" then
    ui.show_float(results, display_fields, ui_opts)
  else
    ui.show_telescope(results, display_fields, ui_opts)
  end
end

--- Run a predefined view by name
---@param name string view name
function M.run_view(name)
  local view = M.config.views[name]
  if not view then
    vim.notify("MdViews: Unknown view '" .. name .. "'", vim.log.levels.ERROR)
    return
  end

  M.run_query(vim.tbl_extend("force", view, { title = name }))
end

--- List all available views
function M.list_views()
  local names = vim.tbl_keys(M.config.views)
  if #names == 0 then
    vim.notify("MdViews: No views configured", vim.log.levels.INFO)
    return
  end

  table.sort(names)
  local lines = { "Available views:" }
  for _, name in ipairs(names) do
    local view = M.config.views[name]
    local desc = view.description or view.from or ""
    table.insert(lines, "  " .. name .. (desc ~= "" and (" - " .. desc) or ""))
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Show picker to select and run a view
function M.pick_view()
  if vim.tbl_isempty(M.config.views) then
    vim.notify("MdViews: No views configured", vim.log.levels.INFO)
    return
  end

  ui.show_view_picker(M.config.views, function(name)
    M.run_view(name)
  end)
end

-- Export query helpers for use in view configs
M.eq = query.eq
M.ne = query.ne
M.gt = query.gt
M.gte = query.gte
M.lt = query.lt
M.lte = query.lte
M.contains = query.contains
M.not_contains = query.not_contains
M.is_in = query.is_in
M.exists = query.exists
M.not_exists = query.not_exists

return M
