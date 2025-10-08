-- ReplicatedStorage/Modules/UIAnimations.lua
local TweenService = game:GetService("TweenService")

local UIAnimations = {}

-- cache per-frame controllers so you can call :Toggle() anywhere
local controllers = setmetatable({}, { __mode = "k" }) -- weak keys

export type LeaderboardController = {
	Open: () -> (),
	Close: () -> (),
	Toggle: () -> (),
	IsOpen: () -> boolean,
}

function UIAnimations.BindLeaderboard(frame: GuiObject, tweenTime: number?, easingStyle: Enum.EasingStyle?, easingDir: Enum.EasingDirection?)
	assert(frame and frame:IsA("GuiObject"), "BindLeaderboard expects a GuiObject")

	-- return existing controller if already bound
	if controllers[frame] then
		return controllers[frame]
	end

	-- remember original (open) position
	local openPos: UDim2 = frame.Position -- expected UDim2.new(0.7, 0, 0, 0)
	local closedPos: UDim2 = UDim2.new(1, 0, 0, 0)
	local isOpen = true

	local info = TweenInfo.new(
		tweenTime or 0.25,
		easingStyle or Enum.EasingStyle.Quad,
		easingDir or Enum.EasingDirection.Out
	)

	local function tweenTo(pos: UDim2)
		TweenService:Create(frame, info, { Position = pos }):Play()
	end

	-- define functions first to avoid self-reference issues
	local function open()
		if not isOpen then
			isOpen = true
			tweenTo(openPos)
		end
	end

	local function close()
		if isOpen then
			isOpen = false
			tweenTo(closedPos)
		end
	end

	local function toggle()
		if isOpen then
			close()
		else
			open()
		end
	end

	local controller: LeaderboardController = {
		Open = open,
		Close = close,
		Toggle = toggle,
		IsOpen = function() return isOpen end,
	}

	controllers[frame] = controller
	return controller
end

-- Fades a full-screen Frame by tweening BackgroundTransparency
function UIAnimations.BindScreenFader(frame: GuiObject, fadeInTime: number?, fadeOutTime: number?)
	assert(frame and frame:IsA("GuiObject"), "BindScreenFader expects a GuiObject")

	-- default timings
	local tIn  = fadeInTime  or 0.35 -- to black
	local tOut = fadeOutTime or 0.35 -- from black

	-- Ensure starting invisible
	frame.Visible = true
	frame.BackgroundTransparency = 1

	local busy = false

	local function tween(propTable, time)
		return TweenService:Create(frame, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), propTable)
	end

	local function FadeToBlack(customTime: number?)
		if busy then return end
		busy = true
		tween({ BackgroundTransparency = 0 }, customTime or tIn):Play()
		task.delay(customTime or tIn, function() busy = false end)
	end

	local function FadeFromBlack(customTime: number?)
		if busy then return end
		busy = true
		tween({ BackgroundTransparency = 1 }, customTime or tOut):Play()
		task.delay(customTime or tOut, function() busy = false end)
	end

	local function FadePulse(holdTime: number?, inTime: number?, outTime: number?)
		if busy then return end
		busy = true
		local _in  = inTime  or tIn
		local _out = outTime or tOut
		local hold = holdTime or 0.05

		local twIn = tween({ BackgroundTransparency = 0 }, _in)
		twIn:Play()
		task.delay(_in + hold, function()
			local twOut = tween({ BackgroundTransparency = 1 }, _out)
			twOut:Play()
			task.delay(_out, function() busy = false end)
		end)
	end

	return {
		FadeToBlack = FadeToBlack,
		FadeFromBlack = FadeFromBlack,
		FadePulse = FadePulse,
	}
end

-- ReplicatedStorage/Modules/UIAnimations.lua (append this)
local RunService = game:GetService("RunService")

