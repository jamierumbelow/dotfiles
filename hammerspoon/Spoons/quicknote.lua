local function resolveVaultPath()
  local candidates = {
    "/Users/james.rumbelow/workspace/vault",
    "/Users/jamierumbelow/workspace/vault",
  }
  for _, path in ipairs(candidates) do
    local mode = hs.fs.attributes(path, "mode")
    if mode == "directory" then return path end
  end
  hs.printf("[quicknote] no vault directory found; tried: %s", table.concat(candidates, ", "))
  return nil
end

local CONFIG = {
  vaultPath            = resolveVaultPath(),
  dailyFolder          = "daily",        -- relative to vault; "" for vault root
  pathFormat           = "%Y/%m/%Y-%m-%d", -- note path under dailyFolder, sans .md
  dateFormat           = "%Y-%m-%d",     -- display only (save confirmation)
  heading              = "## Journal",   -- exact heading line to append under
  appendAtEndOfSection = true,           -- false = insert directly beneath the heading
  createIfMissing      = true,           -- create today's note (and heading) if absent
  timestamp            = true,           -- prefix entries with "HH:MM - "
  timeSeparator        = " - ",          -- between the timestamp and the note text
  hotkey               = { { "cmd", "shift" }, "n" },
  width                = 440,
  height               = 220,
  margin               = 14,
}

local DRAFT_KEY = "quicknote.draft"

---------------------------------------------------------------------------
-- File helpers
---------------------------------------------------------------------------

local function join(...)
  local parts = {}
  for _, p in ipairs({ ... }) do
    if p and p ~= "" then table.insert(parts, p) end
  end
  return table.concat(parts, "/")
end

local function dailyNotePath()
  return join(CONFIG.vaultPath, CONFIG.dailyFolder, os.date(CONFIG.pathFormat) .. ".md")
end

local function parentDir(path)
  return path:match("^(.*)/[^/]+$")
end

-- pathFormat nests notes under year/month, so create each missing level in turn.
local function mkdirp(dir)
  if not dir or dir == "" then return true end
  if hs.fs.attributes(dir, "mode") == "directory" then return true end
  local ok, err = mkdirp(parentDir(dir))
  if not ok then return nil, err end
  return hs.fs.mkdir(dir)
end

