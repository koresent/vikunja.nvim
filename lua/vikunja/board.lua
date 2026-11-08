local M = {}
local api = require("vikunja.api")
local config = require("vikunja.config")
local utils = require("vikunja.utils")
local editor = require("vikunja.editor")
local images = require("vikunja.images")

M.state = {
  tabpage = nil,
  project = nil,
  view = nil,
  buckets = {},
  column_windows = {},
  column_buffers = {},
  card_maps = {}, -- [bufnr] = { cards = {}, line_to_card = {} }
}

local ns_id = vim.api.nvim_create_namespace("vikunja_kanban")

local function get_current_card(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local map = M.state.card_maps[bufnr]
  if not map then
    return nil, nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local card_idx = map.line_to_card[line]
  if not card_idx then
    return nil, nil
  end

  return map.cards[card_idx], card_idx
end

local function get_current_bucket_idx()
  local cur_win = vim.api.nvim_get_current_win()
  for idx, win in ipairs(M.state.column_windows) do
    if win == cur_win then
      return idx
    end
  end
  return 1
end

local function render_column(bucket_idx)
  local bucket = M.state.buckets[bucket_idx]
  local buf = M.state.column_buffers[bucket_idx]
  local win = M.state.column_windows[bucket_idx]

  if not bucket or not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  local win_width = 36
  if win and vim.api.nvim_win_is_valid(win) then
    win_width = math.max(26, vim.api.nvim_win_get_width(win) - 2)
  end

  local lines = {}
  local card_records = {}
  local line_to_card = {}

  local tasks = bucket.tasks or {}

  if #tasks == 0 then
    table.insert(lines, "")
    table.insert(lines, "  (Empty column)")
    table.insert(lines, "")
  else
    table.insert(lines, "")
    for card_idx, task in ipairs(tasks) do
      local start_line = #lines + 1

      local id_text = task.identifier ~= "" and task.identifier or ("#" .. task.id)
      local header_prefix = "╭─ [" .. id_text .. "] "
      local fill_len = math.max(2, win_width - vim.fn.strdisplaywidth(header_prefix) - 1)
      local top_line = header_prefix .. string.rep("─", fill_len) .. "╮"
      table.insert(lines, top_line)

      local check_icon = task.done and config.options.icons.task_done or config.options.icons.task
      local raw_title = task.title or "Untitled"
      local max_title_w = win_width - 6
      if vim.fn.strdisplaywidth(raw_title) > max_title_w then
        raw_title = vim.fn.strcharpart(raw_title, 0, max_title_w - 2) .. "…"
      end
      local title_pad = math.max(0, win_width - vim.fn.strdisplaywidth("│ " .. check_icon .. raw_title) - 1)
      local title_line = "│ " .. check_icon .. raw_title .. string.rep(" ", title_pad) .. "│"
      table.insert(lines, title_line)

      local meta_parts = {}
      local due = utils.format_date(task.due_date)
      if due then
        table.insert(meta_parts, config.options.icons.due .. due)
      end
      local prio = utils.priority_info(task.priority)
      if prio.level > 0 then
        table.insert(meta_parts, prio.name)
      end
      local att_count = (type(task.attachments) == "table" and #task.attachments) or 0
      if att_count > 0 then
        table.insert(meta_parts, " " .. tostring(att_count))
      end

      if #meta_parts > 0 then
        local meta_str = table.concat(meta_parts, "  ")
        local meta_pad = math.max(0, win_width - vim.fn.strdisplaywidth("│   " .. meta_str) - 1)
        local meta_line = "│   " .. meta_str .. string.rep(" ", meta_pad) .. "│"
        table.insert(lines, meta_line)
      end

      local bot_line = "╰" .. string.rep("─", win_width - 2) .. "╯"
      table.insert(lines, bot_line)
      table.insert(lines, "")

      local end_line = #lines - 1
      card_records[card_idx] = {
        start_line = start_line,
        end_line = end_line,
        task = task,
      }

      for l = start_line, end_line do
        line_to_card[l] = card_idx
      end
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  M.state.card_maps[buf] = {
    cards = card_records,
    line_to_card = line_to_card,
  }

  for _, record in ipairs(card_records) do
    local s = record.start_line - 1
    local e = record.end_line - 1
    local t = record.task

    vim.api.nvim_buf_add_highlight(buf, ns_id, "VikunjaCardBorder", s, 0, -1)
    local id_text = t.identifier ~= "" and t.identifier or ("#" .. t.id)
    local id_pos = 4
    vim.api.nvim_buf_add_highlight(buf, ns_id, "VikunjaCardId", s, id_pos, id_pos + #id_text)

    local title_hl = t.done and "VikunjaCardTitleDone" or "VikunjaCardTitle"
    vim.api.nvim_buf_add_highlight(buf, ns_id, title_hl, s + 1, 0, -1)

    vim.api.nvim_buf_add_highlight(buf, ns_id, "VikunjaCardBorder", e, 0, -1)
  end

  if win and vim.api.nvim_win_is_valid(win) then
    local count_str = tostring(#tasks)
    local title = string.format(" %s (%s) ", bucket.title or "Bucket", count_str)
    vim.wo[win].winbar = "%#VikunjaBucketHeader#" .. title
  end
end

function M.render_all()
  for i = 1, #M.state.buckets do
    render_column(i)
  end
end

local function jump_to_card(card_idx)
  local cur_buf = vim.api.nvim_get_current_buf()
  local map = M.state.card_maps[cur_buf]
  if not map or not map.cards[card_idx] then
    return
  end

  local line = map.cards[card_idx].start_line + 1
  pcall(vim.api.nvim_win_set_cursor, 0, { line, 4 })
end

local function move_card_to_bucket(target_bucket_idx)
  local cur_bucket_idx = get_current_bucket_idx()
  if target_bucket_idx == cur_bucket_idx or target_bucket_idx < 1 or target_bucket_idx > #M.state.buckets then
    return
  end

  local cur_buf = vim.api.nvim_get_current_buf()
  local record, card_idx = get_current_card(cur_buf)
  if not record then
    return
  end

  local task = record.task
  local source_bucket = M.state.buckets[cur_bucket_idx]
  local target_bucket = M.state.buckets[target_bucket_idx]

  -- Optimistic local update
  table.remove(source_bucket.tasks, card_idx)
  target_bucket.tasks = target_bucket.tasks or {}
  table.insert(target_bucket.tasks, task)

  render_column(cur_bucket_idx)
  render_column(target_bucket_idx)

  -- Switch focus to target bucket
  local target_win = M.state.column_windows[target_bucket_idx]
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
    jump_to_card(#target_bucket.tasks)
  end

  -- Call Vikunja API
  api.move_task_bucket(M.state.project.id, M.state.view.id, target_bucket.id, task.id, function(res, err)
    if err then
      utils.notify("Failed to move task: " .. tostring(err), vim.log.levels.ERROR)
      M.refresh()
    end
  end)
end

local function reorder_card(direction)
  local cur_bucket_idx = get_current_bucket_idx()
  local cur_bucket = M.state.buckets[cur_bucket_idx]
  if not cur_bucket or not cur_bucket.tasks then
    return
  end

  local cur_buf = vim.api.nvim_get_current_buf()
  local record, cur_idx = get_current_card(cur_buf)
  if not record then
    return
  end

  local new_idx = cur_idx + direction
  if new_idx < 1 or new_idx > #cur_bucket.tasks then
    return
  end

  -- Swap tasks
  local task = cur_bucket.tasks[cur_idx]
  table.remove(cur_bucket.tasks, cur_idx)
  table.insert(cur_bucket.tasks, new_idx, task)

  -- Calculate new position
  local new_pos
  if new_idx == 1 then
    local next_task = cur_bucket.tasks[2]
    new_pos = (next_task and next_task.position or 65536) - 65536
  elseif new_idx == #cur_bucket.tasks then
    local prev_task = cur_bucket.tasks[#cur_bucket.tasks - 1]
    new_pos = (prev_task and prev_task.position or 0) + 65536
  else
    local prev_task = cur_bucket.tasks[new_idx - 1]
    local next_task = cur_bucket.tasks[new_idx + 1]
    new_pos = ((prev_task.position or 0) + (next_task.position or 0)) / 2
  end
  task.position = new_pos

  render_column(cur_bucket_idx)
  jump_to_card(new_idx)

  api.update_task_position(task.id, M.state.view.id, new_pos, function(res, err)
    if err then
      utils.notify("Failed to update position: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

local function setup_buffer_keymaps(buf)
  local keys = config.options.keymaps
  local opts = { buffer = buf, silent = true, noremap = true }

  vim.keymap.set("n", keys.next_column, function()
    local cur_idx = get_current_bucket_idx()
    if cur_idx < #M.state.column_windows then
      vim.api.nvim_set_current_win(M.state.column_windows[cur_idx + 1])
    end
  end, opts)

  vim.keymap.set("n", keys.prev_column, function()
    local cur_idx = get_current_bucket_idx()
    if cur_idx > 1 then
      vim.api.nvim_set_current_win(M.state.column_windows[cur_idx - 1])
    end
  end, opts)

  vim.keymap.set("n", keys.next_card, function()
    local _, card_idx = get_current_card(buf)
    local map = M.state.card_maps[buf]
    if not map or not map.cards then
      return
    end
    if not card_idx then
      jump_to_card(1)
    elseif card_idx < #map.cards then
      jump_to_card(card_idx + 1)
    end
  end, opts)

  vim.keymap.set("n", keys.prev_card, function()
    local _, card_idx = get_current_card(buf)
    local map = M.state.card_maps[buf]
    if not map or not map.cards then
      return
    end
    if not card_idx then
      jump_to_card(#map.cards)
    elseif card_idx > 1 then
      jump_to_card(card_idx - 1)
    end
  end, opts)

  vim.keymap.set("n", keys.move_card_next, function()
    move_card_to_bucket(get_current_bucket_idx() + 1)
  end, opts)

  vim.keymap.set("n", keys.move_card_prev, function()
    move_card_to_bucket(get_current_bucket_idx() - 1)
  end, opts)

  vim.keymap.set("n", keys.reorder_down, function()
    reorder_card(1)
  end, opts)

  vim.keymap.set("n", keys.reorder_up, function()
    reorder_card(-1)
  end, opts)

  vim.keymap.set("n", keys.move_to_bucket, function()
    local items = {}
    for idx, b in ipairs(M.state.buckets) do
      table.insert(items, string.format("%d. %s", idx, b.title))
    end
    vim.ui.select(items, { prompt = "Move to Bucket:" }, function(choice, idx)
      if idx then
        move_card_to_bucket(idx)
      end
    end)
  end, opts)

  vim.keymap.set("n", keys.toggle_done, function()
    local record = get_current_card(buf)
    if not record then
      return
    end

    local task = record.task
    local new_done = not task.done
    task.done = new_done
    render_column(get_current_bucket_idx())

    api.update_task(task.id, { done = new_done }, function(res, err)
      if err then
        utils.notify("Failed to toggle status: " .. tostring(err), vim.log.levels.ERROR)
        task.done = not new_done
        render_column(get_current_bucket_idx())
      end
    end)
  end, opts)

  vim.keymap.set("n", keys.quick_edit, function()
    local record = get_current_card(buf)
    if not record then
      return
    end

    local task = record.task
    vim.ui.input({ prompt = "Edit Title: ", default = task.title }, function(input)
      if input and input ~= "" and input ~= task.title then
        task.title = input
        render_column(get_current_bucket_idx())
        api.update_task(task.id, { title = input }, function(res, err)
          if err then
            utils.notify("Error updating title: " .. tostring(err), vim.log.levels.ERROR)
          end
        end)
      end
    end)
  end, opts)

  vim.keymap.set("n", keys.edit_task, function()
    local record = get_current_card(buf)
    if not record then
      return
    end

    local cur_col = get_current_bucket_idx()
    editor.open(record.task, M.state.project, M.state.view, function(updated_task)
      if updated_task and updated_task.id then
        for k, v in pairs(updated_task) do
          record.task[k] = v
        end
      end
      render_column(cur_col)
    end)
  end, opts)

  vim.keymap.set("n", keys.create_task, function()
    local cur_col = get_current_bucket_idx()
    local bucket = M.state.buckets[cur_col]
    if not bucket then
      return
    end

    vim.ui.input({ prompt = "New Task in [" .. bucket.title .. "]: " }, function(input)
      if not input or input == "" then
        return
      end

      api.create_task(M.state.project.id, {
        title = input,
        bucket_id = bucket.id,
      }, function(created, err)
        if err then
          utils.notify("Failed to create task: " .. tostring(err), vim.log.levels.ERROR)
          return
        end

        bucket.tasks = bucket.tasks or {}
        table.insert(bucket.tasks, created)
        render_column(cur_col)
        jump_to_card(#bucket.tasks)
        utils.notify("Created task: " .. created.title, vim.log.levels.INFO)
      end)
    end)
  end, opts)

  vim.keymap.set("n", keys.delete_task, function()
    local record, card_idx = get_current_card(buf)
    if not record then
      return
    end

    local task = record.task
    local cur_col = get_current_bucket_idx()
    local bucket = M.state.buckets[cur_col]

    vim.ui.input({ prompt = "Delete '" .. task.title .. "'? (y/N): " }, function(ans)
      if ans and (ans == "y" or ans == "Y" or ans == "yes") then
        api.delete_task(task.id, function(res, err)
          if err then
            utils.notify("Failed to delete task: " .. tostring(err), vim.log.levels.ERROR)
            return
          end

          table.remove(bucket.tasks, card_idx)
          render_column(cur_col)
          utils.notify("Deleted task: " .. task.title, vim.log.levels.INFO)
        end)
      end
    end)
  end, opts)

  vim.keymap.set("n", "i", function()
    local record = get_current_card(buf)
    if record then
      images.show_task_images(record.task)
    end
  end, opts)

  vim.keymap.set("n", "I", function()
    local record = get_current_card(buf)
    if record then
      images.upload_task_image(record.task, function()
        M.refresh()
      end)
    end
  end, opts)

  vim.keymap.set("n", keys.switch_project, function()
    M.select_project()
  end, opts)

  vim.keymap.set("n", keys.refresh, function()
    M.refresh()
  end, opts)

  vim.keymap.set("n", keys.help, function()
    M.show_help()
  end, opts)

  vim.keymap.set("n", keys.close, function()
    if M.state.tabpage and vim.api.nvim_tabpage_is_valid(M.state.tabpage) then
      vim.cmd("tabclose")
    end
  end, opts)
end

function M.show_help()
  local help_lines = {
    " ╭─────────────────────────────────────────────────────────────╮",
    " │                  VIKUNJA KANBAN SHORTCUTS                   │",
    " ├─────────────────────────────────────────────────────────────┤",
    " │ Navigation                                                  │",
    " │   h / l       Move focus to Left / Right column             │",
    " │   j / k       Jump to Next / Previous card                  │",
    " │                                                             │",
    " │ Card Operations                                             │",
    " │   H / L       Move card to Left / Right bucket              │",
    " │   J / K       Reorder card Down / Up                        │",
    " │   m           Move card to any bucket (picker)              │",
    " │   <Space>     Toggle Done / Undone                          │",
    " │   <CR>        Open full Details & Markdown Editor           │",
    " │   e           Quick edit task title                         │",
    " │   i           View / preview task images (Kitty protocol)   │",
    " │   I           Attach image file to task                     │",
    " │   a / o       Create new task in current bucket             │",
    " │   d           Delete task (with confirmation)               │",
    " │                                                             │",
    " │ Board Actions                                               │",
    " │   p           Switch Project                                │",
    " │   r           Refresh board from Vikunja API                │",
    " │   ?           Show this Help cheat sheet                    │",
    " │   q           Close Kanban tab                              │",
    " ╰─────────────────────────────────────────────────────────────╯",
  }

  local width = 65
  local height = #help_lines
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "none",
  })

  local close_fn = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close_fn, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close_fn, { buffer = buf, silent = true })
  vim.keymap.set("n", "?", close_fn, { buffer = buf, silent = true })
end

function M.open_project(project, view)
  M.state.project = project
  M.state.view = view

  -- If view not specified, pick kanban view
  if not view and project.views then
    for _, v in ipairs(project.views) do
      if v.view_kind == "kanban" then
        M.state.view = v
        break
      end
    end
    if not M.state.view and #project.views > 0 then
      M.state.view = project.views[1]
    end
  end

  if not M.state.view then
    utils.notify("No Kanban view found for project " .. project.title, vim.log.levels.ERROR)
    return
  end

  -- Check or open tab
  if not M.state.tabpage or not vim.api.nvim_tabpage_is_valid(M.state.tabpage) then
    vim.cmd("tabnew")
    M.state.tabpage = vim.api.nvim_get_current_tabpage()
  else
    vim.api.nvim_set_current_tabpage(M.state.tabpage)
  end

  utils.setup_highlights()
  utils.notify("Loading Kanban for " .. project.title .. "...", vim.log.levels.INFO)

  api.get_view_tasks(project.id, M.state.view.id, function(buckets, err)
    if err then
      utils.notify("Failed to load tasks: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    M.state.buckets = buckets or {}

    -- Close any extra windows in the current tab
    local cur_wins = vim.api.nvim_tabpage_list_wins(M.state.tabpage)
    local first_win = cur_wins[1]

    M.state.column_windows = {}
    M.state.column_buffers = {}
    M.state.card_maps = {}

    local num_buckets = #M.state.buckets
    if num_buckets == 0 then
      utils.notify("No buckets found in this Kanban view.", vim.log.levels.WARN)
      return
    end

    -- Create windows
    vim.api.nvim_set_current_win(first_win)
    local b1 = vim.api.nvim_create_buf(false, true)
    vim.bo[b1].buftype = "nofile"
    vim.bo[b1].bufhidden = "wipe"
    vim.bo[b1].swapfile = false
    vim.api.nvim_win_set_buf(first_win, b1)

    table.insert(M.state.column_windows, first_win)
    table.insert(M.state.column_buffers, b1)
    setup_buffer_keymaps(b1)

    for i = 2, num_buckets do
      vim.cmd("rightbelow vsplit")
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].swapfile = false
      vim.api.nvim_win_set_buf(win, buf)

      table.insert(M.state.column_windows, win)
      table.insert(M.state.column_buffers, buf)
      setup_buffer_keymaps(buf)
    end

    -- Configure window options
    for _, win in ipairs(M.state.column_windows) do
      vim.wo[win].wrap = false
      vim.wo[win].cursorline = true
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = "no"
    end

    -- Equalize window widths
    vim.cmd("wincmd =")

    -- Render all columns
    M.render_all()

    -- Focus first column
    vim.api.nvim_set_current_win(M.state.column_windows[1])
    jump_to_card(1)
  end)
end

function M.refresh()
  if not M.state.project or not M.state.view then
    return
  end

  api.get_view_tasks(M.state.project.id, M.state.view.id, function(buckets, err)
    if err then
      utils.notify("Refresh failed: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    M.state.buckets = buckets or {}
    M.render_all()
    utils.notify("Board refreshed.", vim.log.levels.INFO)
  end)
end

function M.select_project()
  api.get_projects(function(projects, err)
    if err or not projects then
      utils.notify("Failed to get projects: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    local items = {}
    for idx, p in ipairs(projects) do
      local title = p.title or "Untitled"
      if p.identifier and p.identifier ~= "" then
        title = "[" .. p.identifier .. "] " .. title
      end
      table.insert(items, title)
    end

    vim.ui.select(items, { prompt = "Select Vikunja Project:" }, function(choice, idx)
      if idx and projects[idx] then
        M.open_project(projects[idx])
      end
    end)
  end)
end

return M
