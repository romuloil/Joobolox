-- Regras puras para facilitar ajustes sem conceder autoridade ao cliente.
local Rules = {}
function Rules.finite(value)
 return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
function Rules.finitePoint(value)
 local kind = type(value)
 return (kind == "table" or kind == "userdata" or kind == "vector")
  and Rules.finite(value.X) and Rules.finite(value.Y) and Rules.finite(value.Z)
end
function Rules.inRange(distance, maximum)
 return Rules.finite(distance) and Rules.finite(maximum) and distance >= 0 and distance <= maximum
end
function Rules.available(last, time, cooldown)
 return Rules.finite(time) and Rules.finite(cooldown) and cooldown >= 0
  and (last == nil or (Rules.finite(last) and time - last >= cooldown))
end
function Rules.healedHealth(health, maximum, amount)
 if not Rules.finite(health) or not Rules.finite(maximum) or not Rules.finite(amount)
  or health <= 0 or maximum <= 0 or amount < 0 then return nil end
 return math.min(maximum, health + amount)
end
function Rules.canPickpocket(distance, behindDot, facingDot, config)
 return Rules.inRange(distance, config.PickpocketDistance)
  and Rules.finite(behindDot) and behindDot >= config.BehindDot
  and Rules.finite(facingDot) and facingDot >= config.FacingDot
end
return Rules
