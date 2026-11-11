-- HeistEvents (ModuleScript)
-- Caminho: ServerScriptService > Services > HeistEvents
-- Marco 10.20: motor de EVENTOS dos assaltos (banco e joalheria). Cada evento é uma tabela:
--   { Id, Name, Icon, Text, Phases = { fase = true }, Duration (s, opcional), Solo (vale para 1
--     jogador), Requires(ctx) -> bool, Start(ctx, ev), Step(ctx, ev, dt) -> true = acabou,
--     Stop(ctx, ev, reason), Hint(ctx, ev) -> texto curto do painel }
-- O motor confere tudo antes de começar: fase certa, sorteio (Chance), espera entre um e outro no
-- servidor (Cooldown), máximo ao mesmo tempo (MaxEvents), uma vez por assalto e a condição
-- (Requires). Erro dentro de um evento não derruba o assalto: o evento é encerrado (Stop) e pronto.
-- Novo evento = nova tabela na lista do serviço + Chance/Cooldown no GameConfig.

local HeistEvents = {}
HeistEvents.__index = HeistEvents

local rng = Random.new()
local lastRun = {} -- [escopo .. id] = os.clock() da última vez (vale para o servidor todo)

-- scope = "Banco" | "Joia"; defs = lista de eventos; cfg = GameConfig.X.Events; ctx = funções do serviço
-- (ctx.announce(ev) e ctx.ended(ev, reason) são chamados pelo motor)
function HeistEvents.new(scope, defs, cfg, ctx, maxEvents)
	local self = setmetatable({}, HeistEvents)
	self.scope = scope
	self.defs = defs
	self.cfg = cfg or {}
	self.ctx = ctx
	self.max = maxEvents or 2
	self.active = {}
	self.done = {}
	self.forceAll = false
	return self
end

function HeistEvents:count()
	local n = 0
	for _ in pairs(self.active) do
		n += 1
	end
	return n
end

function HeistEvents:isActive(id)
	return self.active[id]
end

function HeistEvents:canRun(def)
	local c = self.cfg[def.Id] or {}
	local chance = c.Chance or def.Chance or 0
	if chance <= 0 or self.done[def.Id] or self.active[def.Id] then
		return false
	end
	local last = lastRun[self.scope .. def.Id]
	if last and not self.forceAll and os.clock() - last < (c.Cooldown or def.Cooldown or 600) then
		return false
	end
	if def.Requires then
		local ok, result = pcall(def.Requires, self.ctx)
		if not ok or not result then
			return false
		end
	end
	return true, chance
end

function HeistEvents:start(def)
	local now = os.clock()
	local c = self.cfg[def.Id] or {}
	local duration = c.Duration or def.Duration
	local ev = { def = def, id = def.Id, started = now, endsAt = duration and now + duration or nil, data = {} }
	self.active[def.Id] = ev
	self.done[def.Id] = true
	lastRun[self.scope .. def.Id] = now
	local ok, err = pcall(def.Start, self.ctx, ev)
	if not ok then
		warn(("[HeistEvents] %s/%s não começou: %s"):format(self.scope, def.Id, tostring(err)))
		self.active[def.Id] = nil
		if def.Stop then
			pcall(def.Stop, self.ctx, ev, "erro")
		end
		return nil
	end
	if self.ctx.announce then
		pcall(self.ctx.announce, ev)
	end
	print(("[HeistEvents] %s: evento %s começou."):format(self.scope, def.Id))
	return ev
end

-- Sorteia os eventos de uma fase. force = id de um evento que começa sem sorteio (testes).
function HeistEvents:roll(phase, force)
	local list = {}
	for _, def in ipairs(self.defs) do
		if def.Phases and def.Phases[phase] then
			table.insert(list, def)
		end
	end
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	for _, def in ipairs(list) do
		if self:count() >= self.max then
			break
		end
		local ok, chance = self:canRun(def)
		if ok and (self.forceAll or force == def.Id or rng:NextNumber() < chance) then
			self:start(def)
		end
	end
end

function HeistEvents:stop(id, reason)
	local ev = self.active[id]
	if not ev then
		return
	end
	self.active[id] = nil
	if ev.def.Stop then
		local ok, err = pcall(ev.def.Stop, self.ctx, ev, reason)
		if not ok then
			warn(("[HeistEvents] %s/%s Stop: %s"):format(self.scope, id, tostring(err)))
		end
	end
	if self.ctx.ended then
		pcall(self.ctx.ended, ev, reason)
	end
end

function HeistEvents:step(dt)
	local now = os.clock()
	for id, ev in pairs(self.active) do
		local finished = ev.finished or (ev.endsAt ~= nil and now >= ev.endsAt)
		if not finished and ev.def.Step then
			local ok, result = pcall(ev.def.Step, self.ctx, ev, dt)
			if not ok then
				warn(("[HeistEvents] %s/%s: %s"):format(self.scope, id, tostring(result)))
				finished = true
			elseif result == true then
				finished = true
			end
		end
		if finished then
			self:stop(id, ev.finished and "concluido" or "tempo")
		end
	end
end

-- Novo assalto: encerra tudo (menos os ids em keep) e libera os eventos de novo
function HeistEvents:reset(keep)
	for id in pairs(self.active) do
		if not (keep and keep[id]) then
			self:stop(id, "reset")
		end
	end
	self.done = {}
	for id in pairs(self.active) do
		self.done[id] = true
	end
end

-- Lista curta para o painel do cliente
function HeistEvents:list()
	local out = {}
	local now = os.clock()
	for id, ev in pairs(self.active) do
		local hint = ev.def.Text
		if ev.def.Hint then
			local ok, h = pcall(ev.def.Hint, self.ctx, ev)
			if ok and h then
				hint = h
			end
		end
		table.insert(out, {
			id = id,
			name = ev.def.Name,
			icon = ev.def.Icon,
			hint = hint,
			left = ev.endsAt and math.max(0, ev.endsAt - now) or nil,
		})
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

return HeistEvents
