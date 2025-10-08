-- ServerScriptService/Modules/PetService.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local sounds = game:GetService("SoundService")

local PlayerData = require(game.ServerScriptService.Modules.PlayerData)
local Catalog = require(ReplicatedStorage.Modules.PetCatalog)
local Settings = require(game.ServerScriptService.Config.Settings)

-- Asset folder for display models
local Assets = ReplicatedStorage:WaitForChild("Assets")
local PetAssets = Assets:WaitForChild("Pets")

-- === NEW: Remote Manager wiring (single server->client bus) ===
local RemoteManager = require(game.ReplicatedStorage.Net.RemoteManager)
local Net = _G.Net or RemoteManager.new()           -- reuse if you created elsewhere
local ClientBus = Net:GetEvent("PetsC")             -- ReplicatedStorage/Net/v1/PetsC (auto-created)
local NotifyBus = Net:GetEvent("NotificationsC")             -- ReplicatedStorage/Net/v1/PetsC (auto-created)

-- Accumulators per slotName: sk -> { amount:number, lastTick:unix, petId:string|nil, owner:Player }

local PetService = {}
local SlotBanks = {}

local function isValidBank(b)
	return b and b.owner and typeof(b.owner) == "Instance" and b.slotName ~= nil
end

-- ===================== Helpers =====================
local function notify(player: Player, text: string, kind: string?, sound: any?)
	-- Always send a table so the client can handle it consistently
	NotifyBus:FireClient(player, {
		text  = text,
		color = kind or "info",  -- your Notification module can map this
		sound = sound,
	})
end

local function slotKey(player: Player, slotModel)
	-- runtime key is unique per player regardless of which plot they’re on
	return tostring(player.UserId) .. ":" .. tostring(slotModel.Name)
end


local function isOwnerOfPlot(player, plotFolder)
	return (plotFolder:GetAttribute("Owner") == player.UserId)
end

local function findPlayerPlotFolder(player)
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	for _, plotFolder in ipairs(plotsFolder:GetChildren()) do
		if plotFolder:IsA("Folder") and plotFolder:GetAttribute("Owner") == player.UserId then
			return plotFolder
		end
	end
	return nil
end

-- Find this player's current slot model by slotName
local function getSlotModelFor(player, slotName)
	local plotFolder = findPlayerPlotFolder(player)
	if not plotFolder then return nil end
	local slots = plotFolder:FindFirstChild("Slots")
	if not slots then return nil end
	return slots:FindFirstChild(slotName)
end

local function setBillboard(slotModel, def)
	local holder = slotModel:FindFirstChild("PetStatsHolder")
	if not (holder and holder:IsA("BasePart")) then
		warn("[PetService] Missing PetStatsHolder on slot:", slotModel:GetFullName())
		return
	end

	local bb = holder:FindFirstChild("PetBillboard")
	if not (bb and bb:IsA("BillboardGui")) then
		warn("[PetService] Missing PetBillboard under:", holder:GetFullName())
		return
	end

	if def then
		bb.Enabled = true

		local function setText(name, value)
			local tl = bb:FindFirstChild(name)
			if tl and tl:IsA("TextLabel") then
				tl.Text = value
			end
		end

		setText("Income", tostring(def.Income) .. "/s")
		setText("Name", def.Name)
		setText("Rarity", def.Rarity)
		setText("Strength", tostring(def.Strength))
	else
		bb.Enabled = false
	end
end

local function clearPetModel(slotModel)
	local holder = slotModel:FindFirstChild("PetStatsHolder")
	if not (holder and holder:IsA("BasePart")) then return end

	for _, child in ipairs(holder:GetChildren()) do
		if not (child:IsA("BillboardGui") and child.Name == "PetBillboard" or child:IsA("ProximityPrompt")) then
			child:Destroy()
		end
	end
end

-- Clone & place the pet model inside PetStatsHolder
local function setPetModel(slotModel, petId)
	local holder = slotModel:FindFirstChild("PetStatsHolder")
	if not (holder and holder:IsA("BasePart")) then
		warn("[PetService] Missing PetStatsHolder for", slotModel:GetFullName())
		return
	end

	clearPetModel(slotModel)

	local src = PetAssets:FindFirstChild(petId)
	if not src then
		warn("[PetService] Pet asset not found for petId:", petId)
		return
	end

	local clone = src:Clone()
	clone.Name = "PetDisplay"
	clone.Parent = holder

	-- Make it a non-physics display + align to holder
	if clone:IsA("Model") then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		local yOff = holder:GetAttribute("PetOffsetY") or 0
		clone:PivotTo(holder.CFrame * CFrame.new(0, yOff, 0))
	elseif clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.CFrame = holder.CFrame
	end
