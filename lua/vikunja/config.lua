local M = {}

M.defaults = {
  base_url = "",
  token = nil,
  token_file = vim.fn.expand("~/.local/share/vikunja/token"),
  default_project_id = nil,
  column_min_width = 30,
  icons = {
    task = "󰄱 ",
    task_done = "󰄵 ",
    due = "󰥔 ",
    priority_low = "󰘄 ",
    priority_medium = "󰁪 ",
    priority_high = "󰀨 ",
    priority_urgent = "󰚌 ",
    subtasks = "󰙅 ",
    attachment = "󰁦 ",
  },
  keymaps = {
    next_column = "l",
    prev_column = "h",
    next_card = "j",
    prev_card = "k",
    move_card_next = "L",
    move_card_prev = "H",
    reorder_down = "J",
    reorder_up = "K",
    move_to_bucket = "m",
    toggle_done = "<space>",
    create_task = "a",
    edit_task = "<CR>",
    quick_edit = "e",
    delete_task = "d",
    switch_project = "p",
    refresh = "r",
    help = "?",
    close = "q",
  },
}

M.options = vim.tbl_deep_extend("force", {}, M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  if M.options.token_file then
    M.options.token_file = vim.fn.expand(M.options.token_file)
  end
  if os.getenv("VIKUNJA_URL") and os.getenv("VIKUNJA_URL") ~= "" then
    M.options.base_url = os.getenv("VIKUNJA_URL")
  end
  if os.getenv("VIKUNJA_TOKEN") and os.getenv("VIKUNJA_TOKEN") ~= "" then
    M.options.token = os.getenv("VIKUNJA_TOKEN")
  end
end

function M.get_token(cb)
  if type(M.options.token) == "function" then
    local t = M.options.token()
    if t and t ~= "" then
      cb(t)
      return
    end
  elseif type(M.options.token) == "string" and M.options.token ~= "" then
    cb(M.options.token)
    return
  end

  local env_token = os.getenv("VIKUNJA_TOKEN")
  if env_token and env_token ~= "" then
    M.options.token = env_token
    cb(env_token)
    return
  end

  local token_file = M.options.token_file
  if token_file and vim.fn.filereadable(token_file) == 1 then
    local lines = vim.fn.readfile(token_file)
    if #lines > 0 and vim.trim(lines[1]) ~= "" then
      local t = vim.trim(lines[1])
      M.options.token = t
      cb(t)
      return
    end
  end

  M.prompt_token(cb)
end

function M.prompt_token(cb)
  vim.ui.input({ prompt = "Vikunja API Token: " }, function(input)
    if not input or vim.trim(input) == "" then
      if cb then
        cb(nil)
      end
      return
    end

    input = vim.trim(input)
    M.options.token = input

    vim.ui.select({ "Yes, save locally (chmod 600, outside git)", "No, keep for this Neovim session only" }, {
      prompt = "Persist token to " .. tostring(M.options.token_file) .. "?",
    }, function(choice)
      if choice and choice:match("^Yes") and M.options.token_file then
        local dir = vim.fs.dirname(M.options.token_file)
        vim.fn.mkdir(dir, "p")
        vim.fn.writefile({ input }, M.options.token_file)
        vim.fn.setfperm(M.options.token_file, "rw-------")
        vim.notify("Vikunja token saved securely to " .. M.options.token_file, vim.log.levels.INFO, { title = "Vikunja" })
      end

      if cb then
        cb(input)
      end
    end)
  end)
end

return M
