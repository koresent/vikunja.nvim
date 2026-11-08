local M = {}
local api = require("vikunja.api")
local utils = require("vikunja.utils")

M.cache_dir = vim.fn.expand("~/.cache/nvim/vikunja/images")

function M.get_attachment_path(task_id, att)
  local fname = (att.file and att.file.name) or ("attachment_" .. att.id .. ".jpg")
  fname = fname:gsub("[^%w%.%-_]", "_")
  return string.format("%s/%s/%s_%s", M.cache_dir, tostring(task_id), tostring(att.id), fname)
end

function M.ensure_downloaded(task_id, att, cb)
  local path = M.get_attachment_path(task_id, att)
  if vim.fn.filereadable(path) == 1 and vim.fn.getfsize(path) > 0 then
    cb(path, nil)
    return
  end

  utils.notify("Downloading image " .. (att.file and att.file.name or "") .. "...", vim.log.levels.INFO)
  api.download_attachment(task_id, att.id, path, function(saved_path, err)
    if err then
      cb(nil, err)
      return
    end
    cb(saved_path, nil)
  end)
end

function M.ensure_all_attachments(task, cb)
  local atts = (type(task.attachments) == "table") and task.attachments or {}
  if #atts == 0 then
    cb({})
    return
  end

  local results = {}
  local pending = #atts

  for _, att in ipairs(atts) do
    M.ensure_downloaded(task.id, att, function(path, err)
      if path then
        table.insert(results, {
          path = path,
          name = att.file and att.file.name or "image",
          attachment = att,
        })
      end
      pending = pending - 1
      if pending == 0 then
        cb(results)
      end
    end)
  end
end

function M.preview_image(file_path, title)
  if vim.fn.filereadable(file_path) ~= 1 then
    utils.notify("Image file not found: " .. tostring(file_path), vim.log.levels.ERROR)
    return
  end

  local width = math.min(100, math.floor(vim.o.columns * 0.85))
  local height = math.min(35, math.floor(vim.o.lines * 0.85))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = "  " .. (title or vim.fs.basename(file_path)) .. " ",
    title_pos = "center",
    footer = " [q/Esc] Close ",
    footer_pos = "right",
  })

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.image then
    if not snacks.image.config.enabled then
      pcall(snacks.image.setup, {})
    end
    pcall(snacks.image.buf._attach, buf, { src = file_path })
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "",
      "  Image: " .. file_path,
      "  Size:  " .. vim.fn.getfsize(file_path) .. " bytes",
      "",
      "  (snacks.image not loaded, open in external viewer if needed)",
    })
  end

  local function close_fn()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close_fn, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close_fn, { buffer = buf, silent = true })
end

function M.show_task_images(task)
  local atts = (type(task.attachments) == "table") and task.attachments or {}
  local image_atts = {}

  for _, att in ipairs(atts) do
    local mime = att.file and att.file.mime or ""
    local name = att.file and att.file.name or ""
    if mime:find("^image/") or name:match("%.png$") or name:match("%.jpe?g$") or name:match("%.webp$") or name:match("%.gif$") then
      table.insert(image_atts, att)
    end
  end

  if #image_atts == 0 then
    utils.notify("Task #" .. task.id .. " has no image attachments.", vim.log.levels.WARN)
    return
  end

  if #image_atts == 1 then
    local att = image_atts[1]
    M.ensure_downloaded(task.id, att, function(path, err)
      if err then
        utils.notify("Failed to open image: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      M.preview_image(path, (task.identifier ~= "" and task.identifier or ("#" .. task.id)) .. " - " .. (att.file and att.file.name or "Cover"))
    end)
  else
    local items = {}
    for idx, att in ipairs(image_atts) do
      local name = att.file and att.file.name or ("attachment_" .. att.id)
      local is_cover = (task.cover_image_attachment_id == att.id) and " ★ (Cover)" or ""
      table.insert(items, string.format("%d. %s%s", idx, name, is_cover))
    end

    vim.ui.select(items, { prompt = "Select Image to View:" }, function(choice, idx)
      if idx and image_atts[idx] then
        local att = image_atts[idx]
        M.ensure_downloaded(task.id, att, function(path, err)
          if err then
            utils.notify("Failed to load image: " .. tostring(err), vim.log.levels.ERROR)
            return
          end
          M.preview_image(path, (task.identifier ~= "" and task.identifier or ("#" .. task.id)) .. " - " .. (att.file and att.file.name or "Image"))
        end)
      end
    end)
  end
end

function M.upload_task_image(task, cb)
  vim.ui.input({ prompt = "Path to image file to attach: ", completion = "file" }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end

    local expanded = vim.fn.expand(vim.trim(input))
    if vim.fn.filereadable(expanded) ~= 1 then
      utils.notify("File not found: " .. expanded, vim.log.levels.ERROR)
      return
    end

    utils.notify("Uploading " .. vim.fs.basename(expanded) .. "...", vim.log.levels.INFO)
    api.upload_attachment(task.id, expanded, function(res, err)
      if err then
        utils.notify("Upload failed: " .. tostring(err), vim.log.levels.ERROR)
        return
      end

      utils.notify("Attachment uploaded successfully!", vim.log.levels.INFO)
      if cb then
        cb(res)
      end
    end)
  end)
end

return M
