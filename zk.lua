-- zk.lua — Zettelkasten helpers and actions

local zk = {}

-- Resolve config dir for zk_config.json
local CONFIG_DIR = hs and hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")

-- === Utilities ===

local function pathJoin(a, b)
    if not a or a == "" then
        return b
    end
    if not b or b == "" then
        return a
    end
    if a:sub(-1) == "/" then
        return a .. b
    else
        return a .. "/" .. b
    end
end

local function expandPath(p)
    return (p or ""):gsub("^~", os.getenv("HOME") or "")
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local s = f:read("*a")
    f:close()
    return s
end

local function writeFile(path, contents)
    local f, err = io.open(path, "w")
    if not f then
        zk.alertError("Write error: " .. tostring(err))
        return false
    end
    f:write(contents)
    f:close()
    return true
end

local function appendFile(path, contents)
    local f, err = io.open(path, "a")
    if not f then
        zk.alertError("Append error: " .. tostring(err))
        return false
    end
    f:write(contents)
    f:close()
    return true
end

function zk.alertError(msg)
    hs.alert.show(tostring(msg))
end

function zk.toBool(v)
    if v == nil then
        return false
    end
    if type(v) == "boolean" then
        return v
    end
    if type(v) ~= "string" then
        return false
    end
    local s = v:lower()
    return s == "1" or s == "true" or s == "yes" or s == "on" or s == "y"
end

function zk.mkdirp(dir)
    if not dir or dir == "" then
        return
    end
    local parts = {}
    for part in dir:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    local acc = dir:sub(1, 1) == "/" and "/" or ""
    for _, part in ipairs(parts) do
        acc = acc ~= "" and (acc .. (acc:sub(-1) == "/" and "" or "/") .. part) or part
        hs.fs.mkdir(acc)
    end
end

local function trim(s)
    return (s or ""):gsub("^%s*(.-)%s*$", "%1")
end

-- Seed RNG with high-res time
if hs and hs.timer and hs.timer.absoluteTime then
    math.randomseed(hs.timer.absoluteTime())
else
    math.randomseed(os.time())
end

-- === Config ===

local function loadVaultConfig()
    local cfgPath = pathJoin(CONFIG_DIR, "zk_config.json")
    local s = readFile(cfgPath)
    if not s then
        pcall(function()
            hs.notify
                .new({
                    title = "Zettelkasten Config Missing",
                    informativeText = "Create "
                        .. cfgPath
                        .. " to configure vaultName and vaultPath.",
                    autoWithdraw = true,
                })
                :send()
        end)
        return { vaultName = nil, vaultPath = nil }
    end
    local ok, cfg = pcall(hs.json.decode, s)
    if not ok or type(cfg) ~= "table" then
        zk.alertError("Invalid zk_config.json; fix or remove it")
        return { vaultName = nil, vaultPath = nil }
    end
    local name = (type(cfg.vaultName) == "string" and cfg.vaultName ~= "") and cfg.vaultName or nil
    local path = (type(cfg.vaultPath) == "string" and cfg.vaultPath ~= "")
            and expandPath(cfg.vaultPath)
        or nil
    if not name or not path then
        zk.alertError("zk_config.json missing required fields vaultName/vaultPath")
    end
    local shots = cfg.screenshotsSubfolder
    if type(shots) ~= "string" or shots == "" then
        shots = "Screenshots"
    end
    local filesRel = cfg.filesFolderRel
    if type(filesRel) ~= "string" or filesRel == "" then
        filesRel = nil
    end
    local excludes = nil
    if type(cfg.excludeFoldersRel) == "table" then
        excludes = {}
        local seen = {}
        for _, v in ipairs(cfg.excludeFoldersRel) do
            if type(v) == "string" then
                local s = v:gsub("/*$", "")
                if s ~= "" and not seen[s] then
                    table.insert(excludes, s)
                    seen[s] = true
                end
            end
        end
        if #excludes == 0 then
            excludes = nil
        end
    end
    if not excludes then
        excludes = { "04 - Archives" }
    end
    local inboxRel = (type(cfg.inboxFolderRel) == "string" and cfg.inboxFolderRel ~= "")
            and cfg.inboxFolderRel
        or nil
    local inboxPrefix = (type(cfg.inboxFilePrefix) == "string" and cfg.inboxFilePrefix ~= "")
            and cfg.inboxFilePrefix
        or nil
    return {
        vaultName = name,
        vaultPath = path,
        screenshotsSubfolder = shots,
        filesFolderRel = filesRel,
        excludedFoldersRel = excludes,
        inboxFolderRel = inboxRel,
        inboxFilePrefix = inboxPrefix,
    }
