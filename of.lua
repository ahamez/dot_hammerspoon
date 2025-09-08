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
			set sel to selection
			if sel is not {} then
				set theMsg to item 1 of sel
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
			else
				return ""
			end if
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

	local note = table.concat(noteLines, "\n")

	-- Create OmniFocus inbox task via AppleScript to avoid URL encoding hassles
	local script = string.format(
		[[set theTaskName to "%s"
set theNote to "%s"
tell application "OmniFocus"
	tell default document
		make new inbox task with properties {name:theTaskName, note:theNote}
	end tell
end tell]],
		encodeAppleScriptString(selection),
		encodeAppleScriptString(note)
	)

	local ok, _, err = hs.osascript.applescript(script)
	if not ok then
		hs.alert.show("Failed to add to OmniFocus: " .. tostring(err))
		return
	end

	hs.alert.show("Captured to OmniFocus")
end

return of
