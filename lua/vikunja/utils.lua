local M = {}

function M.html_to_markdown(html)
  if not html or html == "" then
    return ""
  end

  local s = html

  -- Headers
  s = s:gsub("<h1[^>]*>(.-)</h1>", "# %1\n\n")
  s = s:gsub("<h2[^>]*>(.-)</h2>", "## %1\n\n")
  s = s:gsub("<h3[^>]*>(.-)</h3>", "### %1\n\n")
  s = s:gsub("<h4[^>]*>(.-)</h4>", "#### %1\n\n")

  -- Formatting
  s = s:gsub("<strong[^>]*>(.-)</strong>", "**%1**")
  s = s:gsub("<b[^>]*>(.-)</b>", "**%1**")
  s = s:gsub("<em[^>]*>(.-)</em>", "*%1*")
  s = s:gsub("<i[^>]*>(.-)</i>", "*%1*")
  s = s:gsub("<code[^>]*>(.-)</code>", "`%1`")
  s = s:gsub("<s[^>]*>(.-)</s>", "~~%1~~")
  s = s:gsub("<del[^>]*>(.-)</del>", "~~%1~~")

  -- Links
  s = s:gsub('<a[^>]*href="([^"]+)"[^>]*>(.-)</a>', "[%2](%1)")

  -- Lists
  s = s:gsub("<li[^>]*>(.-)</li>", "- %1\n")
  s = s:gsub("<ul[^>]*>", "")
  s = s:gsub("</ul>", "\n")
  s = s:gsub("<ol[^>]*>", "")
  s = s:gsub("</ol>", "\n")

  -- Paragraphs & line breaks
  s = s:gsub("<br%s*/?>", "\n")
  s = s:gsub("<p[^>]*>(.-)</p>", "%1\n\n")

  -- Blockquotes
  s = s:gsub("<blockquote[^>]*>(.-)</blockquote>", "> %1\n\n")

  -- Decode common HTML entities
  s = s:gsub("&nbsp;", " ")
  s = s:gsub("&quot;", '"')
  s = s:gsub("&apos;", "'")
  s = s:gsub("&lt;", "<")
  s = s:gsub("&gt;", ">")
  s = s:gsub("&amp;", "&")

  -- Remove remaining HTML tags
  s = s:gsub("<[^>]+>", "")

  -- Clean up excess blank lines
  s = s:gsub("\n\n\n+", "\n\n")
  s = vim.trim(s)

  return s
end

function M.markdown_to_html(md)
  if not md or md == "" then
    return ""
  end

  local lines = vim.split(md, "\n")
  local out = {}
  local in_list = false

  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed == "" then
      if in_list then
        table.insert(out, "</ul>")
        in_list = false
      end
    elseif trimmed:match("^%-%s+(.+)$") then
      if not in_list then
        table.insert(out, "<ul>")
        in_list = true
      end
      local item = trimmed:match("^%-%s+(.+)$")
      table.insert(out, "<li><p>" .. item .. "</p></li>")
    elseif trimmed:match("^###%s+(.+)$") then
      if in_list then
        table.insert(out, "</ul>")
        in_list = false
      end
      table.insert(out, "<h3>" .. trimmed:match("^###%s+(.+)$") .. "</h3>")
    elseif trimmed:match("^##%s+(.+)$") then
      if in_list then
        table.insert(out, "</ul>")
        in_list = false
      end
      table.insert(out, "<h2>" .. trimmed:match("^##%s+(.+)$") .. "</h2>")
    elseif trimmed:match("^#%s+(.+)$") then
      if in_list then
        table.insert(out, "</ul>")
        in_list = false
      end
      table.insert(out, "<h1>" .. trimmed:match("^#%s+(.+)$") .. "</h1>")
    else
      if in_list then
        table.insert(out, "</ul>")
        in_list = false
      end
      table.insert(out, "<p>" .. trimmed .. "</p>")
    end
  end

  if in_list then
    table.insert(out, "</ul>")
  end

  return table.concat(out, "")
end

function M.format_date(iso_str)
  if not iso_str or iso_str == "" or vim.startswith(iso_str, "0001") then
    return nil
  end
  return iso_str:sub(1, 10)
end

function M.priority_info(priority)
  local p = tonumber(priority) or 0
  if p <= 0 then
    return { level = 0, name = "None", hl = "Comment" }
  elseif p == 1 then
    return { level = 1, name = "Low", hl = "VikunjaPriorityLow" }
  elseif p == 2 then
    return { level = 2, name = "Medium", hl = "VikunjaPriorityMedium" }
  elseif p == 3 then
    return { level = 3, name = "High", hl = "VikunjaPriorityHigh" }
  else
    return { level = 4, name = "Urgent", hl = "VikunjaPriorityUrgent" }
  end
end

function M.setup_highlights()
  local defs = {
    VikunjaBucketHeader = { link = "Title", default = true, bold = true },
    VikunjaBucketCount = { link = "Number", default = true },
    VikunjaCardBorder = { link = "Comment", default = true },
    VikunjaCardBorderActive = { link = "Function", default = true, bold = true },
    VikunjaCardId = { link = "Directory", default = true, bold = true },
    VikunjaCardTitle = { link = "Normal", default = true },
    VikunjaCardTitleDone = { link = "Comment", default = true, strikethrough = true },
    VikunjaDueDate = { link = "DiagnosticWarn", default = true },
    VikunjaPriorityLow = { link = "DiagnosticInfo", default = true },
    VikunjaPriorityMedium = { link = "DiagnosticWarn", default = true },
    VikunjaPriorityHigh = { link = "DiagnosticError", default = true, bold = true },
    VikunjaPriorityUrgent = { link = "ErrorMsg", default = true, bold = true },
    VikunjaHelpKey = { link = "Special", default = true, bold = true },
    VikunjaHelpDesc = { link = "Normal", default = true },
  }

  for name, opts in pairs(defs) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Vikunja" })
end

return M