end

zk.config = loadVaultConfig()

local function requireVaultConfig()
    if zk.config.vaultName and zk.config.vaultPath then
        return true
    end
    zk.alertError("zk_config.json missing or incomplete in " .. CONFIG_DIR)
    return false
end

-- === Obsidian helpers ===

local function openObsidianPath(relativePath)
    if not requireVaultConfig() then
        return
    end
    local uri = string.format(
        "obsidian://open?vault=%s&file=%s",
        hs.http.encodeForQuery(zk.config.vaultName),
        hs.http.encodeForQuery(relativePath)
    )
    hs.urlevent.openURL(uri)
end

-- === Fleeting note path ===

function zk.todayFleetingRelative()
    local fname = string.format("%s%s.md", zk.config.inboxFilePrefix, os.date("%Y-%m-%d"))
    return string.format("%s/%s", zk.config.inboxFolderRel, fname)
end

local function ensureFleetingFile(relative)
    if not requireVaultConfig() then
        return false
    end
    local full = pathJoin(zk.config.vaultPath, relative)
    zk.mkdirp(pathJoin(zk.config.vaultPath, zk.config.inboxFolderRel))
    if hs.fs.attributes(full) == nil then
        return writeFile(full, "")
    end
    return true
end

-- === ripgrep integration for note listing / random ===

local function findRG()
    for _, p in ipairs({ "/opt/homebrew/bin/rg", "/usr/local/bin/rg" }) do
        if hs.fs.attributes(p) then
            return p
        end
    end
    return nil
end

local _rgPathCache = nil
local function getRG()
    if _rgPathCache ~= nil then
        return _rgPathCache
    end
    _rgPathCache = findRG()
    return _rgPathCache
end

local function listMarkdownFilesRG(root)
    local rg = getRG()
    if not rg then
        return nil
    end
    local function sq(s)
        return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
    end
    local cmd = table.concat({
        "cd",
        sq(root),
        "&&",
        sq(rg),
        "--hidden",
        "--no-messages",
        "--files",
        "-g",
        "'!**/.obsidian/**'",
        "-g",
        "'**/*.md'",
    }, " ")
    local out = hs.execute(cmd, true) or ""
    local files = {}
    for line in out:gmatch("[^\r\n]+") do
        if line ~= "" then
            table.insert(files, line)
        end
    end
    return files
end

