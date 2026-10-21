-- Actual builder execution with geometry doubles; no rendering/physics claim.
return function(mock, GameConfig, Config, CivicBuilder)
 local count = 0
 local function check(ok, message)
  count += 1
  assert(ok, "GEOMETRY: "..message)
 end
 local map = mock.Workspace:WaitForChild("Map")
 local sites = assert(CivicBuilder.sites, "missing civic references")
 local civic = map:WaitForChild("CivicLocations")
 local station = civic:WaitForChild(Config.Station.Name)
 local prison = civic:WaitForChild(Config.Prison.Name)
 check(Config.SentenceSeconds == 60, "sentence must remain 60s")
 check(#map:WaitForChild("JobLocations"):GetChildren() == 4, "all four shops retained")
 check(#sites.escapeSteps == 3, "three ordered escape checkpoints")
 check(not sites.intakePrompt.Enabled, "test intake disabled until service verifies Studio")
 check(station:GetAttribute("Kind") == "Police", "station map kind")
 check(prison:GetAttribute("Kind") == "Prison", "prison map kind")
 check((station:GetAttribute("MapPosition")).Magnitude < 400, "station amid city")
 check((prison:GetAttribute("MapPosition")).Magnitude > 850, "prison outside city")
 local function inBounds(point)
  local p=sites.prisonBounds.cf:PointToObjectSpace(point)
  local half=sites.prisonBounds.half
  return math.abs(p.X)<=half.X and math.abs(p.Y)<=half.Y and math.abs(p.Z)<=half.Z
 end
 check(inBounds(sites.prisonSpawn.Position),"inmate spawn within active bounds")
 check(not inBounds(sites.prisonRelease.Position),"released player starts outside active bounds")
 for i,prompt in ipairs(sites.escapeSteps) do
  check(prompt.ClassName=="ProximityPrompt" and inBounds(prompt.Parent.Position),"checkpoint "..i.." has valid prompt and bounds")
 end
 -- Ensure no civic geometry leaves the enlarged ground plane.
 local civicParts=0
 for _,object in ipairs(civic:GetDescendants()) do
  if object:IsA("BasePart") then
   civicParts+=1
   for _,sx in ipairs({-1,1}) do
    for _,sz in ipairs({-1,1}) do
     local corner=object.CFrame*mock.Vector3.new(sx*object.Size.X/2,0,sz*object.Size.Z/2)
     check(math.abs(corner.X)<=GameConfig.Map.GroundSize/2 and math.abs(corner.Z)<=GameConfig.Map.GroundSize/2,"civic footprint inside ground: "..object.Name)
    end
   end
  end
 end
 -- 2D SAT on oriented boxes; ignore visual leaves/placards and vertical separation.
 local function planarOverlap(a,b)
  local delta=b.Position-a.Position
  if math.abs(delta.Y)>a.Size.Y/2+b.Size.Y/2-0.02 then return false end
  for _,axis in ipairs({a.CFrame.RightVector,a.CFrame.LookVector,b.CFrame.RightVector,b.CFrame.LookVector}) do
   local ra=math.abs(axis:Dot(a.CFrame.RightVector))*a.Size.X/2+math.abs(axis:Dot(a.CFrame.LookVector))*a.Size.Z/2
   local rb=math.abs(axis:Dot(b.CFrame.RightVector))*b.Size.X/2+math.abs(axis:Dot(b.CFrame.LookVector))*b.Size.Z/2
   if math.abs(delta:Dot(axis))>=ra+rb-0.02 then return false end
  end
  return true
 end
 for _,shop in ipairs(map:WaitForChild("JobLocations"):GetChildren()) do
  for _,a in ipairs(station:GetDescendants()) do
   if a:IsA("BasePart") and a.CanCollide then
    for _,b in ipairs(shop:GetDescendants()) do
     if b:IsA("BasePart") and b.CanCollide then
      check(not planarOverlap(a,b),"station overlaps existing shop "..shop.Name..": "..a.Name.."/"..b.Name)
     end
    end
   end
  end
 end
 -- Sample an avatar-sized upright envelope along intended walking corridors.
 -- R15 clearance at root y=4: half width 1, vertical half height 2.5.
 local blockers={}
 for _,p in ipairs(civic:GetDescendants()) do
  if p:IsA("BasePart") and p.CanCollide then table.insert(blockers,p) end
 end
 local function clear(position, stairs)
  for _,p in ipairs(blockers) do
   local q=p.CFrame:PointToObjectSpace(position)
   -- Stair walking permits a normal 0.8-stud step-up under the feet, while
   -- still testing walls, landings above the head and the cabin floor opening.
   local stepSurface = stairs and (p.Name=="Degrau" or p.Name=="Patamar")
    and p.Position.Y+p.Size.Y/2 <= position.Y-2.5+0.8
   if not stepSurface and math.abs(q.X)<p.Size.X/2+0.95 and math.abs(q.Z)<p.Size.Z/2+0.95 and math.abs(q.Y)<p.Size.Y/2+2.5 then
    return false,p.Name
   end
  end
  return true
 end
 local function path(base,points,name,stairs)
  for i=1,#points-1 do
   local a,b=base*points[i],base*points[i+1]
   local samples=math.ceil((b-a).Magnitude*2)
   for n=0,samples do
    local pos=a:Lerp(b,n/samples)
    local ok,blocker=clear(pos,stairs)
    check(ok,name.." walking segment "..i.." blocked by "..tostring(blocker).." near "..tostring(base:PointToObjectSpace(pos)))
   end
  end
 end
 local v=mock.Vector3.new
 path(Config.Station.CFrame,{v(0,4,-34),v(0,4,-12),v(-10,4,-8)},"station entrance/intake")
 check(type(sites.escapeDoors)=="table" and #sites.escapeDoors>=1,"escape route has a controlled physical hatch")
 for _,door in ipairs(sites.escapeDoors) do
  local entry=door.part.Position+v(0,sites.prisonSpawn.Position.Y-door.part.Position.Y,0)
  check(door.part.Anchored and door.part.CanCollide,"maintenance hatch is solid")
  check((door.part.Position-door.closed.Position).Magnitude<0.001,"maintenance hatch starts closed")
  check(not clear(entry),"closed maintenance hatch blocks the escape corridor")
 end
 check(sites.police and #sites.police.doors>=4,"compound has police-controlled access doors")
 for _,door in ipairs(sites.police.doors) do
  check(door.restricted==true and door.prompt and door.part.CanCollide,"police door is a restricted physical access point")
  check((door.part.Position-door.closed.Position).Magnitude<0.001,"police access starts closed: "..door.id)
 end
 -- Closed cells must be actual physical enclosures, not just attribute labels.
 local cells=sites.prisonCells
 check(type(cells)=="table" and #cells>=16,"individual cells for all16player slots")
 local cellIds={}
 local function samePosition(a,b) return (a.Position-b.Position).Magnitude<0.001 end
 for _,cell in ipairs(cells) do
  check(type(cell.id)=="string" and not cellIds[cell.id],"cell identifiers unique")
  cellIds[cell.id]=true
  check(cell.spawn and cell.door and cell.bounds,"cell provides spawn,door and confinementbounds")
  check(inBounds(cell.spawn.Position),"cell spawn within overall detentionbounds")
  check(clear(cell.spawn.Position),"cell spawn has avatarclearance: "..cell.id)
  check(cell.door.CanCollide and cell.door.Anchored and samePosition(cell.door.CFrame,cell.closed),"cell starts physically closed: "..cell.id)
  local doorRoot=cell.door.Position+v(0,cell.spawn.Position.Y-cell.door.Position.Y,0)
  check(not clear(doorRoot),"closed cell doorway blocks avatar: "..cell.id)
  local localSpawn=cell.bounds.cf:PointToObjectSpace(cell.spawn.Position)
  check(math.abs(localSpawn.X)<cell.bounds.half.X and math.abs(localSpawn.Z)<cell.bounds.half.Z,"cell spawn in its assigned confinementbounds")
  -- Check allfourhorizontal enclosurefaces at avatarheight, including any bars.
  -- Margin offsets sample just across the nominal cell boundary; a capsule must
  -- meet colliding material rather than a visual-only seal.
  local enclosure=cell.enclosure or cell.bounds
  local enclosureSpawn=enclosure.cf:PointToObjectSpace(cell.spawn.Position)
  for axis=1,2 do
   local extent=axis==1 and enclosure.half.Z or enclosure.half.X
   for _,side in ipairs({-1,1}) do
    for offset=-extent+1,extent-1,1.5 do
     local pos=axis==1 and v(side*enclosure.half.X,enclosureSpawn.Y,offset) or v(offset,enclosureSpawn.Y,side*enclosure.half.Z)
     check(not clear(enclosure.cf*pos),"cell enclosure has avatar-sized opening: "..cell.id)
    end
   end
  end
  check(not clear(enclosure.cf*v(0,enclosure.half.Y,0)),"cell has closed ceiling: "..cell.id)
  check(not clear(enclosure.cf*v(0,-enclosure.half.Y,0)),"cell has solid floor: "..cell.id)
  cell.door.CFrame=cell.open
  check(clear(doorRoot),"opening cell leaves doorwayclear: "..cell.id)
  check(type(cell.exitPath)=="table" and #cell.exitPath>=2,"cell exposes its intended exitpath")
  path(mock.CFrame.new(),cell.exitPath,"cell "..cell.id.." openexit")
  cell.door.CFrame=cell.closed
 end
 -- Open only the access doors named by each route, then check the same geometry
 -- a player would traverse. Closing doors after each route catches sharedstate.
 check(type(sites.validationRoutes)=="table" and #sites.validationRoutes>=3,"police and escape walkingroutes provided")
 for _,route in ipairs(sites.validationRoutes) do
  local changed={}
  for _,door in ipairs(route.doors or {}) do
   check(door.part and door.closed and door.open,"route door has physical leaf and states")
   table.insert(changed,{part=door.part,cf=door.part.CFrame})
   door.part.CFrame=door.open
  end
  check(type(route.points)=="table" and #route.points>=2,"walkingroute contains endpoints")
  path(mock.CFrame.new(),route.points,route.name or "complexprison",route.stairs)
  for _,door in ipairs(changed) do door.part.CFrame=door.cf end
 end
 check(clear(sites.prisonRelease.Position),"release position has avatar clearance")
 -- Guard towers use four low-rise flights, not the former steep two-flight stair.
 local towerCount=0
 for _,tower in ipairs(civic:GetDescendants())do
  if tower:IsA("Model") and string.match(tower.Name,"^Torre %d+$")then
   towerCount+=1
   local steps={}
   for _,step in ipairs(tower:GetDescendants())do
    if step:IsA("BasePart") and step.Name=="Degrau"then table.insert(steps,step)end
   end
   table.sort(steps,function(a,b)return a.Position.Y<b.Position.Y end)
   check(#steps==48,"tower has four complete stair flights")
   for i=2,#steps do
    check(steps[i].Position.Y-steps[i-1].Position.Y<=0.8,"tower stair risers fit the step-up allowance")
   end
  end
 end
 check(towerCount==4,"four usable guard towers")
 -- Roblox clamps BasePart axes above 2048. Ground must be tiled, cover the
 -- entire configured envelope, and support the prison as well as downtown.
 local ground,area={},0
 for _,p in ipairs(map:GetDescendants()) do
  if p:IsA("BasePart") then
   for _,axis in ipairs({p.Size.X,p.Size.Y,p.Size.Z}) do
    check(axis==axis and axis>0 and axis<=2048,"Roblox BasePart size limit: "..p.Name)
   end
   if string.match(p.Name,"^Ground_%d+_%d+$") then
    table.insert(ground,p)
    area+=p.Size.X*p.Size.Z
    check(p.CanCollide and p.Anchored and math.abs(p.Position.Y+p.Size.Y/2)<0.001,"ground tile has solid top at zero")
    check(math.abs(p.Position.X)+p.Size.X/2<=GameConfig.Map.GroundSize/2+0.001 and math.abs(p.Position.Z)+p.Size.Z/2<=GameConfig.Map.GroundSize/2+0.001,"ground tile within configured envelope")
   end
  end
 end
 check(#ground>=4,"large world requires tiled ground")
 check(math.abs(area-GameConfig.Map.GroundSize^2)<0.01,"ground tiles cover world area")
 for i,a in ipairs(ground) do
  for j=i+1,#ground do
   local b=ground[j]
   check(math.abs(a.Position.X-b.Position.X)>=a.Size.X/2+b.Size.X/2-0.001 or math.abs(a.Position.Z-b.Position.Z)>=a.Size.Z/2+b.Size.Z/2-0.001,"ground tiles have no positive area overlap")
  end
 end
 local function supported(point)
  for _,p in ipairs(ground) do
   local q=p.CFrame:PointToObjectSpace(point)
   if math.abs(q.X)<=p.Size.X/2 and math.abs(q.Z)<=p.Size.Z/2 then return true end
  end
  return false
 end
 local half=GameConfig.Map.GroundSize/2
 for _,x in ipairs({-half+0.1,-half/2,-0.1,0.1,half/2,half-0.1}) do
  for _,z in ipairs({-half+0.1,-half/2,-0.1,0.1,half/2,half-0.1}) do
   check(supported(mock.Vector3.new(x,0,z)),"ground quadrants and seams supported")
  end
 end
 check(supported(sites.prisonSpawn.Position) and supported(sites.prisonRelease.Position),"ground supports prison spawn and release")
 check(supported(sites.escapeSteps[#sites.escapeSteps].Parent.Position),"ground supports final escape checkpoint")
 -- New tree roots remain decoration; no low collision steps or unbounded parts.
 local treeCount=0
 for _,tree in ipairs(map:GetDescendants()) do
  if tree.Name=="Tree" and tree.ClassName=="Model" then
   treeCount+=1
   local roots,parts,crowns=0,0,0
   for _,p in ipairs(tree:GetDescendants()) do
    if p:IsA("BasePart") then
     parts+=1
     if p.Name=="RaizAparente" or p.Name=="PontaDeRaiz" then
      roots+=1
      check(not p.CanCollide,"exposed roots must not trip players")
     elseif string.find(p.Name,"CopaIrregular",1,true) then
      crowns+=1
      check(not p.CanCollide,"tree crowns must not form climbable platforms")
     end
    end
   end
   check(parts<=16 and roots==8 and crowns==3,"organic tree geometry budget and roots")
  end
 end
 check(treeCount>=GameConfig.Map.RandomTrees,"random tree count retained")
 -- Builders must not duplicate structures when bootstrap is called twice.
 local before=#map:GetDescendants()
 check(CivicBuilder.build(map)==sites,"civic build reuses current site references")
 check(#map:GetDescendants()==before,"civic build is idempotent")
 print(string.format("Geometry: %d assertions passed; %d civic parts; %d map descendants. Geometry doubles only; Studio playtest remains required.",count,civicParts,before))
 print("Organic trees validated",treeCount)
end
