-- RouteGraph (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > RouteGraph
-- Marco 9.9: GPS. As ruas da cidade viram um grafo (rotatória, 8 ruas, anel do meio, anel externo e
-- as avenidas que saem dele: Vila, parque, prisão, pintura, terminal, bombeiros) e, no Marco 10,
-- as estradas da expansão (CityRoads: rodovia, Rodoanel, bairro Horizonte...), igual ao
-- MapBuilder. RouteGraph.route(de, para) devolve a lista de pontos (no chão) pelo caminho mais
-- curto pelas ruas: de -> rua mais perto -> ... -> rua mais perto do destino -> destino.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local CityRoads = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CityRoads"))

local RouteGraph = {}

local M = GameConfig.Map
local RADIAL_END = 50 + M.RoadLength
local ROUND_R = (M.RoundaboutOuterRadius + M.RoundaboutIslandRadius) / 2 -- meio da pista da rotatória
local ARC_STEPS = 4 -- cada oitavo da rotatória vira 4 retas (a linha acompanha a curva)

local nodes = {} -- nodes[i] = Vector3 (Y = 0)
local edges = {} -- { a, b } (índices de nodes)
local adj = {} -- adj[i] = { { j, custo } }

local function addNode(p)
	table.insert(nodes, Vector3.new(p.X, 0, p.Z))
	adj[#nodes] = {}
	return #nodes
end

local function link(a, b)
	local cost = (nodes[a] - nodes[b]).Magnitude
	table.insert(edges, { a, b })
	table.insert(adj[a], { b, cost })
	table.insert(adj[b], { a, cost })
end

local function build()
	local dirs = {}
	for i = 0, 7 do
		table.insert(dirs, CFrame.Angles(0, i * math.pi / 4, 0).LookVector)
	end
	local R, I, O = {}, {}, {}
	for i, dir in ipairs(dirs) do
		R[i] = addNode(dir * ROUND_R)
		I[i] = addNode(dir * M.InnerRingRadius)
		O[i] = addNode(dir * RADIAL_END)
	end
	for i = 1, 8 do
		local j = i % 8 + 1
		-- rotatória: arco entre duas ruas
		local prev = R[i]
		for s = 1, ARC_STEPS - 1 do
			local angle = (i - 1 + s / ARC_STEPS) * math.pi / 4
			local mid = addNode(CFrame.Angles(0, angle, 0).LookVector * ROUND_R)
			link(prev, mid)
			prev = mid
		end
		link(prev, R[j])
		link(R[i], I[i]) -- rua: rotatória -> anel do meio -> anel externo
		link(I[i], O[i])
		link(I[i], I[j]) -- anéis
		link(O[i], O[j])
	end
	local extras = { { Dir = M.Vila.Dir, RoadLength = M.Vila.Length } }
	for _, cfg in ipairs({ GameConfig.Park, GameConfig.Prison, GameConfig.PaintShop, GameConfig.BusTerminal, GameConfig.FireStation }) do
		if cfg and cfg.Dir and cfg.RoadLength then
			table.insert(extras, cfg)
		end
	end
	for _, cfg in ipairs(extras) do
		local dir = dirs[cfg.Dir]
		link(O[cfg.Dir], addNode(dir * (RADIAL_END + cfg.RoadLength)))
	end

	-- Marco 10: estradas da expansão. Cada estrada vira uma fila de nós (curvas e cruzamentos);
	-- nós no mesmo lugar são o mesmo nó (assim as estradas se ligam entre si e na cidade).
	local byKey = {}
	local function keyOf(p)
		return ("%d,%d"):format(math.floor(p.X + 0.5), math.floor(p.Z + 0.5))
	end
	for i = 1, #nodes do
		byKey[keyOf(nodes[i])] = i
	end
	local function nodeAt(p)
		local k = keyOf(p)
		if not byKey[k] then
			byKey[k] = addNode(p)
		end
		return byKey[k]
	end
	local data, splits = CityRoads.get(), CityRoads.splits()
	for i, r in ipairs(data.roads) do
		local segs, total = CityRoads.segments(r)
		local marks = {}
		for _, s in ipairs(segs) do
			table.insert(marks, { t = s.t0, pos = s.a })
		end
		table.insert(marks, { t = total, pos = r.Points[#r.Points] })
		for _, s in ipairs(splits[i]) do
			table.insert(marks, { t = s.t, pos = s.pos })
		end
		table.sort(marks, function(a, b)
			return a.t < b.t
		end)
		local prev
		for _, mk in ipairs(marks) do
			local n = nodeAt(mk.pos)
			if prev and prev ~= n then
				link(prev, n)
			end
			prev = n
		end
	end
end

-- Ponto mais perto de p em alguma rua: devolve (ponto, aresta)
local function nearest(p)
	local best, bestD, bestE = nil, math.huge, nil
	local flat = Vector3.new(p.X, 0, p.Z)
	for ei, e in ipairs(edges) do
		local a, b = nodes[e[1]], nodes[e[2]]
		local ab = b - a
		local t = math.clamp((flat - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
		local q = a + ab * t
		local d = (flat - q).Magnitude
		if d < bestD then
			best, bestD, bestE = q, d, ei
		end
	end
	return best, bestE
end

-- Dijkstra simples (o grafo tem ~70 nós)
local function shortest(starts, goals)
	local dist, prev, done = {}, {}, {}
	for node, cost in pairs(starts) do
		dist[node] = cost
	end
	while true do
		local u, ud = nil, math.huge
		for node, d in pairs(dist) do
			if not done[node] and d < ud then
				u, ud = node, d
			end
		end
		if not u then
			return nil
		end
		done[u] = true
		if goals[u] then
			local path = { u }
			while prev[path[1]] do
				table.insert(path, 1, prev[path[1]])
			end
			return path, ud + goals[u]
		end
		for _, nb in ipairs(adj[u] or {}) do
			local v, c = nb[1], nb[2]
			if not done[v] and ud + c < (dist[v] or math.huge) then
				dist[v] = ud + c
				prev[v] = u
			end
		end
	end
end

function RouteGraph.route(from, to)
	if #nodes == 0 then
		build()
	end
	local fromFlat = Vector3.new(from.X, 0, from.Z)
	local toFlat = Vector3.new(to.X, 0, to.Z)
	local qa, ea = nearest(fromFlat)
	local qb, eb = nearest(toFlat)
	if not qa or not qb then
		return { fromFlat, toFlat }
	end
	local points = { fromFlat, qa }
	if ea == eb then
		-- mesma rua: vai direto por ela
		table.insert(points, qb)
	else
		local A, B = edges[ea], edges[eb]
		local starts = { [A[1]] = (qa - nodes[A[1]]).Magnitude, [A[2]] = (qa - nodes[A[2]]).Magnitude }
		local goals = { [B[1]] = (qb - nodes[B[1]]).Magnitude, [B[2]] = (qb - nodes[B[2]]).Magnitude }
		local path = shortest(starts, goals)
		for _, node in ipairs(path or {}) do
			table.insert(points, nodes[node])
		end
		table.insert(points, qb)
	end
	table.insert(points, toFlat)
	-- tira pontos repetidos (começo ou fim já em cima de um cruzamento)
	local clean = {}
	for _, p in ipairs(points) do
		if #clean == 0 or (clean[#clean] - p).Magnitude > 0.5 then
			table.insert(clean, p)
		end
	end
	return clean
end

return RouteGraph