local function listMarkdownFilesFallback(root)
    local files = {}
    local function walk(dir)
        for name in hs.fs.dir(dir) do
            if name ~= "." and name ~= ".." and name ~= ".obsidian" then
                local full = dir .. "/" .. name
                local mode = hs.fs.attributes(full, "mode")
                if mode == "file" and name:sub(-3) == ".md" then
                    local relative = full:sub(#root + 2)
                    table.insert(files, relative)
                elseif mode == "directory" then
                    walk(full)
                end
            end
        end
    end
    walk(root)
    return files
end

local function listAllNotes()
    if not (zk.config.vaultPath and #zk.config.vaultPath > 0) then
        return {}
    end
    return listMarkdownFilesRG(zk.config.vaultPath)
        or listMarkdownFilesFallback(zk.config.vaultPath)
end

local function filterExcluded(files, excludes)
    if not files or #files == 0 then
        return files
    end
    if not excludes or #excludes == 0 then
        return files
    end
    local filtered = {}
    for _, p in ipairs(files) do
        local skip = false
        for _, folder in ipairs(excludes) do
            local prefix = tostring(folder):gsub("/*$", "") .. "/"
            if p:sub(1, #prefix) == prefix then
                skip = true
                break
            end
        end
        if not skip then
            table.insert(filtered, p)
        end
    end
    return filtered
end

local function randomNoteRelative(searchAll)
    local pool = listAllNotes()
    if not pool or #pool == 0 then
        return nil
    end
    if not searchAll then
        local excludes = zk.config.excludedFoldersRel or { "04 - Archives" }
        pool = filterExcluded(pool, excludes)
    end
    if #pool == 0 then
        return nil
    end
    return pool[math.random(#pool)]
end

-- build a fleeting-note entry with captured body as a bullet item
local function makeFleetingEntry(body)
    return string.format("\n- %s\n", body)
end

-- Actions

function zk.openFleeting()
    if not requireVaultConfig() then
        return
    end
    local relative = zk.todayFleetingRelative()
    if not ensureFleetingFile(relative) then
        return
    end
    openObsidianPath(relative)
end

function zk.openRandom(searchAll)
    if not requireVaultConfig() then
        return
    end
    local relative = randomNoteRelative(searchAll)
    if relative then
        openObsidianPath(relative)
    else
        zk.alertError("No notes")
    end
end

function zk.captureText(params)
    if not requireVaultConfig() then
        return
    end
    local text = trim(params and params["text"] or "")
    if text == "" then
        zk.alertError("capture: empty text")
        return
    end
    local relative = zk.todayFleetingRelative()
    if not ensureFleetingFile(relative) then
        return
    end
    local full = pathJoin(zk.config.vaultPath, relative)
    local entry = makeFleetingEntry(text)
    if appendFile(full, entry) then
        openObsidianPath(relative)
    end
end

local function findScreencapture()
    for _, p in ipairs({ "/usr/sbin/screencapture", "/usr/bin/screencapture" }) do
        if hs.fs.attributes(p) then
            return p
        end
    end
    return nil
end

function zk.captureScreenshot()
    if not requireVaultConfig() then
        return
    end
    if not zk.config.filesFolderRel or zk.config.filesFolderRel == "" then
        zk.alertError("filesFolderRel not configured in zk_config.json")
        return
    end
    local bin = findScreencapture()
    if not bin then
        zk.alertError("screencapture not found")
        return
    end
    local stamp = os.date("%Y%m%d-%H%M%S")
    local fileName = string.format("Screenshot-%s.png", stamp)
    local sub = zk.config.screenshotsSubfolder or "Screenshots"
    local relative = pathJoin(pathJoin(zk.config.filesFolderRel, sub), fileName)
    local dirFull = pathJoin(pathJoin(zk.config.vaultPath, zk.config.filesFolderRel), sub)
    local outFull = pathJoin(zk.config.vaultPath, relative)
    zk.mkdirp(dirFull)
    local task = hs.task.new(bin, function(exitCode, _, stdErr)
        if exitCode ~= 0 then
            zk.alertError("Screenshot failed: " .. tostring(stdErr or exitCode))
            return
        end
        if not hs.fs.attributes(outFull) then
            zk.alertError("No file saved")
            return
        end
        local body = string.format("![[%s]]", relative)
        local relF = zk.todayFleetingRelative()
        if not ensureFleetingFile(relF) then
            return
        end
        local fullF = pathJoin(zk.config.vaultPath, relF)
        if appendFile(fullF, makeFleetingEntry(body)) then
            openObsidianPath(relF)
        end
    end, { "-i", "-t", "png", outFull })
    task:start()
end

return zk
