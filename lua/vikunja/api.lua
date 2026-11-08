local M = {}
local config = require("vikunja.config")
local utils = require("vikunja.utils")

local function request(method, endpoint, body, cb)
  config.get_token(function(token)
    if not token or token == "" then
      local err = "Vikunja API token is missing! Run :VikunjaSetToken or set $VIKUNJA_TOKEN."
      utils.notify(err, vim.log.levels.ERROR)
      if cb then
        cb(nil, err)
      end
      return
    end

    local base = config.options.base_url or ""
    if base == "" then
      local err = "Vikunja base_url is not set! Configure 'base_url' in setup({ base_url = '...' }) or set $VIKUNJA_URL."
      utils.notify(err, vim.log.levels.ERROR)
      if cb then
        cb(nil, err)
      end
      return
    end
    base = base:gsub("/+$", "")
    local url = base .. endpoint

    local args = {
      "curl",
      "-s",
      "-X",
      method,
      "-H",
      "Authorization: Bearer " .. token,
      "-H",
      "Content-Type: application/json",
    }

    if body ~= nil then
      table.insert(args, "-d")
      table.insert(args, vim.json.encode(body))
    end

    table.insert(args, url)

    vim.system(args, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          local err = "HTTP Request failed (" .. obj.code .. "): " .. (obj.stderr or "")
          utils.notify(err, vim.log.levels.ERROR)
          if cb then
            cb(nil, err)
          end
          return
        end

        if not obj.stdout or obj.stdout == "" then
          if cb then
            cb({}, nil)
          end
          return
        end

        local ok, res = pcall(vim.json.decode, obj.stdout)
        if not ok then
          local err = "Failed to parse JSON response: " .. tostring(res)
          utils.notify(err, vim.log.levels.ERROR)
          if cb then
            cb(nil, err)
          end
          return
        end

        -- Check for Vikunja error structure { message: "...", code: ... }
        if type(res) == "table" and res.message and not res.id and not vim.islist(res) then
          if res.message ~= "Successfully deleted." then
            local err = "Vikunja API Error: " .. tostring(res.message)
            utils.notify(err, vim.log.levels.ERROR)
            if cb then
              cb(nil, err)
            end
            return
          end
        end

        if cb then
          cb(res, nil)
        end
      end)
    end)
  end)
end

function M.get_projects(cb)
  request("GET", "/projects", nil, cb)
end

function M.get_project_views(project_id, cb)
  request("GET", "/projects/" .. project_id .. "/views", nil, cb)
end

function M.get_view_tasks(project_id, view_id, cb)
  request("GET", "/projects/" .. project_id .. "/views/" .. view_id .. "/tasks", nil, cb)
end

function M.create_task(project_id, data, cb)
  request("PUT", "/projects/" .. project_id .. "/tasks", data, cb)
end

function M.update_task(task_id, data, cb)
  request("POST", "/tasks/" .. task_id, data, cb)
end

function M.delete_task(task_id, cb)
  request("DELETE", "/tasks/" .. task_id, nil, cb)
end

function M.move_task_bucket(project_id, view_id, bucket_id, task_id, cb)
  local endpoint = string.format("/projects/%d/views/%d/buckets/%d/tasks", project_id, view_id, bucket_id)
  request("POST", endpoint, { task_id = task_id }, cb)
end

function M.update_task_position(task_id, view_id, position, cb)
  local endpoint = "/tasks/" .. task_id .. "/position"
  request("POST", endpoint, { project_view_id = view_id, position = position }, cb)
end

function M.create_bucket(project_id, view_id, title, cb)
  local endpoint = string.format("/projects/%d/views/%d/buckets", project_id, view_id)
  request("PUT", endpoint, { title = title }, cb)
end

function M.update_bucket(project_id, view_id, bucket_id, title, cb)
  local endpoint = string.format("/projects/%d/views/%d/buckets/%d", project_id, view_id, bucket_id)
  request("POST", endpoint, { title = title }, cb)
end

function M.delete_bucket(project_id, view_id, bucket_id, cb)
  local endpoint = string.format("/projects/%d/views/%d/buckets/%d", project_id, view_id, bucket_id)
  request("DELETE", endpoint, nil, cb)
end

function M.get_attachments(task_id, cb)
  request("GET", "/tasks/" .. task_id .. "/attachments", nil, cb)
end

function M.download_attachment(task_id, attachment_id, target_file, cb)
  config.get_token(function(token)
    if not token or token == "" then
      local err = "Vikunja API token is missing!"
      utils.notify(err, vim.log.levels.ERROR)
      if cb then
        cb(nil, err)
      end
      return
    end

    local base = (config.options.base_url or ""):gsub("/+$", "")
    if base == "" then
      local err = "Vikunja base_url is not set!"
      utils.notify(err, vim.log.levels.ERROR)
      if cb then
        cb(nil, err)
      end
      return
    end
    local url = string.format("%s/tasks/%d/attachments/%d", base, task_id, attachment_id)

    local parent = vim.fs.dirname(target_file)
    vim.fn.mkdir(parent, "p")

    local args = {
      "curl",
      "-s",
      "-H",
      "Authorization: Bearer " .. token,
      url,
      "-o",
      target_file,
    }

    vim.system(args, { text = false }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          local err = "Failed to download attachment: " .. (obj.stderr or "")
          utils.notify(err, vim.log.levels.ERROR)
          if cb then
            cb(nil, err)
          end
          return
        end

        if cb then
          cb(target_file, nil)
        end
      end)
    end)
  end)
end

function M.upload_attachment(task_id, file_path, cb)
  config.get_token(function(token)
    if not token or token == "" then
      local err = "Vikunja API token is missing!"
      utils.notify(err, vim.log.levels.ERROR)
      if cb then
        cb(nil, err)
      end
      return
    end

    local base = (config.options.base_url or ""):gsub("/+$", "")
    if base == "" then
      local err = "Vikunja base_url is not set!"
      utils.notify(err, vim.log.levels.ERROR)
      if cb then
        cb(nil, err)
      end
      return
    end
    local url = string.format("%s/tasks/%d/attachments", base, task_id)

    local args = {
      "curl",
      "-s",
      "-X",
      "PUT",
      "-H",
      "Authorization: Bearer " .. token,
      "-F",
      "files=@" .. file_path,
      url,
    }

    vim.system(args, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          local err = "Failed to upload attachment: " .. (obj.stderr or "")
          utils.notify(err, vim.log.levels.ERROR)
          if cb then
            cb(nil, err)
          end
          return
        end

        local ok, res = pcall(vim.json.decode, obj.stdout)
        if cb then
          cb(ok and res or obj.stdout, nil)
        end
      end)
    end)
  end)
end

return M
