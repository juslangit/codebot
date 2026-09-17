--!strict
--[[
	RoomView — the part you can see.

	Builds a room out of parts from the same picture the rules were read from,
	puts a robot on it, points the camera at it, and plays back the events the
	world produced.

	It holds no rules of its own. Where the robot *is* was decided by RobotWorld
	before this file was asked to move anything, which is why the rules could be
	tested without a screen. If the robot appears somewhere wrong, the bug is
	here; if it goes somewhere wrong, the bug is there.

	Everything is built on the client. That is fine while each player has their
	own room, and is the one thing that has to change for M7, when the room
	becomes shared and the server builds it.
]]

local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)

local RoomView = {}

local TILE = 6
local WALL_HEIGHT = 5
local FLOOR_THICKNESS = 1
local ROBOT_HEIGHT = 1.8
local MOVE_TIME = 0.28
local TURN_TIME = 0.18
local BUMP_TIME = 0.16

-- Which way the robot faces, as a rotation about Y. A part with no rotation
-- looks down -Z, which is north on our grid.
local YAW_FOR_DIRECTION = { 0, -90, 180, 90 }

local View = {}
View.__index = View

export type View = typeof(setmetatable(
	{} :: {
		room: any,
		world: any,
		folder: Folder,
		body: BasePart,
		head: BasePart,
		eye: BasePart,
		goalPart: BasePart?,
		originX: number,
		originZ: number,
		yaw: number,
		camera: Camera,
	},
	View
))

local function makePart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = true
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function tileCentre(self: View, x: number, y: number): Vector3
	return Vector3.new((x * TILE) - self.originX, 0, (y * TILE) - self.originZ)
end

-- The body is what gets moved. The head and the eye are hung off it afterwards,
-- so there is only ever one thing to position.
local function align(self: View)
	self.head.CFrame = self.body.CFrame * CFrame.new(0, 1.7, 0)
	self.eye.CFrame = self.body.CFrame * CFrame.new(0, 0.3, -1.35)
end

local function setRobot(self: View, position: Vector3, yaw: number)
	self.body.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(yaw), 0)
	align(self)
end

local function standingPosition(self: View): Vector3
	return tileCentre(self, self.world.x, self.world.y) + Vector3.new(0, ROBOT_HEIGHT, 0)
end

function RoomView.create(room: any, world: any, parent: Instance): View
	local folder = Instance.new("Folder")
	folder.Name = "Room" .. room.id
	folder.Parent = parent

	local self: any = setmetatable({
		room = room,
		world = world,
		folder = folder,
		body = nil,
		head = nil,
		eye = nil,
		goalPart = nil,
		originX = (world.width + 1) * TILE / 2,
		originZ = (world.height + 1) * TILE / 2,
		yaw = YAW_FOR_DIRECTION[world.dir],
		camera = workspace.CurrentCamera,
	}, View)

	for y, row in room.map do
		for x = 1, #row do
			local character = string.sub(row, x, x)
			local centre = tileCentre(self, x, y)

			if character == "#" then
				local wall = makePart("Wall", folder)
				wall.Size = Vector3.new(TILE, WALL_HEIGHT, TILE)
				wall.Position = centre + Vector3.new(0, WALL_HEIGHT / 2, 0)
				wall.Color = Theme.wall
				wall.Material = Enum.Material.Slate
			else
				local floor = makePart("Floor", folder)
				floor.Size = Vector3.new(TILE - 0.3, FLOOR_THICKNESS, TILE - 0.3)
				floor.Position = centre - Vector3.new(0, FLOOR_THICKNESS / 2, 0)
				-- A chequer, so counting tiles by eye is possible. Room 4 asks
				-- the player to work out that the hall is ten tiles long.
				floor.Color = if (x + y) % 2 == 0 then Theme.floor else Theme.floorAlt

				if character == "G" then
					floor.Color = Theme.warm
					floor.Material = Enum.Material.Neon

					local marker = makePart("Goal", folder)
					marker.Size = Vector3.new(TILE - 2.4, 0.2, TILE - 2.4)
					marker.Position = centre + Vector3.new(0, 0.1, 0)
					marker.Color = Theme.warm
					marker.Material = Enum.Material.Neon
					marker.Transparency = 0.3
					self.goalPart = marker
				end
			end
		end
	end

	local robot = Instance.new("Model")
	robot.Name = "Robot"
	robot.Parent = folder

	local body = makePart("Body", robot)
	body.Size = Vector3.new(2.6, 2.6, 2.6)
	body.Color = Theme.accent
	body.Material = Enum.Material.Metal

	local head = makePart("Head", robot)
	head.Size = Vector3.new(1.8, 0.9, 1.8)
	head.Color = Theme.panelLight
	head.Material = Enum.Material.Metal

	-- A single eye on the front face, so which way it is facing is obvious at a
	-- glance. A beginner cannot debug turnRight() if they cannot see the front.
	local eye = makePart("Eye", robot)
	eye.Size = Vector3.new(1.2, 0.5, 0.2)
	eye.Color = Theme.warm
	eye.Material = Enum.Material.Neon

	robot.PrimaryPart = body
	self.body, self.head, self.eye = body, head, eye
	setRobot(self, standingPosition(self), self.yaw)

	return self :: View