end

local function setButtonAmount(slotModel, amount)
	local button = slotModel:FindFirstChild("Button")
	if not button then return end
	local claim = button:FindFirstChild("Claim")
	if not (claim and claim:IsA("BasePart")) then return end
	local sg = claim:FindFirstChildOfClass("SurfaceGui")
	if not sg then return end
	local tl = sg:FindFirstChild("TextLabel")
	if tl and tl:IsA("TextLabel") then
		tl.Text = tostring(amount)
	end
end

local function ensureSlotPrompt(slotModel)
	local holder = slotModel:FindFirstChild("PetStatsHolder")
	local parentForPrompt = holder and holder:IsA("BasePart") and holder or slotModel
	local prompt = parentForPrompt:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Manage Slot"
		prompt.ObjectText = "Pets"
		prompt.MaxActivationDistance = 12
		prompt.HoldDuration = 0
		prompt.Parent = parentForPrompt
	end
	return prompt
end

local function waitForSlotVisuals(slotModel, timeout)
	timeout = timeout or 5
	local t0 = os.clock()
	local holder
	repeat
		holder = slotModel:FindFirstChild("PetStatsHolder")
		if holder then break end
		task.wait(0.1)
	until os.clock() - t0 > timeout
	if not holder then
		warn("[PetService] Timed out waiting for PetStatsHolder:", slotModel:GetFullName()); return false
	end
	local bb
	repeat
		bb = holder:FindFirstChild("PetBillboard")
		if bb then break end
		task.wait(0.1)
	until os.clock() - t0 > timeout
	if not bb then
		warn("[PetService] Timed out waiting for PetBillboard:", holder:GetFullName()); return false
	end
	return true
end

local function slotNameFromKey(sk: string): string
	local colon = string.find(sk, ":", 1, true)
	if colon then
		return string.sub(sk, colon + 1)
	end
	return sk
end

local function persistSlotBank(player, sk, amount, lastTick, doImmediateSave)
	local slotName = slotNameFromKey(sk)

	if typeof(PlayerData.SetSlotBank) == "function" then
		PlayerData.SetSlotBank(player, slotName, amount, lastTick)
		if doImmediateSave then PlayerData.SaveAsync(player) end
	else
		local data = PlayerData.Get(player)
		if data then
			data.SlotBanks = data.SlotBanks or {}
			data.SlotBanks[slotName] = data.SlotBanks[slotName] or { amount = 0, lastTick = 0 }
			data.SlotBanks[slotName].amount   = amount
			data.SlotBanks[slotName].lastTick = lastTick
			if doImmediateSave then PlayerData.SaveAsync(player) end
		end
	end
end

-- ===================== Client sync =====================
local function refreshClient(player)
	local data = PlayerData.Get(player)
	if not data then return end

	-- owned vs free
	local owned = data.Pets or {}
	local equipped = data.Equipped or {}
	local usedCounts = {}
	for _, petId in pairs(equipped) do
		if petId then
			usedCounts[petId] = (usedCounts[petId] or 0) + 1
		end
	end
	local free = {}
	for petId, qty in pairs(owned) do
		free[petId] = math.max(0, (qty or 0) - (usedCounts[petId] or 0))
	end

	local earnings = {}
	local plotFolder = findPlayerPlotFolder(player)
	if plotFolder and plotFolder:FindFirstChild("Slots") then
		for _, slotModel in ipairs(plotFolder.Slots:GetChildren()) do
			local sk_run = slotKey(player, slotModel)
			earnings[slotModel.Name] = (SlotBanks[sk_run] and SlotBanks[sk_run].amount) or 0
		end
	end

	ClientBus:FireClient(player, {
		op       = "sync",
		owned    = owned,
		free     = free,
		equipped = equipped,      -- keyed by slotName
		earnings = earnings,      -- keyed by slotName
		catalog  = Catalog.All(),
	})
end

