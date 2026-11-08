local M = {}
local api = require("vikunja.api")
local utils = require("vikunja.utils")
local images = require("vikunja.images")

function M.open(task, project, view, on_saved)
  local width = math.min(95, math.floor(vim.o.columns * 0.8))
  local height = math.min(35, math.floor(vim.o.lines * 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"

  local md_desc = utils.html_to_markdown(task.description or "")
  local due_str = utils.format_date(task.due_date) or ""

  local lines = {
    "---",
    "title: " .. (task.title or ""),
    "done: " .. tostring(task.done or false),
    "priority: " .. tostring(task.priority or 0) .. "  # 0=None, 1=Low, 2=Med, 3=High, 4=Urg",
    "due_date: " .. due_str,
    "---",
    "",
  }

  if md_desc ~= "" then
    for _, l in ipairs(vim.split(md_desc, "\n")) do
      table.insert(lines, l)
    end
  else
    table.insert(lines, "# Notes")
    table.insert(lines, "")
  end

  local atts = (type(task.attachments) == "table") and task.attachments or {}
  if #atts > 0 then
    table.insert(lines, "")
    table.insert(lines, "## Attachments")
    for _, att in ipairs(atts) do
      local path = images.get_attachment_path(task.id, att)
      local name = (att.file and att.file.name) or ("attachment_" .. att.id)
      table.insert(lines, string.format("![%s](%s)", name, path))
    end
    table.insert(lines, "")

    images.ensure_all_attachments(task, function()
      vim.schedule(function()
        local ok, snacks = pcall(require, "snacks")
        if ok and snacks.image and vim.api.nvim_buf_is_valid(buf) then
          pcall(snacks.image.doc.update, buf)
        end
      end)
    end)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  local task_id_display = task.identifier ~= "" and task.identifier or ("#" .. tostring(task.id))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Task [" .. task_id_display .. "] ",
    title_pos = "center",
    footer = " [C-s] Save  |  [i] Images  |  [I] Attach  |  [q/Esc] Close ",
    footer_pos = "right",
  })

  local function save_task(close_after)
    local cur_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local in_fm = false
    local fm_done = false
    local title = task.title
    local done = task.done
    local priority = task.priority
    local due_date = due_str
    local body_lines = {}

    for _, line in ipairs(cur_lines) do
      if not fm_done then
        if line == "---" then
          if not in_fm then
            in_fm = true
          else
            in_fm = false
            fm_done = true
          end
        elseif in_fm then
          local k, v = line:match("^([%w_]+):%s*(.*)$")
          if k and v then
            -- Strip trailing comments
            v = v:gsub("%s*#.*$", "")
            v = vim.trim(v)
            if k == "title" then
              title = v
            elseif k == "done" then
              done = (v == "true")
            elseif k == "priority" then
              priority = tonumber(v) or priority
            elseif k == "due_date" then
              due_date = v
            end
          end
        end
      else
        table.insert(body_lines, line)
      end
    end

    local raw_body = vim.trim(table.concat(body_lines, "\n"))
    local new_desc = utils.markdown_to_html(raw_body)

    local payload = {
      title = title,
      done = done,
      priority = priority,
      description = new_desc,
    }

    if due_date and due_date ~= "" then
      -- If user input YYYY-MM-DD, convert to ISO 8601
      if due_date:match("^%d%d%d%d%-%d%d%-%d%d$") then
        payload.due_date = due_date .. "T23:59:59Z"
      else
        payload.due_date = due_date
      end
    else
      payload.due_date = "0001-01-01T00:00:00Z"
    end

    utils.notify("Saving task #" .. task.id .. "...", vim.log.levels.INFO)
    api.update_task(task.id, payload, function(res, err)
      if err then
        utils.notify("Error saving task: " .. tostring(err), vim.log.levels.ERROR)
        return
      end

      vim.bo[buf].modified = false
      utils.notify("Task updated successfully!", vim.log.levels.INFO)

      if on_saved then
        on_saved(res)
      end

      if close_after and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)
  end

  local function close_modal()
    if vim.bo[buf].modified then
      vim.ui.select({ "Save and Close", "Discard Changes", "Cancel" }, {
        prompt = "Task has unsaved changes:",
      }, function(choice)
        if choice == "Save and Close" then
          save_task(true)
        elseif choice == "Discard Changes" then
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
        end
      end)
    else
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      save_task(false)
    end,
  })

  local map_opts = { buffer = buf, silent = true, noremap = true }
  vim.keymap.set("n", "q", close_modal, map_opts)
  vim.keymap.set("n", "<Esc>", close_modal, map_opts)
  vim.keymap.set("n", "i", function()
    images.show_task_images(task)
  end, map_opts)
  vim.keymap.set("n", "I", function()
    images.upload_task_image(task, function()
      api.get_attachments(task.id, function(atts)
        task.attachments = atts
        utils.notify("Attachment list refreshed.", vim.log.levels.INFO)
      end)
    end)
  end, map_opts)
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    save_task(false)
  end, map_opts)
  vim.keymap.set("n", "<leader>s", function()
    save_task(false)
  end, map_opts)
end

return M
