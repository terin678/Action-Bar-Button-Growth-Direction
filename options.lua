-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-- Native Settings panel (Options > AddOns) using the standard Settings API.
-- Two checkboxes per bar (vertical / horizontal); no custom-drawn UI.

local ADDON, NS = ...

local function build()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

	local category, layout = Settings.RegisterVerticalLayoutCategory('Action Bar Growth Direction')

	local hasHeader = layout and CreateSettingsListSectionHeaderInitializer

	for i = 1, 8 do
		if hasHeader then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(NS.labels[i]))
		end

		local vSetting = Settings.RegisterProxySetting(
			category,
			'ABBGD_VERT_' .. i,
			Settings.VarType.Boolean,
			'Invert vertical (top/bottom)',
			Settings.Default.False,
			function() return NS.GetVert(i) end,
			function(value) NS.SetVert(i, value) end
		)
		Settings.CreateCheckbox(
			category, vSetting,
			'Reverse the vertical fill direction of ' .. NS.labels[i] .. ' (top vs. bottom).'
		)

		local hSetting = Settings.RegisterProxySetting(
			category,
			'ABBGD_HORIZ_' .. i,
			Settings.VarType.Boolean,
			'Invert horizontal (left/right)',
			Settings.Default.False,
			function() return NS.GetHoriz(i) end,
			function(value) NS.SetHoriz(i, value) end
		)
		Settings.CreateCheckbox(
			category, hSetting,
			'Reverse the horizontal fill direction of ' .. NS.labels[i] .. ' (left vs. right).'
		)
	end

	Settings.RegisterAddOnCategory(category)
	NS.category = category
end

local ef = CreateFrame('Frame')
ef:RegisterEvent('PLAYER_LOGIN')
ef:SetScript('OnEvent', function()
	build()
end)