-- ===================== Equip / Unequip / Claim =====================
local function equipPet(player, plotFolder, slotModel, petId)
	if not isOwnerOfPlot(player, plotFolder) then return false, "Not your plot" end
	local def = Catalog.Get(petId)
	if not def then return false, "Unknown pet" end

	local data = PlayerData.Get(player); if not data then return false, "No data" end
	data.Pets = data.Pets or {}
	data.Equipped = data.Equipped or {}

	-- Check available copies (owned - equipped)
	local owned = data.Pets[petId] or 0
	local used = 0
	for _, p in pairs(data.Equipped) do if p == petId then used += 1 end end
	if owned - used <= 0 then return false, "No free copy in inventory" end

	local sk = slotKey(player, slotModel)         -- keep for runtime SlotBanks
	data.Equipped[slotModel.Name] = petId         -- <-- slot-only key for persistence
	PlayerData.SaveAsync(player)

	SlotBanks[sk] = SlotBanks[sk] or { amount = 0, lastTick = os.clock(), owner = player }
	SlotBanks[sk].petId   = petId
	SlotBanks[sk].owner   = player
	SlotBanks[sk].slotName= slotModel.Name
	SlotBanks[sk].lastTick= os.clock()

	local now = os.time()
	persistSlotBank(player, sk, SlotBanks[sk].amount or 0, now, false)
	
	setBillboard(slotModel, def)
	setPetModel(slotModel, petId)
	refreshClient(player)
	return true
end

local function unequipPet(player, plotFolder, slotModel)
	if not isOwnerOfPlot(player, plotFolder) then return false, "Not your plot" end
	local data = PlayerData.Get(player); if not data then return false, "No data" end
	local sk = slotKey(player, slotModel)
	if not data.Equipped[slotModel.Name] then return false, "Slot empty" end

	data.Equipped[slotModel.Name] = nil          -- <-- slot-only key
	PlayerData.SaveAsync(player)

	if SlotBanks[sk] then
		SlotBanks[sk].petId = nil
		persistSlotBank(player, sk, SlotBanks[sk].amount or 0, os.time(), false)
	end
	
	setBillboard(slotModel, nil)
	clearPetModel(slotModel)
	refreshClient(player)
	return true
end

local function claimSlot(player, plotFolder, slotModel)
	if not isOwnerOfPlot(player, plotFolder) then
		return false, "Not your plot"
	end
	local sk = slotKey(player, slotModel)
	local bank = SlotBanks[sk]
	local amount = (bank and bank.amount) or 0
	if amount <= 0 then return false, "Nothing to claim" end

	PlayerData.AddCash(player, amount)
	if player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash") then
		player.leaderstats.Cash.Value = PlayerData.Get(player).Cash
	end

	if bank then bank.amount = 0 end
	persistSlotBank(player, sk, 0, os.time(), true)

	setButtonAmount(slotModel, 0)

	-- === NEW: claim result via bus
	ClientBus:FireClient(player, {
		op      = "claimResult",
		ok      = true,
		amount  = amount,
		message = "Claimed +" .. amount,
	})

	refreshClient(player)
	return true, amount
end

-- ===================== Claim via touch =====================
local function getClaimPart(slotModel)
	local button = slotModel:FindFirstChild("Button")
	if not button then return nil end
	local claim = button:FindFirstChild("Claim")
	if claim and claim:IsA("BasePart") then
		return claim
	end
	return nil
end

local PressState = {} 

local function ensurePressState(part: BasePart)
	local st = PressState[part]
	if not st then
		st = {
			baseCF   = part.CFrame,
			pressedCF= part.CFrame * CFrame.new(-0.25, 0, 0),
			isPressed= false,
			counts   = {},
			total    = 0,
			pressTween = nil,
			releaseTween = nil,
		}
		PressState[part] = st
	end
	return st
end

local function setPressed(part: BasePart, st, wantPressed: boolean)
	if wantPressed == st.isPressed then return end
	st.isPressed = wantPressed

	-- cancel opposite tween if running
	if wantPressed and st.releaseTween then st.releaseTween:Cancel() end
	if not wantPressed and st.pressTween then st.pressTween:Cancel() end

	local ti = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if wantPressed then
		st.pressTween = TweenService:Create(part, ti, { CFrame = st.pressedCF })
		st.pressTween:Play()
	else
		st.releaseTween = TweenService:Create(part, ti, { CFrame = st.baseCF })
		st.releaseTween:Play()
	end
end

