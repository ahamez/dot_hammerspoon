-- Hammerspoon init: bind URL routes to zk module and watch for changes

local ok, zk_or_err = pcall(require, "zk")
if not ok then
    hs.alert.show("Failed to load zk: " .. tostring(zk_or_err))
    return
end
local zk = zk_or_err

-- URL handlers
hs.urlevent.bind("zk-capture", function(_, params)
    zk.captureText(params)
end)

hs.urlevent.bind("zk-open-current-fleeting", function()
    zk.openFleeting()
end)

hs.urlevent.bind("zk-screenshot", function()
    zk.captureScreenshot()
end)

hs.urlevent.bind("zk-random", function(_, params)
    local searchAll = zk.toBool(params and params["searchAll"])
    zk.openRandom(searchAll)
end)

-- Auto-reload when Lua files or zk_config.json change
local function reloadConfig(files)
    local doReload = false
    for _, file in pairs(files) do
        if file:sub(-4) == ".lua" or file:match("zk_config%.json$") then
            doReload = true
        end
    end
    if doReload then
        hs.reload()
    end
end

MyWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()
zk.notifyInfo("Hammerspoon", "Config reloaded")

-- Window manager module
local wm = require("wm")
wm.start()

-- OmniFocus helpers
local of = require("of")
of.start()
-- URL: trigger OmniFocus capture via hammerspoon://of-capture
hs.urlevent.bind("of-capture", function()
    of.captureSelection()
end)

-- Global center hotkey (no modal)
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "c", function()
    wm.centerCompact()
end)

-- Global: capture selection to OmniFocus inbox
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "t", of.captureSelection)

-- Global: move focused window to left screen
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "left", function()
    wm.moveToLeftScreen()
end)

-- Global: move focused window to right screen
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "right", function()
    wm.moveToRightScreen()
end)

-- optional quick reload
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "r", function()
    hs.reload()
end)
hs.alert.show("Hammerspoon loaded", 0.4)
