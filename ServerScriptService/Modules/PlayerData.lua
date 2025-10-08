-- PlayerData.lua
local Players = game:GetService("Players")

local Settings = require(game.ServerScriptService.Config.Settings)
local DS = require(game.ServerScriptService.Modules.DataStoreWrapper)

local PlayerData = {}

-- In-memory cache: [player] = { data = {...}, loaded = true, dirty = false }
local _profiles = {}

local DEFAULTS = {
	Cash = 0,
	XPMultiplier = 1.0,
	Rebirths = 0,
	Pets = {},
	Equipped = {},   -- ["plotId:slotName"] = "petId"

	-- NEW: persistent bank per slot and last seen time
	SlotBanks = {},  -- ["plotId:slotName"] = { amount = 0, lastTick = 0 }
	LastOnline = 0,  -- os.time() of last save / leave
}



local function makeKeyForUser(userId)
	return string.format("%s:%d", Settings.DataVersion, userId)
end

-- Deep copy defaults to avoid reference sharing
local function cloneDefaults()
	local t = {}
	for k, v in pairs(DEFAULTS) do
		t[k] = v
	end
	return t
end

-- Public: ensure profile in memory (load or create)
function PlayerData.LoadAsync(player)
	local key = makeKeyForUser(player.UserId)
	local raw = DS.Get(Settings.DataStoreName, key, "global")

	if raw == nil then
		raw = cloneDefaults()
	else
		-- Basic validation / fill any missing fields
		for k, v in pairs(DEFAULTS) do
			if raw[k] == nil then
				raw[k] = v
			end
		end
	end

	_profiles[player] = {
		data = raw,
		loaded = true,
		_dirty = false,
	}

	if Settings.Debug then
		local http = game:GetService("HttpService")
		local formattedData = http:JSONEncode(raw)
		print(("[PlayerData] Loaded player '%s'\n  Key: %s\n  Data: %s")
			:format(player.Name, key, formattedData))
	end

	return raw
end

function PlayerData.SaveAsync(player)
	local profile = _profiles[player]
	if not profile or not profile.loaded then return false end

	profile.data.LastOnline = os.time()
	local key = string.format("%s:%d", Settings.DataVersion, player.UserId)
	local ok = DS.Set(Settings.DataStoreName, key, profile.data, "global")
	if ok then profile._dirty = false end
	return ok
end


-- Public: release from memory (call on PlayerRemoving)
function PlayerData.Release(player)
	_profiles[player] = nil
end

-- Public: get a read-only copy of data
function PlayerData.Get(player)
	local p = _profiles[player]
	return p and p.data or nil
end

-- Mutators (mark dirty)
function PlayerData.SetCash(player, amount)
	local p = _profiles[player]; if not p then return end
	p.data.Cash = math.floor(tonumber(amount) or 0)
	p._dirty = true
end

function PlayerData.AddCash(player, delta)
	local p = _profiles[player]; if not p then return end
	p.data.Cash = math.max(0, math.floor((p.data.Cash or 0) + (delta or 0)))
	p._dirty = true
end

function PlayerData.SetXPMultiplier(player, value)
	local p = _profiles[player]; if not p then return end
	p.data.XPMultiplier = tonumber(value) or DEFAULTS.XPMultiplier
	p._dirty = true
end

function PlayerData.SetRebirths(player, value)
	local p = _profiles[player]; if not p then return end
	p.data.Rebirths = tonumber(value) or DEFAULTS.Rebirths
	p._dirty = true
end

function PlayerData.SetPlotUpgrades(player, value)
	local p = _profiles[player]; if not p then return end
	p.data.PlotUpgrades = tonumber(value) or DEFAULTS.PlotUpgrades
	p._dirty = true
end

function PlayerData.GetSlotBank(player, sk)
	local p = _profiles[player]; if not p then return nil end
	p.data.SlotBanks = p.data.SlotBanks or {}
	p.data.SlotBanks[sk] = p.data.SlotBanks[sk] or { amount = 0, lastTick = 0 }
	return p.data.SlotBanks[sk]
end

function PlayerData.SetSlotBank(player, sk, amount, lastTick)
	local p = _profiles[player]; if not p then return end
	p.data.SlotBanks = p.data.SlotBanks or {}
	p.data.SlotBanks[sk] = p.data.SlotBanks[sk] or { amount = 0, lastTick = 0 }
	p.data.SlotBanks[sk].amount = amount
	p.data.SlotBanks[sk].lastTick = lastTick or p.data.SlotBanks[sk].lastTick
	p._dirty = true
end


-- Autosave loop (start once)
task.spawn(function()
	while true do
		task.wait(Settings.AutosaveInterval)
		for player, profile in pairs(_profiles) do
			if profile.loaded and profile._dirty then
				PlayerData.SaveAsync(player)
			end
		end
	end
end)

-- Save everyone on shutdown
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerData.SaveAsync(player)
	end
end)

return PlayerData
