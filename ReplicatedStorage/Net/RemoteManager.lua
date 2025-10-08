local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local IS_SERVER = RunService:IsServer()

local FOLDER_NAME = "Net"
local VERSION     = "v1"

local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then f = Instance.new("Folder"); f.Name = name; f.Parent = parent end
	return f
end

local function jsonSize(v)
	local ok, s = pcall(HttpService.JSONEncode, HttpService, v)
	return ok and #s or 0
end

local function now() return os.clock() end

local Validators = {}

function Validators.string(val, spec)
	if typeof(val) ~= "string" then return false, "not string" end
	if spec.min and #val < spec.min then return false, "too short" end
	if spec.max and #val > spec.max then return false, "too long" end
	if spec.enum then
		local ok=false
		for _,e in ipairs(spec.enum) do if e==val then ok=true break end end
		if not ok then return false, "not in enum" end
	end
	return true
end

function Validators.number(val, spec)
	if typeof(val) ~= "number" then return false, "not number" end
	if spec.int and math.floor(val) ~= val then return false, "not int" end
	if spec.min and val < spec.min then return false, "too small" end
	if spec.max and val > spec.max then return false, "too large" end
	return true
end

function Validators.boolean(val)
	return typeof(val) == "boolean", "not boolean"
end

function Validators.table(val, spec)
	if typeof(val) ~= "table" then return false, "not table" end
	if spec.keys then
		for k, rule in pairs(spec.keys) do
			local ok, err = Validators.any(val[k], rule)
			if not ok then return false, ("key '%s' invalid: %s"):format(k, err or "?") end
		end
	end
	return true
end

function Validators.any(val, spec)
	if spec == nil then return true end
	local kind = spec.kind
	if Validators[kind] then
		return Validators[kind](val, spec)
	end
	if kind == nil and typeof(spec) == "table" and spec.keys then
		return Validators.table(val, spec)
	end
	return true
end

local function makeLimiter(ratePerSec, burst)
	local bucket = {}
	ratePerSec = math.max(ratePerSec or 5, 0.1)
	burst      = math.max(burst or ratePerSec, 1)
	return function(player, cost)
		cost = cost or 1
		local b = bucket[player]
		local t = now()
		if not b then
			b = { tokens = burst, last = t }
			bucket[player] = b
		end
		local dt = t - b.last
		b.tokens = math.min(burst, b.tokens + dt * ratePerSec)
		b.last = t
		if b.tokens >= cost then
			b.tokens = b.tokens - cost
			return true
		else
			return false
		end
	end
end

local function makeCooldown()
	local last = {}
	return function(player, route, cd)
		local t = now()
		local map = last[player]; if not map then map = {}; last[player]=map end
		local prev = map[route] or -1e9
		if t - prev >= cd then
			map[route] = t
			return true
		end
		return false
	end
end

local function makeLogger()
	local lastWarn = 0
	return function(...)
		local t = now()
		if t - lastWarn > 0.2 then
			lastWarn = t
			warn("[RemoteManager]", ...)
		end
	end
end

local RemoteManager = {}
RemoteManager.__index = RemoteManager

function RemoteManager.new()
	local self = setmetatable({}, RemoteManager)

	local netRoot = ensureFolder(ReplicatedStorage, FOLDER_NAME)
	self._namespace = ensureFolder(netRoot, VERSION)

	self._events    = {}
	self._functions = {}

	self._limiters  = {}
	self._cooldowns = {}
	self._logger    = makeLogger()

	return self
end

function RemoteManager:RegisterEvent(route, handler, opts)
	assert(IS_SERVER, "RegisterEvent must run on server")
	assert(typeof(route)=="string" and route~="", "bad route")
	assert(typeof(handler)=="function", "handler must be function")
	opts = opts or {}

	local ev = self._namespace:FindFirstChild(route)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = route
		ev.Parent = self._namespace
	end

	-- setup guards
	local limiter = self._limiters[route] or makeLimiter(opts.rate or 8, opts.burst or 16)
	self._limiters[route] = limiter

	local cd = self._cooldowns[route] or makeCooldown()
	self._cooldowns[route] = cd

	local schema = opts.schema
	local middlewares = opts.middlewares or {}
	local maxBytes = opts.maxPayloadBytes or 3000

	ev.OnServerEvent:Connect(function(player, payload)
		if typeof(player) ~= "Instance" or player.ClassName ~= "Player" then return end

		if jsonSize(payload) > maxBytes then
			self._logger(route, "payload too large from", player.Name)
			return
		end
		if not limiter(player, 1) then
			return
		end
		if opts.cooldown and opts.cooldown > 0 then
			if not cd(player, route, opts.cooldown) then
				return
			end
		end

		-- schema
		if schema then
			local ok, err = Validators.any(payload, schema)
			if not ok then
				self._logger(route, "schema reject", player.Name, err)
				return
			end
		end

		-- middleware chain
		for _,mw in ipairs(middlewares) do
			local ok, reason = mw(player, payload)
			if not ok then
				if opts.verbose then self._logger(route, "middleware reject", reason or "?") end
				return
			end
		end

		-- user handler (pcall guard)
		local ok, err = pcall(handler, player, payload)
		if not ok then
			self._logger(route, "handler error:", err)
		end
	end)

	self._events[route] = { opts = opts }
	return route
end

function RemoteManager:RegisterFunction(route, handler, opts)
	assert(IS_SERVER, "RegisterFunction must run on server")
	assert(typeof(route)=="string" and route~="", "bad route")
	assert(typeof(handler)=="function", "handler must be function")
	opts = opts or {}

	local rf = self._namespace:FindFirstChild(route)
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = route
		rf.Parent = self._namespace
	end

	local limiter  = self._limiters[route] or makeLimiter(opts.rate or 5, opts.burst or 10)
	self._limiters[route] = limiter
	local cd       = self._cooldowns[route] or makeCooldown()
	self._cooldowns[route] = cd
	local schema   = opts.schema
	local mws      = opts.middlewares or {}
	local maxBytes = opts.maxPayloadBytes or 3000

	rf.OnServerInvoke = function(player, payload)
		if jsonSize(payload) > maxBytes then return nil end
		if not limiter(player, 1) then return nil end
		if opts.cooldown and opts.cooldown > 0 then
			if not cd(player, route, opts.cooldown) then return nil end
		end
		if schema then
			local ok = Validators.any(payload, schema)
			if not ok then return nil end
		end
		for _,mw in ipairs(mws) do
			local ok = mw(player, payload)
			if not ok then return nil end
		end
		local ok, result = pcall(handler, player, payload)
		if not ok then
			self._logger(route, "function handler error:", result)
			return nil
		end
		return result
	end

	self._functions[route] = { opts = opts }
	return route
end

function RemoteManager:GetEvent(route)
	return self._namespace:WaitForChild(route)
end

function RemoteManager:GetFunction(route)
	return self._namespace:WaitForChild(route)
end

return RemoteManager
