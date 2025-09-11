-- OmniFocus helpers: capture selected text or Mail message to OmniFocus inbox

local of = {}

local function trim(s)
	return s and (s:gsub("^%s+", ""):gsub("%s+$", "")) or s
end

local function encodeAppleScriptString(s)
	if not s then
		return ""
	end
	-- Escape backslashes and quotes for embedding into AppleScript string literals
	s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
	-- AppleScript can handle newlines in quoted strings
	return s
end

local function applescript(script)
	local ok, result, err = hs.osascript.applescript(script)
	return ok, result, err
end

local function ellipsize(s, max)
	s = s or ""
	if #s <= max then
		return s
	end
	return s:sub(1, math.max(0, max - 1)) .. "…"
end

local function firstLine(s)
	s = s or ""
	local line = s:match("([^\r\n]*)") or ""
	return line
end

local function createOmniFocusTask(title, note, projectName)
    local titleEsc = encodeAppleScriptString(title)
    local noteEsc = encodeAppleScriptString(note)
    local script
    if projectName and projectName ~= "" and projectName ~= "Inbox" then
        local projEsc = encodeAppleScriptString(projectName)
        script = string.format([[set theTaskName to "%s"
set theNote to "%s"
set theProjectName to "%s"
tell application "OmniFocus"
    tell default document
        set theTask to missing value
        try
            set theProj to first flattened project whose name is theProjectName
            set theTask to make new task with properties {name:theTaskName, note:theNote} at end of tasks of theProj
        on error
            set theTask to make new inbox task with properties {name:theTaskName, note:theNote}
        end try
    end tell
end tell]], titleEsc, noteEsc, projEsc)
    else
        script = string.format([[set theTaskName to "%s"
set theNote to "%s"
tell application "OmniFocus"
    tell default document
        make new inbox task with properties {name:theTaskName, note:theNote}
    end tell
end tell]], titleEsc, noteEsc)
    end

    local ok, _, err = hs.osascript.applescript(script)
    if not ok then
        hs.alert.show("Failed to add to OmniFocus: " .. tostring(err))
        return
    end

    hs.alert.show("Captured to OmniFocus")
end

local function getOmniFocusProjectNames()
    local script = [[tell application "OmniFocus"
    tell default document
        try
            set nameList to name of flattened projects
            return nameList
        on error
            return {}
        end try
    end tell
end tell]]
    local ok, result = applescript(script)
    if not ok then return {} end
    local t = {}
    if type(result) == "table" then
        t = result
    elseif type(result) == "string" and result ~= "" then
        t = { result }
    end
    table.sort(t, function(a,b)
        return tostring(a):lower() < tostring(b):lower()
    end)
    return t
end

-- Minimal inline prompt without chooser hotkey hints
local function htmlEscape(s)
	s = s or ""
	s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
	return s
end

