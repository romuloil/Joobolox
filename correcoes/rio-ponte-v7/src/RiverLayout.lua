-- Shared geometry for terrain, minimap, road reservations and bridge construction.
local R = {
 Name = "Rio da Enseada", BridgeName = "Ponte da Foz",
 WaterY = -6, BedY = -16, Bank = 24, Step = 4,
 BridgeX = 2220, BridgeZ = 3400, DeckY = 6, RoadWidth = 24,
 DeckX0 = 2160, DeckX1 = 2280, ApproachX0 = 2020, ApproachX1 = 2420,
 RoadX0 = 1800, RoadX1 = 2770, RoadY = .52, Seed = 71037,
 -- x, z, waterline width. One stud = about 0.28 m.
 Points = {
  {2400,1340,0}, {2400,1372,28}, {2440,1560,30},
  {2320,1850,32}, {2190,2140,32}, {2280,2440,34},
  {2160,2740,34}, {2180,3020,36}, {2220,3300,36},
  {2220,3500,36}, {2280,3690,44}, {2350,3870,64}, {2380,4030,80},
 },
}
function R.at(z)
 local points=R.Points
 if z<points[1][2] or z>points[#points][2] then return nil end
 for i=1,#points-1 do
  local a,b=points[i],points[i+1]
  if z<=b[2] then
   local t=math.clamp((z-a[2])/(b[2]-a[2]),0,1);t=t*t*(3-2*t)
   return a[1]+(b[1]-a[1])*t,a[3]+(b[3]-a[3])*t
  end
 end
end
function R.samples(step)
 local out={};local z0,z1=R.Points[1][2],R.Points[#R.Points][2]
 for z=z0,z1,step or 16 do local x,w=R.at(z);table.insert(out,{pos=Vector3.new(x,R.WaterY,z),width=w})end
 if out[#out].pos.Z<z1 then local x,w=R.at(z1);table.insert(out,{pos=Vector3.new(x,R.WaterY,z1),width=w})end
 return out
end
function R.contains(x,z,pad)
 local cx,w=R.at(z);return cx~=nil and math.abs(x-cx)<=w/2+(pad or 0)
end
function R.surface(x,z)
 local cx,w=R.at(z)
 if not cx then return nil end
 local baseline=z<3770 and 0 or math.max(-18,.4-18.4*(z-3770)/250)
 local radius=w/2;local d=math.abs(x-cx)
 if d<=radius*.58 then return R.BedY end
 if d<radius then return R.BedY+(R.WaterY-R.BedY)*(d-radius*.58)/math.max(radius*.42,.01)end
 local t=math.clamp((d-radius)/18,0,1)
 return math.min(baseline,R.WaterY+(baseline-R.WaterY)*t)
end
-- Leave a real opening in the Part-based ground; Terrain fills the banks.
function R.groundPieces(x0,x1,z0,z1)
 local out={}
 local function add(a,b,c,d)if b-a>.01 and d-c>.01 then table.insert(out,{a,b,c,d})end end
 local low=math.max(z0,R.Points[1][2]);local high=math.min(z1,R.Points[#R.Points][2])
 if low>=high or x1<2050 or x0>2510 then add(x0,x1,z0,z1);return out end
 add(x0,x1,z0,low);add(x0,x1,high,z1)
 for z=low,high-.001,8 do
  local endZ=math.min(z+8,high);local l,r=math.huge,-math.huge
  for _,v in ipairs({z,(z+endZ)/2,endZ})do
   local cx,w=R.at(v);l=math.min(l,cx-w/2-R.Bank);r=math.max(r,cx+w/2+R.Bank)
  end
  add(x0,math.min(x1,l),z,endZ);add(math.max(x0,r),x1,z,endZ)
 end
 return out
end
function R.roadHeight(x)
 if x<R.ApproachX0 or x>R.ApproachX1 then return R.RoadY end
 if x<R.DeckX0 then return R.RoadY+(R.DeckY-R.RoadY)*(x-R.ApproachX0)/(R.DeckX0-R.ApproachX0)end
 if x>R.DeckX1 then return R.DeckY+(R.RoadY-R.DeckY)*(x-R.DeckX1)/(R.ApproachX1-R.DeckX1)end
 return R.DeckY
end
function R.roadWidth(x)
 return x<2020 and 60-36*math.clamp((x-1840)/180,0,1) or R.RoadWidth
end
function R.onRoad(x,z,pad)
 return x>=R.RoadX0-40 and x<=R.RoadX1+40 and math.abs(z-R.BridgeZ)<=R.roadWidth(x)/2+6+(pad or 0)
end
function R.roadPoints()
 local out={}
 for _,x in ipairs({1800,1840,2020,2160,2220,2280,2420,2770})do table.insert(out,Vector3.new(x,R.roadHeight(x),R.BridgeZ))end
 return out
end
return R
