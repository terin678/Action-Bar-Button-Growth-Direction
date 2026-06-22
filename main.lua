-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-- Copyright (c) 2023-2026 Thomas Floeren
--
-- Personal Anniversary/Classic build with a native Settings panel and
-- independent per-bar vertical/horizontal invert toggles.
-- Diverges from upstream (which is config-file only).

local ADDON, NS = ...

local DB_VERSION = 1

--[[===========================================================================
	Bar map / labels
===========================================================================]]--

-- Index order matches Blizzard's action bar numbering in the options UI.
local map = {
	[1] = 'MainActionBar', -- previously MainMenuBar
	[2] = 'MultiBarBottomLeft',
	[3] = 'MultiBarBottomRight',
	[4] = 'MultiBarRight',
	[5] = 'MultiBarLeft',
	[6] = 'MultiBar5',
	[7] = 'MultiBar6',
	[8] = 'MultiBar7',
}
NS.map = map

NS.labels = {
	[1] = 'Action Bar 1 (Main)',
	[2] = 'Action Bar 2 (Bottom Left)',
	[3] = 'Action Bar 3 (Bottom Right)',
	[4] = 'Action Bar 4 (Right)',
	[5] = 'Action Bar 5 (Left)',
	[6] = 'Action Bar 6',
	[7] = 'Action Bar 7',
	[8] = 'Action Bar 8',
}

--[[===========================================================================
	DB init (we have `LoadSavedVariablesFirst: 1`)

	Schema matches the original project: per-bar axis tables, where
		y[idx] -> invert vertical growth   (addButtonsToTop)
		x[idx] -> invert horizontal growth (addButtonsToRight)
	Keeping these names (and db_version) means existing SavedVariables load
	directly, with no migration needed.
===========================================================================]]--

local defaults = {
	db_version = DB_VERSION,
	-- Original project intent: invert vertical growth on Bar 1 only.
	y = { [1]=true, [2]=false,[3]=false,[4]=false,[5]=false,[6]=false,[7]=false,[8]=false },
	x = { [1]=false,[2]=false,[3]=false,[4]=false,[5]=false,[6]=false,[7]=false,[8]=false },
}

if type(ABBGD_db) ~= 'table' or ABBGD_db.db_version ~= DB_VERSION then
	ABBGD_db = CopyTable(defaults)
end

local db = ABBGD_db
db.y = db.y or {} -- defensive; older files always had both
db.x = db.x or {}
NS.db = db

--[[===========================================================================
	Frame resolution
===========================================================================]]--

-- Fallback for the MainMenuBar -> MainActionBar rename on newer clients.
local fallback = {
	['MainMenuBar'] = 'MainActionBar',
	['MainActionBar'] = 'MainMenuBar',
}

local function get_frame(name)
	if _G[name] then return _G[name] end
	if fallback[name] and _G[fallback[name]] then return _G[fallback[name]] end
	return nil
end

--[[===========================================================================
	Apply engine

	`stateV`/`stateH` track whether each bar is currently flipped on that axis
	relative to Blizzard's base layout, so `apply_one` is idempotent for live
	toggling. `reassert` resets the tracked base (called on the base-assured
	triggers: zone load, leaving Edit Mode).

	Auto-correct: `apply_one` records the flag values it leaves behind, and a
	read-only hook on each bar's `UpdateGridLayout` notices when Blizzard later
	overwrites them (e.g. Edit Mode). The correction is *deferred* to the next
	frame via C_Timer, so it runs on a fresh, non-re-entrant call stack (never
	inside the hook) — which is what makes it safe. It self-converges: once the
	flags match what we recorded, the hook schedules nothing further.
===========================================================================]]--

local stateV, stateH = {}, {}
local hooked = {}

-- Forward declarations (these three reference each other).
local apply_one, watch, schedule_fix

-- Deferred, non-re-entrant correction: runs after the detection hook returns.
function schedule_fix(frame, idx)
	if frame.__abbgd_fix then return end
	if not (C_Timer and C_Timer.After) then return end
	frame.__abbgd_fix = true
	C_Timer.After(0, function()
		frame.__abbgd_fix = nil
		if InCombatLockdown() then return end -- protected SetPoint; retried on next relayout
		-- Blizzard rewrote the flags; treat the current values as its fresh base.
		stateV[idx] = false
		stateH[idx] = false
		apply_one(idx)
	end)
end

-- Read-only detection hook: notices when Blizzard overwrites our flags.
function watch(frame, idx)
	if hooked[frame] then return end
	hooked[frame] = true
	hooksecurefunc(frame, 'UpdateGridLayout', function(self)
		if self.__abbgd_top == nil then return end -- not managed yet
		if self.addButtonsToTop ~= self.__abbgd_top
			or self.addButtonsToRight ~= self.__abbgd_right then
			schedule_fix(self, idx)
		end
	end)
end

function apply_one(idx)
	local frame = get_frame(map[idx])
	if not frame or type(frame.UpdateGridLayout) ~= 'function' then return end
	local wantV = db.y[idx] and true or false
	local wantH = db.x[idx] and true or false
	local changed = false
	if stateV[idx] ~= wantV then
		frame.addButtonsToTop = not frame.addButtonsToTop
		stateV[idx] = wantV
		changed = true
	end
	if stateH[idx] ~= wantH then
		frame.addButtonsToRight = not frame.addButtonsToRight
		stateH[idx] = wantH
		changed = true
	end
	-- Record what we left the flags at, and watch for Blizzard overwriting them.
	frame.__abbgd_top = frame.addButtonsToTop
	frame.__abbgd_right = frame.addButtonsToRight
	watch(frame, idx)
	if changed then frame:UpdateGridLayout() end
end

-- Called by the options panel when a checkbox changes.
-- (vert == y axis, horiz == x axis, per the original schema)
local function SetVert(idx, value)
	db.y[idx] = value and true or false
	apply_one(idx)
end
NS.SetVert = SetVert

local function SetHoriz(idx, value)
	db.x[idx] = value and true or false
	apply_one(idx)
end
NS.SetHoriz = SetHoriz

local function GetVert(idx) return db.y[idx] and true or false end
NS.GetVert = GetVert
local function GetHoriz(idx) return db.x[idx] and true or false end
NS.GetHoriz = GetHoriz

local function reassert()
	for i = 1, 8 do
		stateV[i] = false -- Blizzard just (re)applied its base layout
		stateH[i] = false
		apply_one(i)
	end
end
NS.reassert = reassert

--[[===========================================================================
	Events
===========================================================================]]--

local ef = CreateFrame('Frame')
ef:RegisterEvent('PLAYER_ENTERING_WORLD')
ef:SetScript('OnEvent', function() reassert() end)

-- Re-apply after the player leaves Edit Mode (Blizzard reapplies bar layouts).
if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback('EditMode.Exit', function() reassert() end, ef)
end
