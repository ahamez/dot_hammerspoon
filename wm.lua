-- Window manager module encapsulated as table `wm`

local wm = {}

-- ==== Window modal tiler with exact 10px spacing ====

local GAP = 10 -- desired TOTAL spacing between neighbors and edges

-- Centered presets (fractions BEFORE padding is applied)
local PRESETS = {
	f = { x = 0.0, y = 0.0, w = 1.0, h = 1.0 }, -- almost-full (inset by GAP)
	c = { x = 0.25, y = 17 / 80, w = 0.50, h = 23 / 40 }, -- centered compact taller
	n = { x = 1 / 5, y = 31 / 200, w = 3 / 5, h = 69 / 100 }, -- centered like c, but 20% larger
	b = { x = 1 / 5, y = 53 / 600, w = 3 / 5, h = 247 / 300 }, -- centered medium (10% narrower, 5% shorter)
	v = { x = 1 / 5, y = 0.0, w = 3 / 5, h = 1.0 }, -- centered tall full-height (match b width)
}

-- Helpers
local function usableFrame(screen)
	-- use menubar/dock-aware frame so padding is reliable
	return screen:frame()
end

local function setWithUniformPadding(win, unit, gap)
	if not win then
		return
	end
	local f = usableFrame(win:screen())
	local x = f.x + f.w * unit.x + gap
	local y = f.y + f.h * unit.y + gap
	local w = f.w * unit.w - 2 * gap
	local h = f.h * unit.h - 2 * gap
	win:setFrame(hs.geometry.rect(x, y, math.max(1, w), math.max(1, h)), 0)
end

-- Move window between screens preserving relative geometry
local function moveWindowToScreen(win, targetScreen)
	if not win or not targetScreen then
		return
	end
	local fromF = usableFrame(win:screen())
	local toF = usableFrame(targetScreen)
	local wf = win:frame()

	local relX = (wf.x - fromF.x) / fromF.w
	local relY = (wf.y - fromF.y) / fromF.h
	local relW = wf.w / fromF.w
	local relH = wf.h / fromF.h

	local nx = toF.x + relX * toF.w
	local ny = toF.y + relY * toF.h
	local nw = relW * toF.w
	local nh = relH * toF.h

	win:setFrame(hs.geometry.rect(nx, ny, nw, nh), 0)
end

-- exact-10px tiling splits
local function leftHalfRect(f)
	-- total outer edges: GAP, center gap: GAP (total 10)
	local innerW = f.w - (3 * GAP) -- left edge + center + right edge
	local w = innerW / 2
	return hs.geometry.rect(f.x + GAP, f.y + GAP, w, f.h - 2 * GAP)
end

local function rightHalfRect(f)
	local innerW = f.w - (3 * GAP)
	local w = innerW / 2
	local x = f.x + GAP + w + GAP -- left + leftWidth + center gap
	return hs.geometry.rect(x, f.y + GAP, w, f.h - 2 * GAP)
end

local function topHalfRect(f)
	local innerH = f.h - (3 * GAP)
	local h = innerH / 2
	return hs.geometry.rect(f.x + GAP, f.y + GAP, f.w - 2 * GAP, h)
end

local function bottomHalfRect(f)
	local innerH = f.h - (3 * GAP)
	local h = innerH / 2
	local y = f.y + GAP + h + GAP
	return hs.geometry.rect(f.x + GAP, y, f.w - 2 * GAP, h)
end

local function place(win, rect)
	if win and rect then
		win:setFrame(rect, 0)
	end
end

-- Resize width by a pixel delta, keeping center X fixed and clamping to the usable screen frame
local function adjustWidth(win, delta)
	if not win or delta == 0 then
		return
	end
	local screenF = usableFrame(win:screen())
	local f = win:frame()
	local newW = math.max(1, f.w + delta)
	local cx = f.x + f.w / 2
	local newX = cx - newW / 2
	-- clamp horizontally to stay within the screen frame
	if newX < screenF.x then
		newX = screenF.x
	end
	if newX + newW > screenF.x + screenF.w then
		newX = (screenF.x + screenF.w) - newW
	end
	win:setFrame(hs.geometry.rect(newX, f.y, newW, f.h), 0)
end