local TouchCooldown = {} -- sk -> lastTouchTime
local function connectClaimTouch(slotModel, plotFolder)
	local claimPart = getClaimPart(slotModel)
	if not claimPart then
		warn("[PetService] Missing Button/Claim part:", slotModel:GetFullName()); return
	end
	claimPart.CanTouch = true

	local st = ensurePressState(claimPart)

	-- helper: track touches for the plot owner only
	local function isOwnerCharacter(hit: BasePart)
		local character = hit and hit.Parent
		if not character then return nil end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return nil end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return nil end
		if not isOwnerOfPlot(player, plotFolder) then return nil end
		return character, player
	end

	claimPart.Touched:Connect(function(hit)
		local ownerId = plotFolder:GetAttribute("Owner")
		local owner = ownerId and game.Players:GetPlayerByUserId(ownerId)
		if not owner then return end

		local character = hit and hit.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		
		local player = game.Players:GetPlayerFromCharacter(character); if not player then return end
		if player ~= owner then 
			print("NO")
			notify(player, "Not your plot!", "error", sounds.Error)
			return 
		end

		-- count this character's touching parts
		st.counts[character] = (st.counts[character] or 0) + 1
		st.total += 1
		if st.total > 0 then
			setPressed(claimPart, st, true)
		end

		local sk = slotKey(owner, slotModel)

		local nowc = os.clock()
		if (TouchCooldown[sk] or 0) + 0.5 > nowc then return end
		TouchCooldown[sk] = nowc

		local ok, amtOrMsg = claimSlot(player, plotFolder, slotModel)
		if not ok then
			ClientBus:FireClient(player, {
				op      = "claimResult",
				ok      = false,
				amount  = 0,
				message = tostring(amtOrMsg or "Nothing to claim"),
			})
		end
	end)

	-- pop back up when owner is no longer touching
	claimPart.TouchEnded:Connect(function(hit)
		local character, _ = isOwnerCharacter(hit)
		if not character then return end

		local cur = (st.counts[character] or 0)
		if cur > 1 then
			st.counts[character] = cur - 1
		else
			st.counts[character] = nil
		end

		-- recompute total safely (guards against physics spam)
		local total = 0
		for _, n in pairs(st.counts) do total += n end
		st.total = total

		if st.total <= 0 then
			setPressed(claimPart, st, false)
		end
	end)
end


-- ===================== Live accumulation loop =====================
local SaveThrottle = {} -- sk -> lastSave os.clock()
task.spawn(function()
	while true do
		task.wait(1)
		for sk, bank in pairs(SlotBanks) do
			if isValidBank(bank) and bank.owner.Parent == Players and bank.petId then
				local def = Catalog.Get(bank.petId)
				if def then
					bank.amount = (bank.amount or 0) + (def.Income or 0)
					-- update button text in-world by locating the owner's plot & slot
					local plotFolder = findPlayerPlotFolder(bank.owner)
					if plotFolder and plotFolder:FindFirstChild("Slots") and bank.slotName then
						local slotModel = plotFolder.Slots:FindFirstChild(bank.slotName)
						if slotModel then
							setButtonAmount(slotModel, bank.amount)
						end
					end
				end
			end
		end
	end
end)

-- ===================== Wiring + Rehydrate (slot-only) =====================
local function wirePlot(plotFolder)
	local slotsFolder = plotFolder:FindFirstChild("Slots")
	if not slotsFolder then return end
	for _, slotModel in ipairs(slotsFolder:GetChildren()) do
		if slotModel:IsA("Model") then
			local managePrompt = ensureSlotPrompt(slotModel)
			managePrompt.Triggered:Connect(function(player)
				if isOwnerOfPlot(player, plotFolder) then
					-- === NEW: open inventory via bus
					ClientBus:FireClient(player, {
						op = "open",
						plotId = plotFolder.Name,
						slotName = slotModel.Name,
					})
					refreshClient(player)
				end
			end)
			connectClaimTouch(slotModel, plotFolder)
		end
	end
end

-- Migrate keys like "3:Slot1" -> "Slot1"
local function migrateKeysToSlotOnly(data)
	if not data then return end
	data.Equipped = data.Equipped or {}
	data.SlotBanks = data.SlotBanks or {}

	local changed = false
	-- Equipped
	for k, v in pairs(table.clone(data.Equipped)) do
		if typeof(k) == "string" and string.find(k, ":") then
			local _, slotName = string.match(k, "^(.-):(.-)$")
			slotName = slotName or k
			if data.Equipped[slotName] == nil then
				data.Equipped[slotName] = v
			end
			data.Equipped[k] = nil
			changed = true
		end
	end
	-- SlotBanks
	for k, v in pairs(table.clone(data.SlotBanks)) do
		if typeof(k) == "string" and string.find(k, ":") then
			local _, slotName = string.match(k, "^(.-):(.-)$")
			slotName = slotName or k
			if data.SlotBanks[slotName] == nil then
				data.SlotBanks[slotName] = v
			end
			data.SlotBanks[k] = nil
			changed = true
		end
	end
	return changed