local function readFile(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local s = f:read("a")
  f:close()
  return s
end

-- Write to a temp file then rename, so a crash mid-write can't truncate the note.
local function writeFileAtomic(path, content)
  local tmp = path .. ".quicknote.tmp"
  local f, err = io.open(tmp, "w")
  if not f then return nil, "open temp failed: " .. tostring(err) end
  local ok, werr = f:write(content)
  f:close()
  if not ok then
    os.remove(tmp)
    return nil, "write failed: " .. tostring(werr)
  end
  local rok, rerr = os.rename(tmp, path)
  if not rok then
    os.remove(tmp)
    return nil, "rename failed: " .. tostring(rerr)
  end
  return true
end

local function splitLines(s)
  local lines = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do table.insert(lines, line) end
  -- gmatch above leaves a trailing empty element when s ends with "\n"; drop it
  if s:sub(-1) == "\n" and lines[#lines] == "" then table.remove(lines) end
  return lines
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function headingLevel(line)
  local hashes = line:match("^(#+)%s")
  return hashes and #hashes or nil
end

---------------------------------------------------------------------------
-- Section insertion
---------------------------------------------------------------------------

-- Returns the new file content with `entryLines` inserted into CONFIG.heading's section.
local function insertIntoSection(content, entryLines)
  local lines = splitLines(content)
  local target = trim(CONFIG.heading)
  local targetLevel = headingLevel(target) or 1

  local headingIdx
  for i, line in ipairs(lines) do
    if trim(line) == target then headingIdx = i; break end
  end

  if not headingIdx then
    if not CONFIG.createIfMissing then
      return nil, ("heading %q not found in note"):format(CONFIG.heading)
    end
    if #lines > 0 and trim(lines[#lines]) ~= "" then table.insert(lines, "") end
    table.insert(lines, CONFIG.heading)
    headingIdx = #lines
  end

  -- Section ends at the next heading of the same or higher level, or EOF.
  local sectionEnd = #lines + 1
  for i = headingIdx + 1, #lines do
    local lvl = headingLevel(lines[i])
    if lvl and lvl <= targetLevel then sectionEnd = i; break end
  end

  local insertAt
  if CONFIG.appendAtEndOfSection then
    -- Skip back over blank lines so the entry lands right after the last content line.
    insertAt = sectionEnd
    while insertAt - 1 > headingIdx and trim(lines[insertAt - 1]) == "" do
      insertAt = insertAt - 1
    end
  else
    insertAt = headingIdx + 1
  end

  for k = #entryLines, 1, -1 do
    table.insert(lines, insertAt, entryLines[k])
  end

  -- Blank line between the previous content and this entry, so entries don't run together.
  if insertAt > 1 and trim(lines[insertAt - 1]) ~= "" then
    table.insert(lines, insertAt, "")
  end

  return table.concat(lines, "\n") .. "\n"
end

local function buildEntry(text)
  local body = splitLines(trim(text))
  if #body == 0 then return nil end
  local prefix = ""
  if CONFIG.timestamp then prefix = os.date("%H:%M") .. CONFIG.timeSeparator end
  local out = { prefix .. body[1] }
  for i = 2, #body do
    table.insert(out, body[i])
  end
  return out
end

---------------------------------------------------------------------------
-- Commit
---------------------------------------------------------------------------

local function notifyError(msg)
  hs.notify.new({
    title = "Quick Note: not saved",
    informativeText = msg .. "\nYour draft is still in the box.",
    withdrawAfter = 0,
  }):send()
  print("[quicknote] ERROR: " .. msg)
end

local function commit(text)
  local entry = buildEntry(text)
  if not entry then
    hs.alert.show("Nothing to save")
    return false
  end

  if not CONFIG.vaultPath then
    notifyError("Vault not found at any known path; check resolveVaultPath().")
    return false
  end

  local path = dailyNotePath()
  local content = readFile(path)
  if not content then
    if not CONFIG.createIfMissing then
      notifyError("Today's note does not exist: " .. path)
      return false
    end
    local dir = parentDir(path)
    local ok, err = mkdirp(dir)
    if not ok then notifyError("Could not create folder " .. tostring(dir) .. ": " .. tostring(err)); return false end
    content = ""
  end

  local newContent, err = insertIntoSection(content, entry)
  if not newContent then notifyError(err); return false end

  local ok, werr = writeFileAtomic(path, newContent)
  if not ok then notifyError(werr .. " (" .. path .. ")"); return false end

  hs.alert.show("Saved to " .. os.date(CONFIG.dateFormat), 0.8)
  return true
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local box
local ucc = hs.webview.usercontent.new("quicknote")

local function hideBox()
  if box then box:hide() end
end

-- hs.json.encode only accepts tables, so string literals are escaped by hand.
local function jsString(s)
  local escaped = s:gsub('[\\"]', '\\%0')
                   :gsub("\n", "\\n")
                   :gsub("\r", "\\r")
                   :gsub("%c", function(c) return ("\\u%04x"):format(c:byte()) end)
  return '"' .. escaped .. '"'
end

local function setTextareaValue(value)
  box:evaluateJavaScript(("document.getElementById('t').value = %s;"):format(jsString(value)))
end

ucc:setCallback(function(msg)
  local body = msg.body or {}
  if body.action == "commit" then
    if commit(body.text or "") then
      hs.settings.set(DRAFT_KEY, "")
      -- The note is already on disk; a failure clearing the box must not keep it open.
      local ok, err = pcall(setTextareaValue, "")
      if not ok then print("[quicknote] could not clear textarea: " .. tostring(err)) end
      hideBox()
    end
  elseif body.action == "hide" then
    hideBox()
  elseif body.action == "draft" then
    hs.settings.set(DRAFT_KEY, body.text or "")
  end
end)

local HTML = [[
<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;height:100%;background:#1e1e22;color:#e8e8ea;
    font:14px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;}
  body{display:flex;flex-direction:column;padding:10px;box-sizing:border-box;}
  textarea{flex:1;resize:none;border:1px solid #3a3a42;border-radius:8px;
    background:#26262c;color:inherit;font:inherit;padding:10px;outline:none;line-height:1.4;}
  textarea:focus{border-color:#7c6cf0;}
  .hint{margin-top:8px;font-size:11px;color:#8a8a94;display:flex;justify-content:space-between;}
  kbd{background:#33333b;border-radius:4px;padding:1px 5px;font:inherit;}
</style></head><body>
<textarea id="t" placeholder="Note for today…" autofocus spellcheck="true"></textarea>
<div class="hint"><span><kbd>⌘↩</kbd> save</span><span><kbd>esc</kbd> hide (keeps draft)</span></div>
<script>
  const t = document.getElementById('t');
  const post = (action) => webkit.messageHandlers.quicknote.postMessage({action, text: t.value});
  t.addEventListener('keydown', (e) => {
    if (e.metaKey && e.key === 'Enter') { e.preventDefault(); post('commit'); }
    else if (e.key === 'Escape') { e.preventDefault(); post('hide'); }
  });
  t.addEventListener('input', () => post('draft'));
  window.focusBox = () => { t.focus(); t.setSelectionRange(t.value.length, t.value.length); };
</script>
</body></html>
]]

local function topRightFrame()
  local s = hs.screen.mainScreen():frame()
  return hs.geometry.rect(
    s.x + s.w - CONFIG.width - CONFIG.margin,
    s.y + CONFIG.margin,
    CONFIG.width,
    CONFIG.height
  )
end

local function buildBox()
  box = hs.webview.new(topRightFrame(), { developerExtrasEnabled = false }, ucc)
    :windowStyle({ "titled", "utility" })
    :windowTitle("Quick Note")
    :level(hs.drawing.windowLevels.floating)
    :allowTextEntry(true)
    :shadow(true)
    :deleteOnClose(false)
    :html(HTML)
end

local function showBox()
  if not box then buildBox() end
  box:frame(topRightFrame()):show():bringToFront()
  hs.timer.doAfter(0.05, function()
    local w = box:hswindow()
    if w then w:focus() end
    local draft = hs.settings.get(DRAFT_KEY)
    if draft and draft ~= "" then
      box:evaluateJavaScript(
        ("if(!document.getElementById('t').value){document.getElementById('t').value=%s;}"):format(jsString(draft)))
    end
    box:evaluateJavaScript("focusBox();")
  end)
end

local function toggleBox()
  local front = hs.application.frontmostApplication()
  local hsIsFront = front and front:bundleID() == "org.hammerspoon.Hammerspoon"
  if box and box:isVisible() and hsIsFront then
    hideBox()
  else
    showBox()
  end
end

hs.hotkey.bind(CONFIG.hotkey[1], CONFIG.hotkey[2], toggleBox)
buildBox()
print("[quicknote] loaded; writing to " .. dailyNotePath())