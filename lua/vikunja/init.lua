local M = {}
local config = require("vikunja.config")
local board = require("vikunja.board")
local api = require("vikunja.api")
local utils = require("vikunja.utils")

function M.setup(opts)
  config.setup(opts)
  utils.setup_highlights()

  vim.api.nvim_create_user_command("VikunjaKanban", function(args)
    local arg = args.args
    if arg and arg ~= "" then
      local pid = tonumber(arg)
      if pid then
        M.open_by_id(pid)
        return
      end
    end
    M.open()
  end, {
    nargs = "?",
    desc = "Open Vikunja Kanban Board",
  })

  vim.api.nvim_create_user_command("Vikunja", function(args)
    vim.cmd("VikunjaKanban " .. (args.args or ""))
  end, {
    nargs = "?",
    desc = "Open Vikunja Kanban Board",
  })

  vim.api.nvim_create_user_command("VikunjaProjects", function()
    M.select_project()
  end, {
    desc = "Select Vikunja Project",
  })

  vim.api.nvim_create_user_command("VikunjaSetToken", function()
    config.prompt_token(function(tok)
      if tok then
        utils.notify("Token updated successfully.", vim.log.levels.INFO)
      end
    end)
  end, {
    desc = "Interactively set Vikunja API token",
  })
end

function M.open()
  if config.options.default_project_id then
    M.open_by_id(config.options.default_project_id)
    return
  end

  api.get_projects(function(projects, err)
    if err or not projects or #projects == 0 then
      utils.notify("No projects available or failed to load: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    -- If there is a favorite project, pick the first favorite
    local fav
    for _, p in ipairs(projects) do
      if p.is_favorite then
        fav = p
        break
      end
    end

    if fav then
      board.open_project(fav)
    else
      board.select_project()
    end
  end)
end

function M.open_by_id(project_id)
  api.get_projects(function(projects, err)
    if err or not projects then
      utils.notify("Failed to load projects: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    for _, p in ipairs(projects) do
      if p.id == project_id then
        board.open_project(p)
        return
      end
    end

    utils.notify("Project with ID " .. project_id .. " not found.", vim.log.levels.ERROR)
  end)
end

function M.select_project()
  board.select_project()
end

function M.refresh()
  board.refresh()
end

return M
