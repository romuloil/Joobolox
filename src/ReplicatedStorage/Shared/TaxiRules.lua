-- Regras puras, usadas pelo servidor. Não concedem autoridade ao cliente.
local TaxiRules = {}
function TaxiRules.finite(value)
 return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
function TaxiRules.point(value)
 local kind=type(value)
 return (kind=="table" or kind=="userdata" or kind=="vector")
  and TaxiRules.finite(value.X) and TaxiRules.finite(value.Y) and TaxiRules.finite(value.Z)
end
function TaxiRules.fare(distance, base, rate)
 if not TaxiRules.finite(distance) or distance<0 or not TaxiRules.finite(base) or base<0
  or not TaxiRules.finite(rate) or rate<0 then return nil end
 local result=base+math.ceil(distance*rate)
 return TaxiRules.finite(result) and result>=1 and math.floor(result)==result and result or nil
end
function TaxiRules.plausible(distance, elapsed, maxSpeed)
 return TaxiRules.finite(distance) and distance>=0 and TaxiRules.finite(elapsed) and elapsed>=0
  and TaxiRules.finite(maxSpeed) and maxSpeed>0 and distance<=12+maxSpeed*1.5*elapsed
end
function TaxiRules.canServe(role, driving, distance, speed, radius)
 return role==true and driving==true and TaxiRules.finite(distance) and distance>=0
  and TaxiRules.finite(speed) and speed>=0 and TaxiRules.finite(radius) and radius>0
  and distance<=radius and speed<=5
end
function TaxiRules.canFinish(stage, elapsed, straight, covered, maxSpeed, radius)
 if stage~="dropoff" or not TaxiRules.finite(elapsed) or elapsed<0
  or not TaxiRules.finite(straight) or straight<0 or not TaxiRules.finite(covered) or covered<0
  or not TaxiRules.finite(maxSpeed) or maxSpeed<=0 or not TaxiRules.finite(radius) or radius<0 then return false end
 local required=math.max(0,straight-radius)
 return elapsed>=math.max(0,required/(maxSpeed*1.3)-0.5) and covered>=required
end
return TaxiRules
