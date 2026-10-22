-- Executes the actual PrisonService with controlled time/events and fake Roblox
-- objects. These checks cover server decisions, not Studio replication/physics.
return function(mockSource, rulesSource, serviceSource)
	local checks = 0
	local function check(name, value)
		checks += 1
		assert(value, name)
	end
	local function fixture(studio, failPreparation, cellCount)
		local makeMock = assert(loadstring(mockSource, "@roblox_geometry_mock"))
		local m = makeMock()
		local warnings = {}
		m.env.warn = function(message) table.insert(warnings, message) end
		local time = 1000
		local queue = {}
		local function schedule(delay, fn, ...)
			table.insert(queue, { at = time + delay, thread = coroutine.create(fn), arguments = { ... } })
		end
		local function advance(duration)
			local target = time + duration
			local iterations = 0
			while true do
				local selected, earliest
				for index, item in ipairs(queue) do
					if item.at <= target and (not earliest or item.at < earliest) then
						selected, earliest = index, item.at
					end
				end
				if not selected then break end
				time = earliest
				local item = table.remove(queue, selected)
				local ok, delay = coroutine.resume(item.thread, table.unpack(item.arguments))
				assert(ok, delay)
				if coroutine.status(item.thread) ~= "dead" then
					table.insert(queue, { at = time + (delay or 0), thread = item.thread, arguments = {} })
				end
				iterations += 1
				assert(iterations < 20000, "scheduler stalled")
			end
			time = target
		end
		local function signal()
			local connections = {}
			return {
				Connect = function(_, callback)
					table.insert(connections, callback)
					return { Disconnect = function() end }
				end,
				Fire = function(_, ...)
					for _, callback in ipairs(connections) do callback(...) end
				end,
			}
		end
		local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), list = {} }
		function Players:GetPlayers() return self.list end
		m.services.Players = Players
		m.services.RunService = { IsStudio = function() return studio end }
		m.Workspace.GetServerTimeNow = function() return time end
		m.env.task = {
			spawn = function(fn, ...) schedule(0, fn, ...) end,
			defer = function(fn, ...) schedule(0, fn, ...) end,
			delay = function(delay, fn, ...) schedule(delay, fn, ...) end,
			wait = function(delay) return coroutine.yield(delay or 0) end,
		}
		local v, cf = m.Vector3, m.CFrame
		local function character()
			local humanoid = { Name = "Humanoid", Health = 100, WalkSpeed = 24, Sit = false }
			local root = { Name = "HumanoidRootPart", Position = v.new(0, 4, 0), CFrame = cf.new(0, 4, 0) }
			local char = { Humanoid = humanoid, HumanoidRootPart = root }
			function char:FindFirstChild(name) return self[name] end
			function char:FindFirstChildOfClass(name) return self[name] end
			function char:WaitForChild(name) return self[name] end
			function char:PivotTo(frame) root.Position = frame.Position; root.CFrame = frame end
			return char
		end
		local function makePlayer(id)
			local attributes = { Money = 781 }
			local p = { Parent = Players, Name = "TestPlayer" .. id, UserId = id, Character = character(), CharacterAdded = signal() }
			function p:GetAttribute(name) return attributes[name] end
			function p:SetAttribute(name, value) attributes[name] = value end
			return p, attributes
		end
		local player, attributes = makePlayer(1)
		Players.list = { player }
		local rateAt = {}
		m.load("SecurityService", "return {}", true)
		m.registry.SecurityService = {
			getLivingCharacter = function(p)
				local c = p.Character
				if not c or c.Humanoid.Health <= 0 then return nil end
				return c, c.Humanoid, c.HumanoidRootPart
			end,
			checkRate = function(p, name, interval)
				name = tostring(p.UserId) .. name
				if rateAt[name] and time - rateAt[name] < interval then return false end
				rateAt[name] = time
				return true
			end,
		}
		m.load("GameConfig", "return {WalkSpeed=16, Remotes={UIUpdate='UIUpdate'}}")
		m.load("CivicConfig", "return {SentenceSeconds=60, CellLockSeconds=15}")
		m.load("PrisonRules", rulesSource)
		local dressed, outfitCalls = {}, 0
		m.load("PrisonOutfitService", "return {}", true)
		m.registry.PrisonOutfitService = {
			apply = function(p) dressed[p] = true; outfitCalls += 1; return true end,
			restore = function(p) dressed[p] = nil end,
		}
		local service = m.load("PrisonService", serviceSource, true)
		local messages = {}
		local update = { FireClient = function(_, p, kind, data)
			assert(p.Parent == Players)
			table.insert(messages, { player = p, kind = kind, data = data })
		end }
		local function part(x, z)
			local p = m.Instance.new("Part"); p.CFrame = cf.new(x, 4, z); return p
		end
		local function prompt(x, z)
			local p = m.Instance.new("ProximityPrompt")
			p.Parent = part(x, z); p.Triggered = signal(); p.ObjectText = "Checkpoint"; p.Enabled = false; return p
		end
		local sites = {
			prisonSpawn = part(0, 0), prisonRelease = part(120, 0),
			intakePrompt = prompt(120, 0), escapeSteps = { prompt(16, 0), prompt(32, 0), prompt(48, 0) },
			prisonBounds = { cf = cf.new(0, 4, 0), half = v.new(100, 30, 100) },
		}
		if cellCount then
			sites.prisonBounds.half = v.new(200, 30, 200)
			sites.prisonCells = {}
			for index = 1, cellCount do
				local spawn = part(0, index * 8)
				local door = part(6, index * 8)
				door.Parent = m.Workspace
				table.insert(sites.prisonCells, {
					id = ("%02d"):format(index), spawn = spawn, door = door,
					closed = door.CFrame, open = cf.new(12, 4, index * 8),
					bounds = { cf = spawn.CFrame, half = v.new(5, 8, 3) },
				})
			end
		end
		local prepared, releases, returned = 0, {}, 0
		service.init({ UIUpdate = update }, sites, { beforeDetain = function()
			prepared += 1
			if failPreparation then error("expected test failure") end
		end, afterRelease = function(p, escaped, reason)
			table.insert(releases, { player = p, escaped = escaped, reason = reason, dressed = dressed[p] })
		end, afterReturnToCell = function() returned += 1 end })
		advance(0)
		return {
			service = service, sites = sites, player = player, advance = advance,
			messages = messages, attributes = attributes, Players = Players, warnings = warnings,
			prepared = function() return prepared end,
			dressed = dressed, releases = releases, outfitCalls = function() return outfitCalls end,
			returned = function() return returned end,
			move = function(x, z) player.Character.HumanoidRootPart.Position = v.new(x, 4, z or 0) end,
			addPlayer = function(id)
				local p = makePlayer(id)
				table.insert(Players.list, p)
				Players.PlayerAdded:Fire(p)
				return p
			end,
			respawn = function()
				player.Character = character()
				player.CharacterAdded:Fire(player.Character)
				advance(0)
			end,
		}
	end

	local f = fixture(true)
	check("Studio intake available", f.sites.intakePrompt.Enabled)
	for index, prompt in ipairs(f.sites.escapeSteps) do
		check("escape interaction enabled " .. index, prompt.Enabled == true)
	end
	check("detention succeeds", f.service.detain(f.player, "test"))
	check("detention invokes integrations once", f.prepared() == 1)
	check("detention dresses prisoner automatically", f.dressed[f.player] and f.outfitCalls() == 1)
	check("detained state set", f.service.isDetained(f.player) and f.player:GetAttribute("Detained"))
	check("60 second deadline recorded", f.player:GetAttribute("PrisonEndsAt") == 1060)
	check("walk speed controlled in prison", f.player.Character.Humanoid.WalkSpeed == 16)
	check("duplicate detention rejected", not f.service.detain(f.player, "again"))
	f.advance(25)
	f.respawn()
	check("reset preserves detention", f.service.isDetained(f.player))
	check("reset preserves deadline", f.player:GetAttribute("PrisonEndsAt") == 1060)
	check("reset reapplies custody outfit", f.dressed[f.player] and f.outfitCalls() == 2)
	f.advance(34.9)
	check("cannot leave before 60 seconds", f.service.isDetained(f.player))
	f.advance(0.4)
	check("timer releases player", not f.service.isDetained(f.player))
	check("release restores clothing before callback", not f.dressed[f.player] and #f.releases == 1 and not f.releases[1].dressed)
	check("release callback includes original reason", f.releases[1].reason == "test" and not f.releases[1].escaped)
	check("release removes HUD state", f.player:GetAttribute("Detained") == false and f.player:GetAttribute("PrisonEndsAt") == nil)
	check("timer moves player outside", f.player.Character.HumanoidRootPart.Position.X == 120)
	check("prior speed restored", f.player.Character.Humanoid.WalkSpeed == 24)
	check("duplicate release rejected", not f.service.release(f.player, true))
	check("prison never changes money", f.player:GetAttribute("Money") == 781)
	local released = 0
	for _, event in ipairs(f.messages) do
		if event.kind == "PrisonState" and event.data.active == false then released += 1 end
	end
	check("release announced once", released == 1)

	local escape = fixture(true)
	escape.service.detain(escape.player, "test")
	escape.move(48)
	escape.sites.escapeSteps[3].Triggered:Fire(escape.player)
	check("cannot skip to exit", escape.service.isDetained(escape.player) and escape.player:GetAttribute("PrisonStep") == 0)
	-- New fixture avoids carrying a rejected teleported sample into normal route.
	escape = fixture(true)
	escape.service.detain(escape.player, "test")
	for index = 1, 3 do
		for _ = 1, 4 do
			local root = escape.player.Character.HumanoidRootPart
			escape.move(root.Position.X + 4)
			escape.advance(0.3)
		end
		escape.sites.escapeSteps[index].Triggered:Fire(escape.player)
	end
	check("linear escape route releases early", not escape.service.isDetained(escape.player))
	check("escape keeps player at exit", escape.player.Character.HumanoidRootPart.Position.X == 48)
	check("escape preserves money", escape.player:GetAttribute("Money") == 781)
	check("escape clears deadline", escape.player:GetAttribute("PrisonEndsAt") == nil)
	check("repeated escape cannot release twice", not escape.service.release(escape.player, true))

	local instant = fixture(true)
	instant.service.detain(instant.player, "test")
	instant.advance(2)
	instant.move(16)
	instant.sites.escapeSteps[1].Triggered:Fire(instant.player)
	check("same-frame teleport checkpoint rejected", instant.player:GetAttribute("PrisonStep") == 0)
	check("same-frame teleport returns inmate", instant.player.Character.HumanoidRootPart.Position.X == 0)

	local teleport = fixture(true)
	teleport.service.detain(teleport.player, "test")
	teleport.move(90)
	teleport.advance(0.3)
	check("teleport returns inmate to cell", teleport.player.Character.HumanoidRootPart.Position.X == 0)
	check("teleport does not reset sentence", teleport.player:GetAttribute("PrisonEndsAt") == 1060)
	teleport.move(120)
	teleport.advance(0.3)
	check("out of bounds returns inmate", teleport.player.Character.HumanoidRootPart.Position.X == 0)

	local production = fixture(false)
	check("intake unavailable outside Studio", production.sites.intakePrompt.Enabled == false)
	production.move(120)
	production.sites.intakePrompt.Triggered:Fire(production.player)
	check("forged production intake ignored", not production.service.isDetained(production.player))
	local intake = fixture(true)
	intake.sites.intakePrompt.Triggered:Fire(intake.player)
	check("distant Studio intake ignored", not intake.service.isDetained(intake.player))
	intake.advance(1.1)
	intake.move(120)
	intake.sites.intakePrompt.Triggered:Fire(intake.player)
	check("nearby Studio intake detains self", intake.service.isDetained(intake.player))
	intake.Players.PlayerRemoving:Fire(intake.player)
	check("disconnect clears session", not intake.service.isDetained(intake.player))

	local failed = fixture(true, true)
	check("failed integration aborts detention", not failed.service.detain(failed.player, "test"))
	check("failed detention clears attributes", failed.player:GetAttribute("Detained") == false)
	check("failed detention leaves no session", not failed.service.isDetained(failed.player))
	check("failed integration reports diagnostic", #failed.warnings == 1)

	-- New sealed-cell lifecycle: one occupant per cell, lock schedule never restarts.
	local cells = fixture(true, false, 16)
	check("cell detention succeeds", cells.service.detain(cells.player, "test"))
	check("cell identifier replicated", cells.player:GetAttribute("PrisonCell") == "01")
	check("assigned cell API is authoritative", cells.service.getAssignedCellId(cells.player) == "01")
	check("cell unlock deadline replicated", cells.player:GetAttribute("PrisonCellOpensAt") == 1015)
	check("assigned inmate moved inside own cell", cells.player.Character.HumanoidRootPart.Position.Z == 8)
	check("cell gate initially closed", cells.sites.prisonCells[1].door.CFrame.Position.X == 6)
	cells.advance(5)
	cells.move(4, 8)
	cells.sites.escapeSteps[1].Triggered:Fire(cells.player)
	check("locked inmate cannot advance escape", cells.player:GetAttribute("PrisonStep") == 0)
	cells.respawn()
	check("cell reset preserves original lock deadline", cells.player:GetAttribute("PrisonCellOpensAt") == 1015)
	check("cell reset preserves original sentence deadline", cells.player:GetAttribute("PrisonEndsAt") == 1060)
	cells.advance(9.9)
	check("gate stays closed before 15 seconds", cells.sites.prisonCells[1].door.CFrame.Position.X == 6)
	cells.advance(0.4)
	check("gate opens after initial lock", cells.sites.prisonCells[1].door.CFrame.Position.X == 12)
	cells.respawn()
	check("reset after unlock leaves gate open", cells.sites.prisonCells[1].door.CFrame.Position.X == 12)
	check("reset keeps assigned cell", cells.player:GetAttribute("PrisonCell") == "01")
	check("manual release frees cell", cells.service.release(cells.player, false))
	check("release clears cell attributes", cells.player:GetAttribute("PrisonCell") == nil and cells.player:GetAttribute("PrisonCellOpensAt") == nil)
	check("release clears assigned cell API", cells.service.getAssignedCellId(cells.player) == nil)
	cells.advance(0.3)
	check("empty cell gate closes again", cells.sites.prisonCells[1].door.CFrame.Position.X == 6)

	local concurrent = fixture(true, false, 16)
	local inmates = { concurrent.player }
	for index = 2, 17 do table.insert(inmates, concurrent.addPlayer(index)) end
	for index = 1, 16 do
		check("unique cell admission " .. index, concurrent.service.detain(inmates[index], "test"))
		check("unique cell allocation " .. index, inmates[index]:GetAttribute("PrisonCell") == ("%02d"):format(index))
	end
	check("capacity overflow refuses admission", not concurrent.service.detain(inmates[17], "test"))
	check("capacity refusal leaves civilian free", not concurrent.service.isDetained(inmates[17]) and not inmates[17]:GetAttribute("Detained"))
	check("freeing one cell succeeds", concurrent.service.release(inmates[3], false))
	concurrent.advance(0.3)
	check("new inmate can use freed cell", concurrent.service.detain(inmates[17], "test"))
	check("reused cell gets its own full lock", inmates[17]:GetAttribute("PrisonCell") == "03" and inmates[17]:GetAttribute("PrisonCellOpensAt") > 1015)
	check("other inmate timer unaffected", inmates[2]:GetAttribute("PrisonEndsAt") == 1060)
	concurrent.Players.PlayerRemoving:Fire(inmates[2])
	check("disconnect releases cell session", not concurrent.service.isDetained(inmates[2]))


	local confined = fixture(true, false, 1)
	confined.service.detain(confined.player, "test")
	confined.move(0, 30)
	confined.advance(0.3)
	check("locked inmate returned from outside own cell", confined.player.Character.HumanoidRootPart.Position.Z == 8)
	check("cell boundary recovery preserves release deadline", confined.player:GetAttribute("PrisonEndsAt") == 1060)
	check("cell boundary recovery preserves unlock deadline", confined.player:GetAttribute("PrisonCellOpensAt") == 1015)

	local doorway = fixture(true, false, 1)
	doorway.service.detain(doorway.player, "test")
	doorway.advance(15.3)
	doorway.move(6, 8)
	check("release near cell doorway succeeds", doorway.service.release(doorway.player, true))
	check("escape restores civil outfit and reports escape", not doorway.dressed[doorway.player] and doorway.releases[1].escaped)
	doorway.advance(0.6)
	check("empty cell does not close onto living character", doorway.sites.prisonCells[1].door.CFrame.Position.X == 12)
	local waiting = doorway.addPlayer(2)
	check("blocked doorway is not allocated to another inmate", not doorway.service.detain(waiting, "test"))
	doorway.move(30, 8)
	doorway.advance(0.6)
	check("empty door closes after character clears opening", doorway.sites.prisonCells[1].door.CFrame.Position.X == 6)
	check("cleared cell can then admit new inmate", doorway.service.detain(waiting, "test"))


	local controls = fixture(true, false, 2)
	controls.service.detain(controls.player, "test")
	local view = controls.service.getCellControls()
	check("control panel lists actual cells", #view == 2 and view[1].id == "01")
	check("control panel marks occupied locked cell", view[1].occupied and not view[1].open and view[1].lockedUntil == 1015)
	check("control panel marks free cell", not view[2].occupied and view[2].lockedUntil == 0)
	check("control cannot bypass initial cell lock", not controls.service.setCellDoor("01", true))
	check("unknown cell control refused", not controls.service.setCellDoor("unknown", true))
	check("nonboolean cell command refused", not controls.service.setCellDoor("01", "open"))
	controls.advance(15.01)
	check("manual close accepted after initial lock", controls.service.setCellDoor("01", false))
	controls.advance(0.4)
	check("monitor does not undo manual close", controls.sites.prisonCells[1].door:GetAttribute("Open") == false)
	check("manual control cannot change sentence", controls.player:GetAttribute("PrisonEndsAt") == 1060)
	check("manual cell opening accepted after lock", controls.service.setCellDoor("01", true))
	controls.move(6, 8)
	check("manual close refuses occupied doorway", not controls.service.setCellDoor("01", false))
	controls.move(0, 8)
	controls.advance(44.8)
	check("manual gate controls never prevent release", not controls.service.isDetained(controls.player))


	local stunnedIntake = fixture(true, false, 1)
	stunnedIntake.player.Character.Humanoid.WalkSpeed = 0
	check("stunned suspect can enter prison", stunnedIntake.service.detain(stunnedIntake.player, "police_capture"))
	check("detention normalizes stunned movement", stunnedIntake.player.Character.Humanoid.WalkSpeed == 16)
	stunnedIntake.advance(60.3)
	check("release never restores a zero stunned walking speed", stunnedIntake.player.Character.Humanoid.WalkSpeed == 16)

	local recaptured = fixture(true, false, 1)
	check("free citizen has no assigned cell", recaptured.service.getAssignedCellId(recaptured.player) == nil)
	check("free citizen cannot be returned to cell", not recaptured.service.returnToCell(recaptured.player))
	recaptured.service.detain(recaptured.player, "test")
	recaptured.advance(16)
	recaptured.player:SetAttribute("StunnedUntil", 1020)
	recaptured.move(2, 8)
	recaptured.advance(0.3)
	check("prison tick preserves stun movement", recaptured.player.Character.Humanoid.WalkSpeed == 0)
	check("internal recapture returns assigned inmate", recaptured.service.returnToCell(recaptured.player))
	check("internal recapture keeps same cell and notifies cleanup", recaptured.player.Character.HumanoidRootPart.Position.Z == 8 and recaptured.returned() == 1)
	check("internal recapture preserves original deadlines", recaptured.player:GetAttribute("PrisonEndsAt") == 1060 and recaptured.player:GetAttribute("PrisonCellOpensAt") == 1015)
	check("internal recapture keeps opened cell open", recaptured.sites.prisonCells[1].door:GetAttribute("Open"))
	recaptured.advance(4)
	check("movement returns after stun deadline", recaptured.player.Character.Humanoid.WalkSpeed == 16)
	recaptured.player:SetAttribute("CuffedUntil", 1025)
	recaptured.advance(0.3)
	check("prison tick also respects cuff movement", recaptured.player.Character.Humanoid.WalkSpeed == 0)
	recaptured.service.release(recaptured.player, false)
	check("duplicate release produces no duplicate hook", not recaptured.service.release(recaptured.player, false) and #recaptured.releases == 1)

	print(("PASS PrisonService: %d lifecycle checks (mock services)"):format(checks))
end