end

function View.focusCamera(self: View)
	local camera = self.camera
	camera.CameraType = Enum.CameraType.Scriptable

	-- Far enough back that the biggest room still fits, and high enough that the
	-- walls do not hide the floor the robot is standing on.
	local span = math.max(self.world.width, self.world.height) * TILE
	local height = span * 0.85 + 14
	local back = span * 0.55 + 10

	camera.CFrame = CFrame.lookAt(Vector3.new(0, height, back), Vector3.new(0, 0, -TILE * 0.3))
end

function View.reset(self: View)
	self.yaw = YAW_FOR_DIRECTION[self.world.dir]
	setRobot(self, standingPosition(self), self.yaw)
	if self.goalPart then
		(self.goalPart :: BasePart).Transparency = 0.3
	end
end

function View.destroy(self: View)
	self.folder:Destroy()
end

--[[
	Plays one event and waits for it to finish. Called by the driver between
	interpreter steps, never by a builtin — a builtin that waited would be
	mistaken by the interpreter for a step boundary.
]]
function View.play(self: View, event: any)
	if event.kind == "move" then
		local from = tileCentre(self, event.fromX, event.fromY) + Vector3.new(0, ROBOT_HEIGHT, 0)
		local to = tileCentre(self, event.toX, event.toY) + Vector3.new(0, ROBOT_HEIGHT, 0)
		local started = os.clock()

		while true do
			local alpha = math.min((os.clock() - started) / MOVE_TIME, 1)
			-- Ease out, so a step lands rather than stopping dead.
			local eased = 1 - (1 - alpha) ^ 3
			setRobot(self, from:Lerp(to, eased), self.yaw)
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	elseif event.kind == "turn" then
		local fromYaw = self.yaw
		-- Always turn the short way, so a turn never spins the long way round.
		local delta = if (event.to - event.from) % 4 == 1 then -90 else 90
		local toYaw = fromYaw + delta
		local centre = standingPosition(self)
		local started = os.clock()

		while true do
			local alpha = math.min((os.clock() - started) / TURN_TIME, 1)
			setRobot(self, centre, fromYaw + (toYaw - fromYaw) * alpha)
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		self.yaw = toYaw
	elseif event.kind == "bump" then
		-- A short nudge forward and back. The robot tried, and could not.
		local centre = standingPosition(self)
		local target = tileCentre(self, event.x, event.y)
		local towards = (target - tileCentre(self, self.world.x, self.world.y)).Unit
		local started = os.clock()

		while true do
			local alpha = math.min((os.clock() - started) / BUMP_TIME, 1)
			local nudge = math.sin(alpha * math.pi) * 0.9
			setRobot(self, centre + towards * nudge, self.yaw)
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	elseif event.kind == "solved" and self.goalPart then
		local marker = self.goalPart :: BasePart
		local started = os.clock()
		while os.clock() - started < 0.5 do
			local pulse = (math.sin((os.clock() - started) * 24) + 1) / 2
			marker.Transparency = 0.05 + pulse * 0.45
			RunService.RenderStepped:Wait()
		end
		marker.Transparency = 0.3
	end
end

return RoomView
