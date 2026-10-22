-- Actual outfit code with avatar/loading doubles; not visual verification.
return function(mockSource, fixtureSource, outfitSource)
	local count = 0
	local function check(value, message) count += 1; assert(value, message) end
	local makeFixture = assert(loadstring(fixtureSource))()
	for _, r6 in ipairs({false, true}) do
		local f = makeFixture(mockSource)
		local m = f.mock
		local p = f.player(1, r6)
		local service = m.load("PrisonOutfitService", outfitSource, true)
		local function clothing(class, property, value)
			local item = f.instance(class); item[property] = value; item.Parent = p.Character; return item
		end
		local shirt = clothing("Shirt", "ShirtTemplate", "civil-shirt")
		local pants = clothing("Pants", "PantsTemplate", "civil-pants")
		local graphic = clothing("ShirtGraphic", "Graphic", "civil-graphic")
		local jacket = f.instance("Accessory"); jacket.AccessoryType = m.Enum.AccessoryType.Jacket; jacket.Parent = p.Character
		local jacketPart = f.instance("Part"); jacketPart.Name = "Handle"; jacketPart.Transparency = 0.2; jacketPart.Parent = jacket
		local hair = f.instance("Accessory"); hair.AccessoryType = m.Enum.AccessoryType.Hair; hair.Parent = p.Character
		local hairPart = f.instance("Part"); hairPart.Name = "Handle"; hairPart.Transparency = 0.3; hairPart.Parent = hair
		check(service.apply(p), "apply orange outfit")
		local uniform = p.Character:FindFirstChild("UniformePrisional")
		check(uniform ~= nil and p:GetAttribute("PrisonUniform"), "custody clothing flag and model")
		check(shirt.ShirtTemplate == "" and pants.PantsTemplate == "" and graphic.Graphic == "", "civil clothing hidden")
		check(jacketPart.Transparency == 1 and hairPart.Transparency == 0.3, "layered clothing hidden, hair preserved")
		check(uniform:FindFirstChild("Zíper") ~= nil and uniform:FindFirstChild("GolaCustódia") ~= nil, "zipper and collar modeled")
		local countBefore = #uniform:GetDescendants()
		check(service.apply(p) and #uniform:GetDescendants() == countBefore, "repeated detain placement does not duplicate outfit")
		for _, item in ipairs(uniform:GetDescendants()) do
			if item:IsA("BasePart") then
				check(item.Massless and not item.Anchored and not item.CanCollide and not item.CanQuery, "uniform never blocks or anchors avatar")
				local stitch = item:FindFirstChild("CosturaCustódia")
				check(stitch ~= nil and stitch.Part0.Parent == p.Character, "outfit welded directly to avatar limb")
			end
		end
		-- Same object receives its avatar template AFTER joining the character.
		shirt.ShirtTemplate = "loaded-civil-shirt"
		check(shirt.ShirtTemplate == "", "late same-object texture immediately hidden")
		jacketPart.Transparency = 0.45
		check(jacketPart.Transparency == 1, "late layered visibility remains hidden")
		local late = clothing("Pants", "PantsTemplate", "late-pants")
		check(late.PantsTemplate == "", "late clothing object hidden")
		local torso = p.Character:FindFirstChild(r6 and "Torso" or "UpperTorso")
		torso.Size = m.Vector3.new(3, 2.6, 1.4)
		p.CharacterAppearanceLoaded:Fire(p.Character)
		check(math.abs(uniform:FindFirstChild("JaquetaLaranja").Size.X - 3.12) < 0.001, "outfit resizes after appearance load")
		check(#uniform:GetDescendants() == countBefore, "appearance event rebuild does not duplicate pieces")
		service.restore(p)
		check(not p.Character:FindFirstChild("UniformePrisional") and not p:GetAttribute("PrisonUniform"), "release removes custody outfit")
		check(shirt.ShirtTemplate == "loaded-civil-shirt" and pants.PantsTemplate == "civil-pants" and graphic.Graphic == "civil-graphic", "latest original templates restored exactly")
		check(late.PantsTemplate == "late-pants" and jacketPart.Transparency == 0.45, "late clothing and layered values restored")
		shirt.ShirtTemplate = "post-release-change"
		check(shirt.ShirtTemplate == "post-release-change", "release disconnects outfit watchers")
		service.restore(p)
		check(shirt.ShirtTemplate == "post-release-change", "repeated release is idempotent")
		check(service.apply(p), "outfit reissued")
		local old = p.Character
		p.Character = f.character(r6)
		local newShirt = clothing("Shirt", "ShirtTemplate", "respawn-civil")
		check(service.apply(p), "new character gets prison outfit")
		check(not old:FindFirstChild("UniformePrisional") and shirt.ShirtTemplate == "post-release-change", "respawn restores abandoned avatar")
		check(newShirt.ShirtTemplate == "", "respawn current clothes hidden")
		service.restore(p)
		check(newShirt.ShirtTemplate == "respawn-civil", "release restores current avatar")
	end
	-- Character parts can arrive after PrisonService has seen Root/Humanoid.
	local f = makeFixture(mockSource)
	local p = f.player(2, false)
	local service = f.mock.load("PrisonOutfitService", outfitSource, true)
	local torso = p.Character:FindFirstChild("UpperTorso"); torso.Parent = nil
	check(service.apply(p), "partial avatar can wait for limbs")
	torso.Parent = p.Character
	check(p.Character:FindFirstChild("UniformePrisional"):FindFirstChild("JaquetaLaranja") ~= nil, "late torso gets orange jacket")
	service.restore(p)
	p.Character = nil
	check(not service.apply(p), "missing avatar rejected")
	print("PASS PrisonOutfitService: " .. count .. " avatar/lifecycle checks (mock services)")
end