-- Resize height by a pixel delta, keeping center Y fixed and clamping to the usable screen frame
local function adjustHeight(win, delta)
	if not win or delta == 0 then
		return
	end
	local screenF = usableFrame(win:screen())
	local f = win:frame()
	local newH = math.max(1, f.h + delta)
	local cy = f.y + f.h / 2
	local newY = cy - newH / 2
	-- clamp vertically to stay within the screen frame
	if newY < screenF.y then
		newY = screenF.y
	end
	if newY + newH > screenF.y + screenF.h then
		newY = (screenF.y + screenF.h) - newH
	end
	win:setFrame(hs.geometry.rect(f.x, newY, f.w, newH), 0)
end

local function hideHint()
	if wm._hintAlert then
		hs.alert.closeSpecific(wm._hintAlert)
		wm._hintAlert = nil
	end
end

local function hint()
	hideHint()
	local msg = hs.styledtext.new("f c v b n\nw ⟸⟹  s ⟹⟸\nu ⇑⇓  i ⇓⇑\n← → ↑ ↓\n␛", {
		paragraphStyle = { alignment = "center" },
		font = { name = "Menlo", size = 48 },
		color = { red = 1, green = 1, blue = 1, alpha = 1 },
	})
	wm._hintAlert = hs.alert.show(msg, 9999)
end

-- Public initializer
function wm.start()
	-- expose modal instance on the module for external reference if needed
	local modal
	modal = hs.hotkey.modal.new({ "cmd", "alt", "ctrl" }, "x", function()
		modal:enter()
		hint()
	end)

	function modal:entered()
		hint()
	end
	function modal:exited()
		hideHint()
	end

	modal:bind({}, "escape", function()
		modal:exit()
	end)
	modal:bind({ "cmd", "alt", "ctrl" }, "x", function()
		modal:exit()
	end)

	-- centered presets with uniform outer padding
	for key, unit in pairs(PRESETS) do
		modal:bind({}, key, function()
			setWithUniformPadding(hs.window.focusedWindow(), unit, GAP)
			-- auto-exit after applying centered preset
			modal:exit()
		end)
	end

	-- exact-10px total gaps for 2-way tiling
	modal:bind({}, "left", function()
		local w = hs.window.focusedWindow()
		if not w then
			return
		end
		place(w, leftHalfRect(usableFrame(w:screen())))
	end)

	modal:bind({}, "right", function()
		local w = hs.window.focusedWindow()
		if not w then
			return
		end
		place(w, rightHalfRect(usableFrame(w:screen())))
	end)

	modal:bind({}, "up", function()
		local w = hs.window.focusedWindow()
		if not w then
			return
		end
		place(w, topHalfRect(usableFrame(w:screen())))
	end)

	modal:bind({}, "down", function()
		local w = hs.window.focusedWindow()
		if not w then
			return
		end
		place(w, bottomHalfRect(usableFrame(w:screen())))
	end)

	-- width adjustments: w = +5%, s = -5% (remain in modal)
	modal:bind({}, "w", function()
		local win = hs.window.focusedWindow()
		if not win then
			return
		end
		local step = usableFrame(win:screen()).w * 0.05
		adjustWidth(win, step)
	end)

	modal:bind({}, "s", function()
		local win = hs.window.focusedWindow()
		if not win then
			return
		end
		local step = usableFrame(win:screen()).w * 0.05
		adjustWidth(win, -step)
	end)

	-- height adjustments: u = +5%, i = -5% (remain in modal)
	modal:bind({}, "u", function()
		local win = hs.window.focusedWindow()
		if not win then
			return
		end
		local step = usableFrame(win:screen()).h * 0.05
		adjustHeight(win, step)
	end)

	modal:bind({}, "i", function()
		local win = hs.window.focusedWindow()
		if not win then
			return
		end
		local step = usableFrame(win:screen()).h * 0.05
		adjustHeight(win, -step)
	end)

	wm.modal = modal
end

-- Center the focused window using the compact preset
function wm.centerCompact()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local screenFrame = usableFrame(win:screen())
	local wf = win:frame()
	local newX = screenFrame.x + math.floor((screenFrame.w - wf.w) / 2)
	local newY = screenFrame.y + math.floor((screenFrame.h - wf.h) / 2)
	win:setFrame(hs.geometry.rect(newX, newY, wf.w, wf.h), 0)
end

-- Move focused window to the screen to the left (west)
function wm.moveToLeftScreen()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local s = win:screen()
	if not s then
		return
	end
	local west = s:toWest()
	if west then
		moveWindowToScreen(win, west)
	end
end

-- Move focused window to the screen to the right (east)
function wm.moveToRightScreen()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local s = win:screen()
	if not s then
		return
	end
	local east = s:toEast()
	if east then
		moveWindowToScreen(win, east)
	end
end

return wm