end

function PetService.ReleasePlayer(player: Player)
	-- 1) Clear runtime banks for this user
	local prefix = tostring(player.UserId) .. ":"
	for sk in pairs(SlotBanks) do
		if string.sub(sk, 1, #prefix) == prefix then
			SlotBanks[sk] = nil
		end
	end

	-- 2) Clear visuals on their plot (if still present)
	local plotFolder = findPlayerPlotFolder(player)
	if plotFolder then
		local slots = plotFolder:FindFirstChild("Slots")
		if slots then
			for _, slotModel in ipairs(slots:GetChildren()) do
				if slotModel:IsA("Model") then
					-- wipe billboard + 3D pet + claim text
					setBillboard(slotModel, nil)
					clearPetModel(slotModel)
					setButtonAmount(slotModel, 0)
				end
			end
		end
	end
end

function PetService.ResetPlot(plotFolder: Instance)
	if not plotFolder then return end
	local slots = plotFolder:FindFirstChild("Slots")
	if not slots then return end

	for _, slotModel in ipairs(slots:GetChildren()) do
		if slotModel:IsA("Model") then
			setBillboard(slotModel, nil)
			clearPetModel(slotModel) 
			setButtonAmount(slotModel, 0) 
		end
	end

	local slotNameSet = {}
	for _, slotModel in ipairs(slots:GetChildren()) do
		if slotModel:IsA("Model") then
			slotNameSet[slotModel.Name] = true
		end
	end

	for sk, bank in pairs(SlotBanks) do
		if bank and slotNameSet[bank.slotName] then
			SlotBanks[sk] = nil
		end
	end
end

local function onPlayerAdded(player)
	task.defer(function()
		local plots = workspace:WaitForChild("Plots", 10)
		if not plots then return end

		-- wait up to ~5s for ownership to be set
		local deadline = os.clock() + 5
		local plotFolder
		repeat
			for _, pf in ipairs(plots:GetChildren()) do
				if pf:IsA("Folder") and pf:GetAttribute("Owner") == player.UserId then
					plotFolder = pf
					break
				end
			end
			if not plotFolder then task.wait(0.2) end
		until plotFolder or os.clock() > deadline

		-- Load & migrate data first
		local data = PlayerData.Get(player) or PlayerData.LoadAsync(player)
		if not data then return end
		if migrateKeysToSlotOnly(data) then
			PlayerData.SaveAsync(player) -- persist migration
		end

		-- Even if no plot yet, push inventory sync so left-side button works
		refreshClient(player)

		if not plotFolder then
			warn("[PetService] No owned plot found for", player.Name)
			return
		end

		wirePlot(plotFolder)

		-- Rehydrate slots + offline income (slot-name keys)
		data = PlayerData.Get(player)
		data.Equipped = data.Equipped or {}
		data.SlotBanks = data.SlotBanks or {}

		local now = os.time()
		local slotsFolder = plotFolder:FindFirstChild("Slots") or plotFolder:WaitForChild("Slots", 5)
		if not slotsFolder then
			warn("[PetService] No Slots folder under", plotFolder:GetFullName())
			refreshClient(player)
			return
		end

		-- if streaming delays, wait a bit for children
		if #slotsFolder:GetChildren() == 0 then
			local tEnd = os.clock() + 5
			repeat task.wait(0.2) until #slotsFolder:GetChildren() > 0 or os.clock() > tEnd
		end

		for _, slotModel in ipairs(slotsFolder:GetChildren()) do
			if not slotModel:IsA("Model") then continue end
			local sk       = slotKey(player, slotModel)         -- runtime key
			local slotName = slotModel.Name
			
			local petId = data.Equipped[slotName]

			local persisted = data.SlotBanks[slotName] or { amount = 0, lastTick = data.LastOnline or 0 }
			local storedAmount = tonumber(persisted.amount) or 0
			local lastTick = tonumber(persisted.lastTick) or (data.LastOnline or now)

			local amount = storedAmount
			if petId then
				local def = Catalog.Get(petId)
				if def then
					local delta = math.max(0, now - (lastTick or now))
					-- optional cap: delta = math.min(delta, 8*3600)
					amount += (def.Income or 0) * delta
				else
					warn("[PetService] Equipped pet missing from Catalog:", petId, "slot", sk)
				end
			end

			SlotBanks[sk] = SlotBanks[sk] or { amount = 0, lastTick = os.clock(), owner = player }
			SlotBanks[sk].owner    = player
			SlotBanks[sk].slotName = slotName
			SlotBanks[sk].petId    = petId

			waitForSlotVisuals(slotModel, 5)
			if petId and Catalog.Get(petId) then
				setBillboard(slotModel, Catalog.Get(petId))
				setPetModel(slotModel, petId)
			else
				setBillboard(slotModel, nil)
				clearPetModel(slotModel)
			end
			setButtonAmount(slotModel, amount)

			persistSlotBank(player, sk, amount, now, false)
		end

		refreshClient(player)
	end)
