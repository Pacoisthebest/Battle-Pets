local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local player            = Players.LocalPlayer

local FOLDER_NAME = "Net"
local VERSION     = "v1"

local netRoot = ReplicatedStorage:WaitForChild(FOLDER_NAME)
local ns      = netRoot:WaitForChild(VERSION)

local Net = {}

function Net:Event(route)
	return ns:WaitForChild(route)
end

-- Fire event
function Net:Fire(route, payload)
	self:Event(route):FireServer(payload)
end

-- Invoke with timeout (seconds). Returns (ok, resultOrError)
function Net:Invoke(route, payload, timeoutSec)
	timeoutSec = timeoutSec or 5
	local rf = ns:WaitForChild(route)
	local done, result
	task.spawn(function()
		result = rf:InvokeServer(payload)
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < timeoutSec do task.wait() end
	if done then return true, result end
	return false, "timeout"
end
return Net
