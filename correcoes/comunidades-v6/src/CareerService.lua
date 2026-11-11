-- CareerService (ModuleScript)
-- Caminho: ServerScriptService > Services > CareerService
-- Marco 10.15: economia nova (Revisão 2). Duas coisas:
--   1. SALÁRIO a cada 15 min só por estar no emprego (GameConfig.Career.Salary, por faixa e cargo).
--      Anti-AFK: precisa ter feito 1 tarefa nos últimos 15 min OU ter andado nos últimos 5 min.
--      Quem não fez nada recebe metade; na 2ª vez seguida, nada. Preso não recebe.
--   2. CARGO em cada profissão pelo número de tarefas feitas (salvo em data.career; trocar de
--      emprego não perde). Cada promoção dá +10% no valor das tarefas.
-- Todo pagamento de tarefa passa por CareerService.taskPay (MissionService, CrimeService, Downed...).
-- Atributos no jogador: Cargo (nome do cargo no emprego de agora), SalarioEm (horário do servidor
-- do próximo salário).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local CareerService = {}

local C = GameConfig.Career
local uiUpdate

-- [player] = { job, nextPay, lastTask, lastMove, lastPos, strikes }
local live = {}

local function money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return GameConfig.Economy.CurrencySymbol .. out
end

local function careerOf(player)
	local data = PlayerDataService.get(player)
	if not data then
		return nil
	end
	if type(data.career) ~= "table" then
		data.career = {}
	end
	return data.career
end

function CareerService.tasks(player, job)
	local career = careerOf(player)
	return career and tonumber(career[job]) or 0
end

function CareerService.rank(player, job)
	local n = CareerService.tasks(player, job)
	local r = 1
	for i, info in ipairs(C.Ranks) do
		if n >= info.Tasks then
			r = i
		end
	end
	return r
end

function CareerService.rankName(job, r)
	if r == #C.Ranks and C.TopTitle[job] then
		return C.TopTitle[job]
	end
	return C.Ranks[r].Name
end

local function publish(player)
	local job = player:GetAttribute("Job")
	if job and C.Tier[job] then
		local r = CareerService.rank(player, job)
		player:SetAttribute("Cargo", CareerService.rankName(job, r))
		local nextInfo = C.Ranks[r + 1]
		player:SetAttribute("CargoProximo", nextInfo and (nextInfo.Tasks - CareerService.tasks(player, job)) or nil)
	else
		player:SetAttribute("Cargo", nil)
		player:SetAttribute("CargoProximo", nil)
	end
end

local function notice(player, text)
	if uiUpdate and player.Parent then
		uiUpdate:FireClient(player, "Notice", { text = text })
	end
end

-- Conta tarefas feitas (e avisa promoção)
function CareerService.addTasks(player, job, count)
	local career = careerOf(player)
	if not career or not C.Tier[job] then
		return
	end
	local before = CareerService.rank(player, job)
	career[job] = (tonumber(career[job]) or 0) + (count or 1)
	PlayerDataService.set(player, "career", career)
	local after = CareerService.rank(player, job)
	local st = live[player]
	if st then
		st.lastTask = os.clock()
		st.strikes = 0
	end
	if after > before then
		notice(player, ("🎉 Promoção! Agora você é %s (%s): salário maior e +%d%% nas tarefas."):format(CareerService.rankName(job, after), tostring(job), math.floor((after - 1) * C.RankBonus * 100 + 0.5)))
	end
	publish(player)
end

-- Paga uma tarefa: valor base + bônus do cargo. Conta como tarefa feita. Devolve o valor pago.
function CareerService.taskPay(player, job, base, reason, tasks)
	base = math.floor(tonumber(base) or 0)
	if base <= 0 then
		return 0
	end
	local mult = 1
	if job and C.Tier[job] then
		mult = 1 + (CareerService.rank(player, job) - 1) * C.RankBonus
	end
	local amount = math.floor(base * mult + 0.5)
	if not EconomyService.add(player, amount, reason or "tarefa") then
		return 0
	end
	if job and C.Tier[job] then
		CareerService.addTasks(player, job, tasks or 1)
	end
	return amount
end

-- Multiplicador do cargo (para mostrar valores na tela)
function CareerService.multiplier(player, job)
	if not job or not C.Tier[job] then
		return 1
	end
	return 1 + (CareerService.rank(player, job) - 1) * C.RankBonus
end

local function onJob(player)
	local job = player:GetAttribute("Job")
	local st = live[player]
	if not st then
		return
	end
	if job ~= st.job then
		st.job = job
		st.strikes = 0
		st.lastTask = os.clock()
		if job and C.Tier[job] then
			st.nextPay = os.clock() + C.Interval
			player:SetAttribute("SalarioEm", Workspace:GetServerTimeNow() + C.Interval)
		else
			st.nextPay = nil
			player:SetAttribute("SalarioEm", nil)
		end
	end
	publish(player)
end

local function paySalary(player, st)
	local job = st.job
	local tier = job and C.Tier[job]
	st.nextPay = os.clock() + C.Interval
	player:SetAttribute("SalarioEm", Workspace:GetServerTimeNow() + C.Interval)
	if not tier then
		return
	end
	if player:GetAttribute("Preso") then
		notice(player, "💼 Preso não recebe salário.")
		return
	end
	local now = os.clock()
	local active = (now - (st.lastTask or 0)) <= C.Interval or (now - (st.lastMove or 0)) <= C.ActiveWindow
	local r = CareerService.rank(player, job)
	local amount = C.Salary[tier][r] or C.Salary[tier][1]
	if not active then
		st.strikes += 1
		amount = st.strikes == 1 and math.floor(amount / 2) or 0
	else
		st.strikes = 0
	end
	if amount <= 0 then
		notice(player, "💼 Sem salário: você ficou parado sem trabalhar.")
		return
	end
	if EconomyService.add(player, amount, "Salário: " .. tostring(job)) then
		if uiUpdate then
			uiUpdate:FireClient(player, "CrimePaid", {
				amount = amount,
				text = ("💼 Salário (%s): +%s%s"):format(CareerService.rankName(job, r), money(amount), active and "" or " (metade: parado)"),
			})
		end
	end
end

local function track(player)
	live[player] = { strikes = 0, lastTask = os.clock(), lastMove = os.clock() }
	player:GetAttributeChangedSignal("Job"):Connect(function()
		onJob(player)
	end)
	onJob(player)
end

function CareerService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	PlayerDataService.onLoaded(function(player)
		if player.Parent and not live[player] then
			track(player)
		end
		publish(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		live[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for player, st in pairs(live) do
				if player.Parent then
					-- andou? (anti-AFK)
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root then
						local p = root.Position
						local moved = st.lastPos and (p - st.lastPos).Magnitude or 0
						if moved > 4 then
							st.lastMove = now
						end
						-- patrulha do policial: andou pela cidade no último minuto = +PatrolPay
						if st.job == "Policial" and moved < 400 then -- (teleporte não conta)
							st.patrol = (st.patrol or 0) + moved
						end
						st.lastPos = p
					end
					if st.job == "Policial" then
						st.patrolAt = st.patrolAt or now
						if now - st.patrolAt >= 60 then
							if (st.patrol or 0) >= C.PatrolDistance and not player:GetAttribute("Preso") then
								CareerService.taskPay(player, "Policial", C.PatrolPay, "Patrulha", 0)
							end
							st.patrol = 0
							st.patrolAt = now
						end
					else
						st.patrol, st.patrolAt = nil, nil
					end
					if st.nextPay and now >= st.nextPay then
						task.spawn(paySalary, player, st)
					end
				end
			end
		end
	end)
end

return CareerService
