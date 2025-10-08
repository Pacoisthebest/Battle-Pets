-- ReplicatedStorage/Modules/SettingsClient.lua
-- Handles player settings UI + talks to server for persistence.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Net = require(ReplicatedStorage:WaitForChild("Net"):WaitForChild("NetClient"))
local SettingsBus = ReplicatedStorage:WaitForChild("Net"):WaitForChild("v1"):WaitForChild("SettingsC")

local SettingsClient = {}

-- local cache of settings for this client
local state = {
	Music = true, -- default if server has none yet
}

-- UI refs (you call :Init() and pass your PlayerGui/Main so we can find these)
local refs = {
	Main = nil,
	SettingsFrame = nil,
	MusicToggle = nil,         -- TextButton
	MusicTitle = nil,          -- TextLabel under Toggle.Frame.Title
}

-- ===== utilities =====
local function setMusicEnabled(isOn: boolean)
	state.Music = not not isOn

	-- Apply to sound (choose your strategy)
	-- Strategy A: global mute music channel
	local bg = SoundService:FindFirstChild("Music")
	if bg and bg:IsA("Sound") then
		bg.Playing = isOn
	else
		-- Fallback: toggle all Sounds tagged "Music" under SoundService
		for _, s in ipairs(SoundService:GetDescendants()) do
			if s:IsA("Sound") and (s.Name == "Music" or s:GetAttribute("IsMusic") == true) then
				s.Playing = isOn
			end
		end
	end

	-- Update UI
	if refs.MusicTitle then
		refs.MusicTitle.Text = isOn and "On" or "Off"
	end
	if refs.MusicToggle then
		-- Optional: visual toggle feedback (pressed/unpressed)
		refs.MusicToggle.AutoButtonColor = true
	end
end

local function pushToServer(key: string, value: any)
	-- fire-and-forget persist
	Net:Fire("Settings/Update", { key = key, value = value })
end

-- ===== UI binding =====
local function bindMusic()
	if not (refs.MusicToggle and refs.MusicTitle) then return end
	refs.MusicToggle.MouseButton1Click:Connect(function()
		setMusicEnabled(not state.Music)
		pushToServer("Music", state.Music)
	end)
end

-- ===== Public API =====
function SettingsClient.Init(playerGui: PlayerGui)
	-- Resolve UI
	local Main = playerGui:WaitForChild("Main")
	local SettingsFrame = Main:WaitForChild("Frames"):WaitForChild("SettingsFrame")
	local Holder = SettingsFrame:WaitForChild("Holder")
	local Scroller = Holder:WaitForChild("Settings")
	local Music = Scroller:WaitForChild("Music")
	local Toggle = Music:WaitForChild("Toggle")
	local Title = Toggle:WaitForChild("Frame"):WaitForChild("Title")

	refs.Main = Main
	refs.SettingsFrame = SettingsFrame
	refs.MusicToggle = Toggle
	refs.MusicTitle = Title

	-- Bind UI
	bindMusic()

	-- Ask server for current settings (server replies via same remote)
	Net:Fire("Settings/RequestSync", {})

	-- Apply any cached defaults immediately (so UI shows something)
	setMusicEnabled(state.Music)
end

SettingsBus.OnClientEvent:Connect(function(msg)
	-- Expect: { op = "sync", settings = { Music = true, ... } }
	if type(msg) ~= "table" or msg.op ~= "sync" then return end
	local payload = msg.settings or {}
	for k, v in pairs(payload) do
		state[k] = v
	end
	setMusicEnabled(state.Music)
end)

-- (Optional) When server confirms an update, you could listen to RE_SettingsUpdate.OnClientEvent as well,
-- but for simple toggles the optimistic update above is fine.

return SettingsClient