function UIAnimations.AnimateRewardsRowsLanes(args)
	assert(args and typeof(args) == "table", "AnimateRewardsRowsLanes: args table required")

	local overlay     = args.overlay
	local holder      = args.holder
	local rowTemplate = args.rowTemplate
	local items       = args.items or {}
	local startFrom   = args.startFrom
	assert(overlay and overlay:IsA("GuiObject"), "overlay must be a GuiObject")
	assert(holder and holder:IsA("Instance"), "holder required")
	assert(rowTemplate and rowTemplate:IsA("GuiObject"), "rowTemplate must be a GuiObject")
	assert(startFrom and startFrom:IsA("GuiObject"), "startFrom must be a GuiObject")

	local initialDelay = args.initialDelay or 2.5
	local stepDelay    = args.stepDelay or 1.0
	local duration     = args.duration or 1
	local perRow       = math.max(1, args.perRow or 5)
	local info         = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- three fixed lane points (we'll force X=0.5 and ignore X/Offset from input)
	local points = args.points

	-- Clean old rows (keep template + layout helpers)
	for _, child in ipairs(holder:GetChildren()) do
		if child ~= rowTemplate
			and not child:IsA("UIListLayout")
			and not child:IsA("UIPadding")
			and not child:IsA("UISizeConstraint")
			and not child:IsA("UIAspectRatioConstraint")
		then
			child:Destroy()
		end
	end

	-- Build rows (UIListLayout controls placement; we don't move rows)
	local nRows = math.ceil(#items / perRow)
	local rows = table.create(nRows)
	for i = 1, nRows do
		local row = rowTemplate:Clone()
		row.Name = ("Row_%d"):format(i)
		row.Visible = false -- start hidden; window will reveal 1..3
		row.LayoutOrder = i
		row.Parent = holder
		rows[i] = row
	end

	local origSize = {}
	for _, row in ipairs(rows) do
		origSize[row] = row.Size
	end

	RunService.Heartbeat:Wait()

	-- 3-row visibility window helpers
	local function setRowWindow(startIndex: number, animate: boolean?)
		for i, row in ipairs(rows) do
			local shouldBeVisible = (i >= startIndex and i <= startIndex + 2)
			if shouldBeVisible then
				if not row.Visible then
					row.Size = origSize[row] -- restore original size BEFORE making visible
					row.Visible = true
				end
			else
				if row.Visible then
					if animate then
						local tw = TweenService:Create(row, info, { Size = UDim2.new(1, 0, 0, 0) })
						tw:Play()
						tw.Completed:Once(function()
							row.Visible = false
						end)
					else
						row.Visible = false
						row.Size = UDim2.new(1, 0, 0, 0)
					end
				end
			end
		end
	end

	-- Start with rows 1..3 visible
	local windowStart = 1
	if nRows > 0 then
		setRowWindow(windowStart, false)
	end

	-- Compute scale-based start position (X=0.5, Y as scale)
	local overlayAbs  = overlay.AbsolutePosition
	local overlaySize = overlay.AbsoluteSize
	local startAbs    = startFrom.AbsolutePosition
	local startYScale = (startAbs.Y - overlayAbs.Y) / math.max(1, overlaySize.Y)
	local startPosUD  = UDim2.new(0.5, 0, startYScale, 0)

	-- Helper: lane target with X locked to 0.5, Y taken from points' Y.Scale
	local function laneTargetUD(laneIdx: number): UDim2
		local p = points[math.clamp(laneIdx, 1, #points)]
		return UDim2.new(0.5, 0, p.Y.Scale, 0)
	end

	local rowBegan = {}

	for i, real in ipairs(items) do
		local rowIndex = math.floor((i - 1) / perRow) + 1
		local row = rows[rowIndex]
		if row then
			real.Parent = row
			real.Visible = false
			real.Size = UDim2.new(0.15, 0, 1, 0)

			local ghost = real:Clone()
			ghost.Parent   = overlay.Tweening or overlay
			ghost.Position = startPosUD
			ghost.Size     = UDim2.fromOffset(real.AbsoluteSize.X, real.AbsoluteSize.Y)
			ghost.Visible  = false

			task.delay(initialDelay + (i - 1) * stepDelay, function()
				if not rowBegan[rowIndex] then
					rowBegan[rowIndex] = true
					local needStart = math.max(1, rowIndex - 2)
					if needStart ~= windowStart then
						windowStart = needStart
						setRowWindow(windowStart, true)
					end
				end

				if not ghost.Parent then return end
				ghost.Visible = true

				local lane = math.clamp(rowIndex - windowStart + 1, 1, 3)
				local targetUD = laneTargetUD(lane)

				local tw = TweenService:Create(ghost, info, { Position = targetUD })
				tw:Play()
				tw.Completed:Once(function()
					if real and real.Parent == row then
						real.Visible = true
					end
					if ghost and ghost.Parent then
						ghost:Destroy()
					end
				end)
			end)
		end
	end
end


return UIAnimations