end

local function onPlayerRemoving(player)
	local data = PlayerData.Get(player)
	if data then
		data.LastOnline = os.time()
		PlayerData.SaveAsync(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

----------------------------------------------------------------
-- === NEW: Net routes (replace old OnServerEvent handlers) ===
----------------------------------------------------------------

-- helper that checks slot ownership and calls a function
local function mustOwnSlot(player, slotName)
	local plotFolder = findPlayerPlotFolder(player); if not plotFolder then return false, "no plot" end
	local slots = plotFolder:FindFirstChild("Slots"); if not slots then return false, "no slots" end
	local slotModel = slots:FindFirstChild(tostring(slotName)); if not slotModel then return false, "invalid slot" end
	if not isOwnerOfPlot(player, plotFolder) then return false, "not owner" end
	return true, plotFolder, slotModel
end

-- 1) Equip
Net:RegisterEvent("Pets/Equip", function(player, payload)
	-- payload = { slotName="Slot1", petId="Cat" }
	if type(payload) ~= "table" then return end
	local slotName = tostring(payload.slotName)
	local petId    = tostring(payload.petId)
	local ok, plotFolder, slotModel = mustOwnSlot(player, slotName)
	if not ok then return end
	equipPet(player, plotFolder, slotModel, petId)
end, {
	cooldown = 0.20, rate = 6, burst = 8, maxPayloadBytes = 200,
	schema = { kind="table", keys = {
		slotName = { kind="string", min=3, max=16 },
		petId    = { kind="string", min=1, max=64 },
	}}
})

-- 2) Unequip
Net:RegisterEvent("Pets/Unequip", function(player, payload)
	-- payload = { slotName="Slot1" }
	if type(payload) ~= "table" then return end
	local slotName = tostring(payload.slotName)
	local ok, plotFolder, slotModel = mustOwnSlot(player, slotName)
	if not ok then return end
	unequipPet(player, plotFolder, slotModel)
end, {
	cooldown = 0.20, rate = 6, burst = 8, maxPayloadBytes = 120,
	schema = { kind="table", keys = {
		slotName = { kind="string", min=3, max=16 },
	}}
})

-- 3) AutoEquip (first empty slot)
Net:RegisterEvent("Pets/AutoEquip", function(player, payload)
	-- payload = { petId="Cat" }
	if type(payload) ~= "table" then return end
	local petId = tostring(payload.petId)

	local plotFolder = findPlayerPlotFolder(player); if not plotFolder then return end
	local slots = plotFolder:FindFirstChild("Slots"); if not slots then return end

	local data = PlayerData.Get(player); if not data then return end
	data.Equipped = data.Equipped or {}

	local targetSlotModel
	for i = 1, 12 do
		local sn = "Slot"..i
		if not data.Equipped[sn] then
			local sm = slots:FindFirstChild(sn)
			if sm and sm:IsA("Model") then targetSlotModel = sm break end
		end
	end
	if not targetSlotModel then
		warn(("[PetService] %s tried auto-equip but no free slots"):format(player.Name))
		return
	end

	equipPet(player, plotFolder, targetSlotModel, petId)
end, {
	cooldown = 0.25, rate = 4, burst = 6, maxPayloadBytes = 120,
	schema = { kind="table", keys = {
		petId = { kind="string", min=1, max=64 },
	}}
})

-- 4) Manual RequestSync
Net:RegisterEvent("Pets/RequestSync", function(player, _)
	refreshClient(player)
end, {
	cooldown = 1.0, rate = 2, burst = 2, maxPayloadBytes = 32,
})
----------------------------------------------------------------

return PetService
