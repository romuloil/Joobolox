-- Execute PoliceService itself with controlled time, raycasts and service doubles.
-- Does not emulate engine physics, tool rendering or actual network replication.
return function(mockSource, configSource, rulesSource, serviceSource)
	local checks = 0
	local function check(name, result) checks += 1; assert(result, name) end
	local function fixture(failPreparation)
		local m = assert(loadstring(mockSource))()
		local time, queue = 1000, {}
		local warnings = {}
		m.env.warn = function(message) table.insert(warnings, message) end
		local function signal()
			local callbacks = {}
			return {
				Connect = function(_, fn) table.insert(callbacks, fn); return { Disconnect = function() end } end,
				Fire = function(_, ...) for _, fn in ipairs(callbacks) do fn(...) end end,
			}
		end
		local function schedule(delay, fn, ...)
			table.insert(queue, { at = time + delay, thread = coroutine.create(fn), args = {...} })
		end
		local function advance(duration)
			local untilTime = time + duration
			local iterations = 0
			while true do
				local selected, earliest
				for index, item in ipairs(queue) do
					if item.at <= untilTime and (not earliest or item.at < earliest) then selected, earliest = index, item.at end
				end
				if not selected then break end
				time = earliest
				local item = table.remove(queue, selected)
				local ok, delay = coroutine.resume(item.thread, table.unpack(item.args))
				assert(ok, delay)
				if coroutine.status(item.thread) ~= "dead" then table.insert(queue, { at = time + (delay or 0), thread = item.thread, args = {} }) end
				iterations += 1; assert(iterations < 100000, "clock stalled")
			end
			time = untilTime
		end
		m.env.task = {
			spawn = function(fn, ...) schedule(0, fn, ...) end,
			defer = function(fn, ...) schedule(0, fn, ...) end,
			delay = function(delay, fn, ...) schedule(delay, fn, ...) end,
			wait = function(delay) return coroutine.yield(delay or 0) end,
		}
		local v, cf = m.Vector3, m.CFrame
		local newInstance = m.Instance.new
		local function instance(class)
			local p = newInstance(class)
			if class == "ProximityPrompt" then p.Triggered = signal() end
			return p
		end
		m.env.Instance = { new = instance }
		m.env.RaycastParams = { new = function() return {} end }
		m.env.TweenInfo = { new = function(seconds) return { seconds = seconds } end }
		m.Workspace.GetServerTimeNow = function() return time end
		local nextHit
		m.Workspace.Raycast = function()
			local result = nextHit; nextHit = nil; return result
		end
		m.services.TweenService = { Create = function(_, part, _, values)
			return { Play = function() for key, value in pairs(values) do part[key] = value end end }
		end }
		m.services.Debris = { AddItem = function(_, item, delay) schedule(delay, function() item:Destroy() end) end }
		local Players = { list = {}, PlayerAdded = signal(), PlayerRemoving = signal() }
		function Players:GetPlayers() return self.list end
		function Players:GetPlayerByUserId(id) for _, p in ipairs(self.list) do if p.UserId == id then return p end end end
		function Players:GetPlayerFromCharacter(character) for _, p in ipairs(self.list) do if p.Character == character then return p end end end
		m.services.Players = Players
		m.services.RunService = { IsStudio = function() return false end }
		local function makePlayer(id)
			local attributes, changes = { Money = 781 }, {}
			local character = instance("Model"); character.Name = "Character" .. id; character.Parent = m.Workspace
			local root = instance("Part"); root.Name = "HumanoidRootPart"; root.CFrame = cf.new(0, 4, 0); root.Parent = character
			local head = instance("Part"); head.Name = "Head"; head.CFrame = cf.new(0, 5.5, 0); head.Parent = character
			local torso = instance("Part"); torso.Name = "UpperTorso"; torso.CFrame = root.CFrame; torso.Parent = character
			local humanoid = instance("Humanoid"); humanoid.Name = "Humanoid"; humanoid.Health = 100; humanoid.WalkSpeed = 16
			humanoid.JumpPower, humanoid.JumpHeight = 50, 7.2; humanoid.Parent = character
			local backpack = instance("Backpack")
			local player = { Parent = Players, Name = "Player" .. id, DisplayName = "Player" .. id, UserId = id, Character = character, CharacterAdded = signal() }
			function player:GetAttribute(name) return attributes[name] end
			function player:SetAttribute(name, value)
				local before = attributes[name]; attributes[name] = value
				if before ~= value and changes[name] then changes[name]:Fire() end
			end
			function player:GetAttributeChangedSignal(name)
				if not changes[name] then changes[name] = signal() end
				return changes[name]
			end
			function player:FindFirstChildOfClass(name) return name == "Backpack" and backpack or nil end
			function player:FindFirstChild(name) return name == "Backpack" and backpack or nil end
			table.insert(Players.list, player)
			return player
		end
		local player = makePlayer(1)
		local rate = {}
		m.load("SecurityService", "return {}", true)
		m.registry.SecurityService = {
			getLivingCharacter = function(p)
				local c = p.Character
				local h, root = c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
				if not h or not root or h.Health <= 0 then return nil end
				return c, h, root
			end,
			checkRate = function(p, key, interval)
				key = tostring(p.UserId) .. key
				if rate[key] and time - rate[key] < interval then return false end
				rate[key] = time; return true
			end,
			isShortString = function(value, length) return type(value) == "string" and #value > 0 and #value <= length end,
		}
		m.load("GameConfig", "return {Remotes={UIUpdate='UIUpdate',PoliceRequest='PoliceRequest'}}")
		m.load("PoliceConfig", configSource)
		m.load("PoliceRules", rulesSource)
		local service = m.load("PoliceService", serviceSource, true)
		local messages, captures, preparation, stunPreparations, cellOperations = {}, {}, 0, 0, {}
		local cellState = {id="01",open=false,occupied=true,lockedUntil=1015}
		local update = { FireClient = function(_, p, kind, data) table.insert(messages, { player = p, kind = kind, data = data }) end }
		local request = { OnServerEvent = signal() }
		local function prompt(x)
			local anchor = instance("Part"); anchor.CFrame = cf.new(x, 4, 0); anchor.Parent = m.Workspace
			local p = instance("ProximityPrompt"); p.Parent = anchor; return p
		end
		local doorPart = instance("Part"); doorPart.CFrame = cf.new(50, 4, 0); doorPart.Size = v.new(6, 8, 1); doorPart.Parent = m.Workspace
		local door = { id = "gate", name = "Portão", part = doorPart, closed = doorPart.CFrame, open = cf.new(60, 4, 0), prompt = prompt(45) }
		local trainingSpawn = instance("Part"); trainingSpawn.CFrame = cf.new(66, 4, 0); trainingSpawn.Parent = m.Workspace
		local sites = { dutyPrompts = {prompt(0)}, armoryPrompts = {prompt(10)}, reportPrompts = {prompt(20)}, controlPrompts = {prompt(30)},
			patrolPrompts = {prompt(40),prompt(50)}, doors = {door}, trainingPrompt = prompt(60), trainingSpawn = trainingSpawn }
		service.init({ UIUpdate = update, PoliceRequest = request }, { police = sites }, {
			beforeStun = function(p)
				stunPreparations += 1
				p.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = 16
			end,
			beforeDuty = function() preparation += 1; if failPreparation then error("expected test failure") end end,
			prisonService = {
				getCellControls = function() return {cellState} end,
				setCellDoor = function(id, open)
					table.insert(cellOperations, {id=id,open=open})
					if open and time < cellState.lockedUntil then return false, "locked" end
					cellState.open=open; return true
				end,
				detain = function(p)
				if p:GetAttribute("Detained") then return false end
				table.insert(captures, p); p:SetAttribute("Detained", true); return true
			end },
		})
		advance(0)
		local function move(p, x)
			p.Character:FindFirstChild("HumanoidRootPart").CFrame = cf.new(x, 4, 0)
			p.Character:FindFirstChild("Head").CFrame = cf.new(x, 5.5, 0)
		end
		local function equip(p, id)
			local bag = p:FindFirstChildOfClass("Backpack")
			for _, item in ipairs(p.Character:GetChildren()) do if item:IsA("Tool") then item.Parent = bag end end
			for _, item in ipairs(bag:GetChildren()) do if item:GetAttribute("PoliceTool") == id then item.Parent = p.Character; return item end end
		end
		local function addPlayer(id)
			local p = makePlayer(id); Players.PlayerAdded:Fire(p); advance(0); return p
		end
		local function lastState(p)
			for index = #messages, 1, -1 do local e = messages[index]; if e.player == p and e.kind == "PoliceState" then return e.data end end
		end
		return { m = m, service = service, player = player, sites = sites, messages = messages, captures = captures, request = request,
			advance = advance, move = move, equip = equip, addPlayer = addPlayer, Players = Players, lastState = lastState,
			prepared = function() return preparation end,
			stunPrepared = function() return stunPreparations end,
			cellOperations = cellOperations, cellState=cellState,
			warnings = warnings,
			hitModel = function(model) nextHit = { Instance = model:FindFirstChild("Head"), Position = model:FindFirstChild("Head").Position } end,
			hit = function(p) nextHit = { Instance = p.Character:FindFirstChild("Head"), Position = p.Character:FindFirstChild("Head").Position } end,
			blockRay = function() nextHit = { Instance = doorPart, Position = doorPart.Position } end,
		}
	end

	local f = fixture()
	check("civilian cannot obtain gear", not f.service.requestGear(f.player))
	f.move(f.player, 100)
	check("distant player cannot join duty", not f.service.join(f.player))
	f.move(f.player, 0); f.player:SetAttribute("Detained", true)
	check("inmate cannot join duty", not f.service.join(f.player))
	f.player:SetAttribute("Detained", false)
	check("nearby civilian joins duty", f.service.join(f.player))
	check("duty reserves one slot", f.player:GetAttribute("PoliceDuty") == true and f.lastState(f.player).count == 1)
	check("duty preparation called once", f.prepared() == 1)
	check("repeat join is idempotent", f.service.join(f.player) and f.lastState(f.player).count == 1 and f.prepared() == 1)
	local second, third, fourth = f.addPlayer(2), f.addPlayer(3), f.addPlayer(4)
	check("second officer joins", f.service.join(second))
	check("third officer joins", f.service.join(third))
	check("fourth officer refused", not f.service.join(fourth))
	check("vacancy available after leave", f.service.leave(second) and f.service.join(fourth))
	f.move(f.player, 100)
	check("gear requires armory proximity", not f.service.requestGear(f.player))
	f.move(f.player, 10)
	check("armory issues equipment", f.service.requestGear(f.player))
	check("exactly four police tools issued", #f.player:FindFirstChildOfClass("Backpack"):GetChildren() == 4)
	check("reissue refreshes instead of duplicating", f.service.requestGear(f.player) and #f.player:FindFirstChildOfClass("Backpack"):GetChildren() == 4)
	f.move(f.player, 20)
	check("valid report recorded", f.service.submitReport(f.player, {category="Seguranca"}))
	check("rapid duplicate report refused", not f.service.submitReport(f.player, {category="Seguranca"}))
	f.advance(10.1)
	check("free-form report refused", not f.service.submitReport(f.player, {category="arbitrary text"}))
	f.move(f.player, 100)
	check("report requires terminal proximity", not f.service.submitReport(f.player, {category="Patrulha"}))
	check("distant control command refused", not f.service.toggleDoor(f.player, "gate"))
	f.move(f.player, 30)
	check("officer at terminal opens secure door", f.service.toggleDoor(f.player, "gate"))
	check("door physically moves clear", f.sites.doors[1].part.CFrame.Position.X == 60)
	check("busy door rejects another toggle", not f.service.toggleDoor(f.player, "gate"))
	f.advance(0.7); f.move(third, 50)
	check("door refuses to close on a character", not f.service.toggleDoor(f.player, "gate"))
	f.move(third, 0)
	check("empty doorway can close", f.service.toggleDoor(f.player, "gate"))
	f.advance(0.7)
	f.move(f.player, 40); f.sites.patrolPrompts[2].Triggered:Fire(f.player)
	check("patrol cannot skip checkpoint", f.lastState(f.player).patrolStep == 0)
	f.advance(0.4)
	f.sites.patrolPrompts[1].Triggered:Fire(f.player)
	check("first patrol checkpoint accepted", f.lastState(f.player).patrolStep == 1)
	f.advance(0.4); f.move(f.player, 50); f.sites.patrolPrompts[2].Triggered:Fire(f.player)
	check("completed patrol resets for next route", f.lastState(f.player).patrolStep == 0)
	check("police duties do not change money", f.player:GetAttribute("Money") == 781)
	check("leaving returns all issued tools", f.service.leave(f.player) and #f.player:FindFirstChildOfClass("Backpack"):GetChildren() == 0)
	check("off-duty door command refused", not f.service.toggleDoor(f.player, "gate"))
	check("off-duty cell control refused", not f.service.toggleDoor(f.player, "Cell:01"))
	check("rejected cell command never calls prison controls", #f.cellOperations == 0)

	local cellControl = fixture()
	cellControl.service.join(cellControl.player)
	cellControl.move(cellControl.player, 100)
	check("distant officer cannot control cells", not cellControl.service.toggleDoor(cellControl.player, "Cell:01"))
	check("distant cell command never reaches prison", #cellControl.cellOperations == 0)
	cellControl.move(cellControl.player, 30)
	check("police cell controls respect initial prisoner lock", not cellControl.service.toggleDoor(cellControl.player, "Cell:01"))
	cellControl.advance(15.2)
	check("officer at terminal can open unlocked cell", cellControl.service.toggleDoor(cellControl.player, "Cell:01"))
	check("valid police command forwarded to prison", cellControl.cellState.open == true)

	local capture = fixture()
	local officer = capture.player
	local suspect = capture.addPlayer(2)
	capture.service.join(officer); capture.service.requestGear(officer)
	capture.move(suspect, 5); capture.equip(officer, "Cuff")
	check("innocent cannot be captured", not capture.service.capture(officer, suspect.UserId))
	check("server can mark legitimate suspect", capture.service.markSuspect(suspect, "test crime", 120))
	capture.advance(0.6)
	check("unstunned suspect cannot be captured", not capture.service.capture(officer, suspect.UserId))
	capture.equip(officer, "Spray"); capture.hit(suspect)
	check("equipped water launcher fires", capture.service.spray(officer, { direction=capture.m.Vector3.new(1,0,0) }))
	check("wanted suspect becomes stunned", suspect.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 0 and suspect:GetAttribute("StunnedUntil") > 1000)
	check("spray cooldown enforced", not capture.service.spray(officer, { direction=capture.m.Vector3.new(1,0,0) }))
	capture.equip(officer, "Cuff"); capture.advance(0.6); capture.blockRay()
	check("cuffs cannot pass through walls", not capture.service.capture(officer, suspect.UserId))
	capture.advance(0.6)
	check("valid stun and cuffs detain suspect", capture.service.capture(officer, suspect.UserId))
	check("captured suspect forwarded once", #capture.captures == 1 and suspect:GetAttribute("Detained") == true)
	check("capture clears wanted state", suspect:GetAttribute("Wanted") == false)
	check("capture clears jumping impairment", suspect.Character:FindFirstChildOfClass("Humanoid").JumpPower == 50 and suspect.Character:FindFirstChildOfClass("Humanoid").JumpHeight == 7.2)
	capture.advance(0.6)
	check("repeated capture refused", not capture.service.capture(officer, suspect.UserId) and #capture.captures == 1)
	check("capture preserves prior balance", suspect:GetAttribute("Money") == 781)

	local protected = fixture()
	protected.service.join(protected.player); protected.service.requestGear(protected.player)
	local civil = protected.addPlayer(2); protected.move(civil, 5)
	protected.equip(protected.player, "Spray"); protected.hit(civil)
	protected.service.spray(protected.player, {direction=protected.m.Vector3.new(1,0,0)})
	check("water causes no stun to innocent civilian", civil.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 16)
	civil:SetAttribute("InWorkZone", "Market")
	check("protected worker cannot be marked suspect", not protected.service.markSuspect(civil, "test", 60))
	civil:SetAttribute("InWorkZone", nil)
	protected.service.markSuspect(civil, "test", 5)
	protected.advance(5.2)
	check("wanted state expires", civil:GetAttribute("Wanted") == false)
	protected.player:SetAttribute("Detained", true)
	check("detention removes police duty", protected.player:GetAttribute("PoliceDuty") == false)
	check("detention removes police equipment", #protected.player:FindFirstChildOfClass("Backpack"):GetChildren() == 0)

	local recovery = fixture()
	recovery.service.join(recovery.player); recovery.service.requestGear(recovery.player)
	local runner = recovery.addPlayer(2); recovery.move(runner, 5)
	runner.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = 30
	recovery.service.markSuspect(runner, "test", 60)
	recovery.equip(recovery.player, "Spray"); recovery.hit(runner)
	recovery.service.spray(recovery.player, {direction=recovery.m.Vector3.new(1,0,0)})
	check("stun prepares vehicle removal", recovery.stunPrepared() == 1)
	check("stun captures walking speed after vehicle removal", runner.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 0)
	recovery.advance(6.2)
	check("stun expiration restores normal walking speed", runner.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 16)
	check("stun expiration restores jumping", runner.Character:FindFirstChildOfClass("Humanoid").JumpPower == 50)
	check("server-wanted suspect cannot join police", not recovery.service.join(runner))

	local spoof = fixture()
	spoof.service.join(spoof.player); spoof.service.requestGear(spoof.player)
	local falseWanted = spoof.addPlayer(2); spoof.move(falseWanted, 5)
	falseWanted:SetAttribute("Wanted", true)
	spoof.equip(spoof.player, "Spray"); spoof.hit(falseWanted)
	spoof.service.spray(spoof.player, {direction=spoof.m.Vector3.new(1,0,0)})
	check("wanted attribute alone does not authorize stun", falseWanted.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 16)

	local train = fixture()
	train.service.join(train.player); train.service.requestGear(train.player)
	train.move(train.player, 60)
	check("officer can start target training nearby", train.service.startTraining(train.player))
	check("training state replicated", train.lastState(train.player).training == true)
	local targetModel
	for _, item in ipairs(train.m.Workspace:GetChildren()) do if item:GetAttribute("PoliceTrainingOwner") == train.player.UserId then targetModel = item end end
	check("server creates officer-owned training target", targetModel ~= nil)
	train.equip(train.player, "Cuff")
	check("training capture requires prior stun", not train.service.capture(train.player, "Training"))
	train.equip(train.player, "Spray"); train.hitModel(targetModel)
	check("training target accepts water hit", train.service.spray(train.player, {direction=train.m.Vector3.new(1,0,0)}))
	train.advance(0.6); train.equip(train.player, "Cuff")
	check("stunned close training target can be cuffed", train.service.capture(train.player, "Training"))
	check("training target removed after completion", targetModel.Parent == nil and train.lastState(train.player).training == false)
	check("training pays no invented reward", train.player:GetAttribute("Money") == 781)
	train.advance(0.6)
	check("training completion cannot be repeated", not train.service.capture(train.player, "Training"))

	local failed = fixture(true)
	check("failed preparation refuses duty", not failed.service.join(failed.player))
	check("failed preparation releases slot", failed.lastState(failed.player).count == 0 and not failed.player:GetAttribute("PoliceDuty"))
	check("failed preparation emits diagnostic", #failed.warnings == 1)
	print(("PASS PoliceService: %d lifecycle checks (mock services)"):format(checks))
end
