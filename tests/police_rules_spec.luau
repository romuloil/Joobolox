local Rules = require("../src/ReplicatedStorage/Shared/PoliceRules")
local count = 0
local function check(name, result)
	count += 1
	assert(result, name)
end

check("living civilian may join open slot", Rules.canJoin(true, false, 0, 3))
check("third slot available", Rules.canJoin(true, false, 2, 3))
check("fourth slot refused", not Rules.canJoin(true, false, 3, 3))
check("dead player cannot join", not Rules.canJoin(false, false, 0, 3))
check("inmate cannot join", not Rules.canJoin(true, true, 0, 3))
check("invalid vacancy count refused", not Rules.canJoin(true, false, 0 / 0, 3))
check("negative vacancy count refused", not Rules.canJoin(true, false, -1, 3))

local function capture(duty, tool, distance, now, untilTime, wanted, detained, protected)
	return Rules.canCapture(duty, tool, distance, now, untilTime, wanted, detained, protected)
end
check("close equipped officer may capture stunned suspect", capture(true, true, 4, 1000, 1006, true, false, false))
check("capture at exact maximum range", capture(true, true, 8, 1000, 1006, true, false, false))
check("capture outside range refused", not capture(true, true, 8.01, 1000, 1006, true, false, false))
check("off-duty capture refused", not capture(false, true, 4, 1000, 1006, true, false, false))
check("unequipped cuffs refused", not capture(true, false, 4, 1000, 1006, true, false, false))
check("innocent civilian cannot be arrested", not capture(true, true, 4, 1000, 1006, false, false, false))
check("existing inmate cannot be captured twice", not capture(true, true, 4, 1000, 1006, true, true, false))
check("protected work zone prevents capture", not capture(true, true, 4, 1000, 1006, true, false, true))
check("stun deadline exclusive", not capture(true, true, 4, 1006, 1006, true, false, false))
check("expired stun refused", not capture(true, true, 4, 1010, 1006, true, false, false))
check("invalid capture distance refused", not capture(true, true, 0 / 0, 1000, 1006, true, false, false))
check("negative capture distance refused", not capture(true, true, -1, 1000, 1006, true, false, false))
check("invalid capture time refused", not capture(true, true, 4, math.huge, 1006, true, false, false))

check("nonzero direction allowed", Rules.validDirection({ X = 0, Y = 0, Z = -1 }))
check("zero direction refused", not Rules.validDirection({ X = 0, Y = 0, Z = 0 }))
check("NaN direction refused", not Rules.validDirection({ X = 0 / 0, Y = 0, Z = -1 }))
check("infinite direction refused", not Rules.validDirection({ X = math.huge, Y = 0, Z = -1 }))
check("oversized direction refused", not Rules.validDirection({ X = 1e8, Y = 0, Z = -1 }))
check("incomplete direction refused", not Rules.validDirection({ X = 0, Z = -1 }))
check("numeric direction refused", not Rules.validDirection(4))
check("nil direction refused", not Rules.validDirection(nil))

check("security report allowed", Rules.validReport("Seguranca"))
check("patrol report allowed", Rules.validReport("Patrulha"))
check("maintenance report allowed", Rules.validReport("Manutencao"))
check("arbitrary report text refused", not Rules.validReport("hello"))
check("table report category refused", not Rules.validReport({}))
check("nil report category refused", not Rules.validReport(nil))

print(("PASS PoliceRules: %d checks"):format(count))