local function showCapturePrompt(defaultTitle, defaultBody, projectNames, defaultProject, onSubmit, onCancel)
    local screen = hs.screen.mainScreen():frame()
    local width, height = 720, 520
	local rect = {
		x = screen.x + (screen.w - width) / 2,
		y = screen.y + (screen.h - height) / 4,
		w = width,
		h = height,
	}

	local uc = hs.webview.usercontent.new("ofPrompt")
	uc:setCallback(function(msg)
		if not msg or not msg.body then
			return
		end
		local event = msg.body.event
		if event == "submit" then
			local title = trim((msg.body.title or ""))
			local body = msg.body.body or ""
			local project = msg.body.project or "Inbox"
			if title ~= "" then
				onSubmit(title, body, project)
			end
		elseif event == "cancel" then
			if onCancel then
				onCancel()
			end
		end
	end)

    -- Build project options HTML
    local opts = {}
    local def = defaultProject or "Inbox"
    local function addOption(name)
        local selected = (name == def) and " selected" or ""
        table.insert(opts, string.format('<option value="%s"%s>%s</option>', htmlEscape(name), selected, htmlEscape(name)))
    end
    addOption("Inbox")
    if type(projectNames) == "table" then
        for _, n in ipairs(projectNames) do
            if n and n ~= "" then addOption(tostring(n)) end
        end
    end
    local optionsHTML = table.concat(opts, "")

    local html = [[
<!doctype html>
<html>
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  html,body{margin:0;padding:0;background:#ededed;color:#111;font:16px -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;}
  .wrap{display:flex;flex-direction:column;gap:10px;padding:12px 16px;height:100%%;box-sizing:border-box;}
  .row{display:flex;align-items:center;}
  .label{font-size:12px;color:#5f6368;margin-bottom:4px;}
  .title{flex:1;border:none;outline:none;background:#fff;border-radius:8px;padding:10px 12px;font-size:20px;font-weight:600;box-shadow: inset 0 0 0 1px #d0d0d0;}
  .title::placeholder{color:#9aa0a6;font-weight:500;}
  .project{flex:1;border:none;outline:none;background:#fff;border-radius:8px;padding:9px 12px;font-size:14px;box-shadow: inset 0 0 0 1px #d0d0d0;}
  .body{flex:1;min-height:360px;border:none;outline:none;background:#fff;border-radius:8px;padding:10px 12px;font-size:14px;line-height:1.4;box-shadow: inset 0 0 0 1px #d0d0d0;resize:vertical;}
  .hint{font-size:11px;color:#80868b;}
</style>
</head>
<body>
  <div class="wrap">
    <div class="row" style="flex-direction:column;align-items:stretch;">
      <div class="label">Title</div>
      <input id="title" class="title" type="text" spellcheck="false" autocomplete="off" placeholder="Enter task title" value="%s"/>
    </div>
    <div class="row" style="gap:10px;">
      <div style="display:flex;flex-direction:column;flex:1;">
        <div class="label">Project</div>
        <select id="project" class="project">%s</select>
      </div>
    </div>
    <div class="row" style="flex-direction:column;align-items:stretch;flex:1;">
      <div class="label">Selection</div>
      <textarea id="body" class="body" spellcheck="false">%s</textarea>
      <div class="hint">Enter to submit (when in Title). Cmd+Enter always submits. Esc cancels.</div>
    </div>
  </div>
  <script>
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ofPrompt;
    function send(event, payload){ if(handler){ handler.postMessage(Object.assign({event}, payload||{})); } }
    const input = document.getElementById('title');
    const body = document.getElementById('body');
    const project = document.getElementById('project');
    setTimeout(()=>{ input.focus(); input.select(); }, 0);
    document.addEventListener('keydown', (e)=>{
      if((e.metaKey || e.ctrlKey) && e.key === 'Enter'){
        send('submit', { title: input.value, body: body.value, project: project.value });
      } else if(e.key === 'Enter' && document.activeElement === input){
        send('submit', { title: input.value, body: body.value, project: project.value });
      }
      if(e.key === 'Escape'){ send('cancel', {}); }
    });
  </script>
</body>
</html>]]

    local w = hs.webview
        .new(rect, { developerExtrasEnabled = false }, uc)
		:shadow(true)
		:level(hs.drawing.windowLevels.modalPanel)
		:windowStyle({ "utility" })
		:allowTextEntry(true)
        :html(string.format(html, htmlEscape(defaultTitle or ""), optionsHTML, htmlEscape(defaultBody or "")))

	w:show()
	w:bringToFront(true)
	local hw = w:hswindow()
	if hw then
		hw:focus()
	end
	-- extra nudge after presentation to ensure keyboard focus
	hs.timer.doAfter(0.05, function()
		w:bringToFront(true)
		local h2 = w:hswindow()
		if h2 then
			h2:focus()
		end
		w:evaluateJavaScript("(function(){var i=document.getElementById('title'); if(i){ i.focus(); i.select(); }})();")
	end)

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		w:delete()
	end
	-- wrap submit/cancel to close the prompt
    local function submit(title, body, project)
        close()
        onSubmit(title, body, project)
    end
	local function cancel()
		close()
		if onCancel then
			onCancel()
		end
	end

    -- rebind callbacks with close behavior
    uc:setCallback(function(msg)
        if not msg or not msg.body then
            return
        end
        local event = msg.body.event
        if event == "submit" then
            local title = trim((msg.body.title or ""))
            local body = msg.body.body or ""
            local project = msg.body.project or "Inbox"
            if title ~= "" then
                submit(title, body, project)
            else
                cancel()
            end
        elseif event == "cancel" then
            cancel()
        end
    end)
end

function of.captureSelection()
	-- Copy current selection without clobbering clipboard permanently
	local pb = hs.pasteboard
	local oldChange = pb.changeCount()
	local oldContents = pb.getContents()

	-- Send Cmd+C to copy selection
	hs.eventtap.keyStroke({ "cmd" }, "c", 0)

	-- Wait briefly for pasteboard to update
	local deadline = hs.timer.absoluteTime() + 1e9 -- ~1s in ns
	while pb.changeCount() == oldChange and hs.timer.absoluteTime() < deadline do
		hs.timer.usleep(30000) -- 30ms
	end

	local copyChanged = (pb.changeCount() ~= oldChange)
	local selection = pb.getContents()
	-- Restore previous clipboard
	if oldContents then
		pb.setContents(oldContents)
	else
		pb.clearContents()
	end

	selection = trim(selection or "")

	local frontApp = hs.application.frontmostApplication()
	local appName = frontApp and frontApp:name() or "Unknown App"
	local appLower = appName:lower()

	-- If in Mail and no text selection or copy didn't change clipboard, fall back to message subject
	local mailInfo = nil
	if appLower == "mail" or appLower:find("mail", 1, true) then
		local ok, result = applescript([[on replaceText(find, replace, subjectText)
		repeat while subjectText contains find
			set AppleScript's text item delimiters to find
			set subjectText to text items of subjectText
			set AppleScript's text item delimiters to replace
			set subjectText to subjectText as string
		end repeat
		set AppleScript's text item delimiters to ""
		return subjectText
	end replaceText

	set delim to ASCII character 31 -- unit separator to avoid collisions
	tell application "Mail"
		try
			set theMsg to missing value
			-- First try the generic selection API
			try
				set sel to selection
				if sel is not {} then set theMsg to item 1 of sel
			end try
			-- If no message yet, try the front message viewer's selected messages
			if theMsg is missing value then
				try
					set selMsgs to selected messages of front message viewer
					if selMsgs is not {} then set theMsg to item 1 of selMsgs
				end try
			end if
			if theMsg is missing value then return ""
			set theID to message id of theMsg
			if theID is missing value then return ""
			set theSubject to subject of theMsg
			set theSender to sender of theMsg
			set theDate to date received of theMsg
			set idText to theID as text
			set idText to my replaceText("\n", "", idText)
			set idText to my replaceText("\r", "", idText)
			-- Ensure angle brackets are present before encoding
			if idText is not "" and (text 1 of idText) is not "<" then set idText to "<" & idText & ">"
			-- Percent-encode only angle brackets for Mail message URLs
			set idEnc to my replaceText("<", "%3C", idText)
			set idEnc to my replaceText(">", "%3E", idEnc)
			set linkText to "message://" & idEnc
			return theSubject & delim & theSender & delim & (theDate as string) & delim & linkText
		on error
			return ""
		end try
	end tell]])
		if ok and type(result) == "string" and result ~= "" then
			local US = string.char(31)
			local subj, sender, dateStr, link = result:match("^(.-)" .. US .. "(.-)" .. US .. "(.-)" .. US .. "(.*)$")
			mailInfo = { subject = subj or "", sender = sender or "", date = dateStr or "", link = link or "" }
			if (selection == "" or not copyChanged) and mailInfo.subject ~= "" then
				selection = mailInfo.subject
			end
		end
	end

	if selection == "" then
		hs.alert.show("No selected text to capture")
		return
	end

	local noteLines = { "From: " .. appName }
	if appLower:find("safari", 1, true) then
		local ok, result = applescript([[tell application "Safari"
			if (count of windows) is 0 then return ""
			set theTab to current tab of front window
			set theURL to URL of theTab
			return theURL
		end tell]])
		if ok and result and result ~= "" then
			table.insert(noteLines, "Link: " .. tostring(result))
		end
	elseif appLower:find("chrome", 1, true) then
		-- Works for Google Chrome / Canary / Chromium by telling the exact front app name
		local script = string.format(
			[[tell application "%s"
			if (count of windows) is 0 then return ""
			set theTab to active tab of front window
			set theURL to URL of theTab
			return theURL
		end tell]],
			appName
		)
		local ok, result = applescript(script)
		if ok and result and result ~= "" then
			table.insert(noteLines, "Link: " .. tostring(result))
		end
	elseif appLower == "mail" or appLower:find("mail", 1, true) then
		if mailInfo and mailInfo.subject ~= "" then
			table.insert(noteLines, "Mail: " .. mailInfo.subject)
			if mailInfo.sender ~= "" then
				table.insert(noteLines, "Sender: " .. mailInfo.sender)
			end
			if mailInfo.date ~= "" then
				table.insert(noteLines, "Date: " .. mailInfo.date)
			end
			if mailInfo.link ~= "" then
				table.insert(noteLines, "Link: " .. mailInfo.link)
			end
		end
	end

	local noteHeader = table.concat(noteLines, "\n")

	-- Prefill the editor with exactly what will be saved as the task note
	local initialNote = noteHeader
	if selection ~= "" then
		initialNote = noteHeader .. "\n\n" .. selection
	end

    -- Fetch project names and show prompt with project selector
    local projects = getOmniFocusProjectNames()
    -- Prompt with title + editable note content; save exactly what user sees
    showCapturePrompt("", initialNote, projects, "Inbox", function(title, edited, project)
        createOmniFocusTask(title, edited or "", project)
    end, function() end)
end

return of
