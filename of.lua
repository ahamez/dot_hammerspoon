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

local function isOmniFocusApp(app)
    if not app then
        return false
    end
    local bundleID = app:bundleID()
    if bundleID and bundleID:match("^com%.omnigroup%.OmniFocus") then
        return true
    end
    local name = app:name()
    return name == "OmniFocus"
end

local toggleModal = hs.hotkey.modal.new()
local appWatcher

local toggleScript = [[tell application "OmniFocus"
	if not (exists document 1) then return
	tell document 1
		if not (exists document window 1) then return
		tell document window 1
			set theContent to content
			if theContent is missing value then return
			set currentFilter to selected task state filter identifier of theContent
			if currentFilter is "available" then
				set selected task state filter identifier of theContent to "incomplete"
			else
				set selected task state filter identifier of theContent to "available"
			end if
		end tell
	end tell
end tell]]

local function createOmniFocusTask(title, note, projectName)
    local titleEsc = encodeAppleScriptString(title)
    local noteEsc = encodeAppleScriptString(note)
    local script
    if projectName and projectName ~= "" and projectName ~= "Inbox" then
        local projEsc = encodeAppleScriptString(projectName)
        script = string.format(
            [[set theTaskName to "%s"
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
end tell]],
            titleEsc,
            noteEsc,
            projEsc
        )
    else
        script = string.format(
            [[set theTaskName to "%s"
set theNote to "%s"
tell application "OmniFocus"
    tell default document
        make new inbox task with properties {name:theTaskName, note:theNote}
    end tell
end tell]],
            titleEsc,
            noteEsc
        )
    end

    local ok, _, err = hs.osascript.applescript(script)
    if not ok then
        hs.alert.show("Failed to add to OmniFocus: " .. tostring(err))
        return
    end

    hs.alert.show("Captured to OmniFocus")
end

-- Minimal inline prompt without chooser hotkey hints
local function htmlEscape(s)
    s = s or ""
    s = s:gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
        :gsub("'", "&#39;")
    return s
end

local function showCapturePrompt(defaultTitle, defaultBody, onSubmit, onCancel)
    local screen = hs.screen.mainScreen():frame()
    local width, height = 720, 520
    local rect = {
        x = screen.x + (screen.w - width) / 2,
        y = screen.y + (screen.h - height) / 4,
        w = width,
        h = height,
    }

    local uc = hs.webview.usercontent.new("ofPrompt")

    -- Load HTML template from file and substitute placeholders
    local templatePath = (hs and hs.configdir or (os.getenv("HOME") .. "/.hammerspoon"))
        .. "/of_prompt.html"
    local fh = io.open(templatePath, "r")
    local html = nil
    if fh then
        html = fh:read("*a")
        fh:close()
    else
        hs.alert.show("Missing of_prompt.html; cannot show capture UI")
        return
    end

    local w = hs.webview
        .new(rect, { developerExtrasEnabled = false }, uc)
        :shadow(true)
        :level(hs.drawing.windowLevels.modalPanel)
        :windowStyle({ "utility" })
        :allowTextEntry(true)
        :html((html:gsub("{{TITLE}}", function()
            return htmlEscape(defaultTitle or "")
        end):gsub("{{BODY}}", function()
            return htmlEscape(defaultBody or "")
        end)))

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
        w:evaluateJavaScript(
            "(function(){var i=document.getElementById('title'); if(i){ i.focus(); i.select(); }})();"
        )
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
    local function submit(title, body)
        close()
        onSubmit(title, body)
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
            if title ~= "" then
                submit(title, body)
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
    local defaultTitle = ""
    if appLower == "mail" or appLower:find("mail", 1, true) then
        defaultTitle = "Follow-up:"
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
            local subj, sender, dateStr, link =
                result:match("^(.-)" .. US .. "(.-)" .. US .. "(.-)" .. US .. "(.*)$")
            mailInfo = {
                subject = subj or "",
                sender = sender or "",
                date = dateStr or "",
                link = link or "",
            }
            if (selection == "" or not copyChanged) and mailInfo.subject ~= "" then
                selection = mailInfo.subject
            end
            local subjectForTitle = trim(mailInfo.subject or "")
            if subjectForTitle ~= "" then
                defaultTitle = "Follow-up: " .. subjectForTitle
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

    -- Prompt with title + editable note content; save exactly what user sees
    showCapturePrompt(defaultTitle, initialNote, function(title, edited)
        createOmniFocusTask(title, edited or "")
    end, function() end)
end

toggleModal:bind({ "alt" }, "a", function()
    of.toggleAvailabilityFilter()
end)

function of.toggleAvailabilityFilter()
    local frontApp = hs.application.frontmostApplication()
    if not isOmniFocusApp(frontApp) then
        return
    end

    local ok, _, err = hs.osascript.applescript(toggleScript)
    if not ok then
        hs.alert.show("OmniFocus toggle failed: " .. tostring(err))
    end
end

function of.start()
    local function syncModal()
        if isOmniFocusApp(hs.application.frontmostApplication()) then
            toggleModal:enter()
        else
            toggleModal:exit()
        end
    end

    syncModal()

    if appWatcher then
        return
    end

    appWatcher = hs.application.watcher.new(function(appName, eventType, appObject)
        local isOmniFocus = appName == "OmniFocus" or isOmniFocusApp(appObject)

        if eventType == hs.application.watcher.activated then
            if isOmniFocus then
                toggleModal:enter()
            else
                toggleModal:exit()
            end
        elseif isOmniFocus and (eventType == hs.application.watcher.deactivated
            or eventType == hs.application.watcher.terminated)
        then
            toggleModal:exit()
        end
    end)

    appWatcher:start()
end

return of
