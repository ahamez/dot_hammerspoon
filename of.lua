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
    if not script or script == "" then
        return false, nil, "missing script"
    end
    local ok, result, err = hs.osascript.applescript(script)
    return ok, result, err
end

local function readAppleScript(filename)
    local baseDir = (hs and hs.configdir) or (os.getenv("HOME") .. "/.hammerspoon")
    local fullPath = baseDir .. "/apple_scripts/" .. filename

    local fh = io.open(fullPath, "r")
    if not fh then
        hs.alert.show("Missing AppleScript: " .. filename)
        return nil
    end

    local contents = fh:read("*a")
    fh:close()
    return contents
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

local toggleScript = readAppleScript("toggle_filter.applescript")
local createWithProjectScript = readAppleScript("create_task_with_project.applescript")
local createInboxScript = readAppleScript("create_inbox_task.applescript")
local mailContextScript = readAppleScript("mail_context.applescript")
local safariUrlScript = readAppleScript("safari_url.applescript")
local browserUrlScript = readAppleScript("browser_url.applescript")

local function createOmniFocusTask(title, note, projectName)
    local titleEsc = encodeAppleScriptString(title)
    local noteEsc = encodeAppleScriptString(note)
    local script
    if projectName and projectName ~= "" and projectName ~= "Inbox" then
        if not createWithProjectScript then
            hs.alert.show("Missing OmniFocus project AppleScript template")
            return
        end
        local projEsc = encodeAppleScriptString(projectName)
        script = string.format(createWithProjectScript, titleEsc, noteEsc, projEsc)
    else
        if not createInboxScript then
            hs.alert.show("Missing OmniFocus inbox AppleScript template")
            return
        end
        script = string.format(createInboxScript, titleEsc, noteEsc)
    end

    local ok, _, err = applescript(script)
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
        local ok, result = applescript(mailContextScript)
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
        local ok, result = applescript(safariUrlScript)
        if ok and result and result ~= "" then
            table.insert(noteLines, "Link: " .. tostring(result))
        end
    elseif appLower:find("chrome", 1, true) then
        -- Works for Google Chrome / Canary / Chromium by telling the exact front app name
        if browserUrlScript then
            local script = string.format(browserUrlScript, appName)
            local ok, result = applescript(script)
            if ok and result and result ~= "" then
                table.insert(noteLines, "Link: " .. tostring(result))
            end
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

    local ok, _, err = applescript(toggleScript)
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
