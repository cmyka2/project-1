-- Asset lookup by key, placeholders for missing assets, and display anchoring
-- (rigged models must keep their limbs unanchored or animations never play).
return function(ctx)
	local T, Loader, Mock = ctx.Test, ctx.Loader, ctx.Mock
	local describe, it, expect = T.describe, T.it, T.expect
	local AssetRegistry = Loader.requirePath("ReplicatedStorage.Shared.AssetRegistry")
	local roblox = require("@lune/roblox")
	local Instance = Mock.globals().Instance

	local assets = Mock.game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local monsterFolder = assets:FindFirstChild("MonsterModels")

	local function part(name, parent, y)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = roblox.Vector3.new(2, 2, 2)
		p.CFrame = roblox.CFrame.new(0, y or 1, 0)
		p.Parent = parent
		return p
	end

	local info = { Rarity = "Common", Element = "Nature", Name = "Test" }

	describe("AssetRegistry", function()
		it("returns a placeholder (and records it) when a model is missing", function()
			local model = AssetRegistry.monsterModel("DefinitelyNotImported", info)
			expect(model:IsA("Model")).toBe(true)
			expect(model:GetAttribute("Placeholder")).toBe(true)
			expect(AssetRegistry.missingReport().DefinitelyNotImported).notToBeNil()
		end)

		it("uses an imported model found by its ModelKey, without code changes", function()
			local source = Instance.new("Model")
			source.Name = "MossGolem"
			part("Body", source)
			source.Parent = monsterFolder
			local model = AssetRegistry.monsterModel("MossGolem", info)
			expect(model ~= source).toBe(true)
			expect(model:FindFirstChild("Body")).notToBeNil()
			expect(model:GetAttribute("Placeholder")).toBeNil()
			expect(model:GetAttribute("ModelKey")).toBe("MossGolem")
			source:Destroy()
		end)

		it("fully anchors a static model and disables collisions", function()
			local model = Instance.new("Model")
			local a, b = part("A", model), part("B", model, 3)
			a.CanCollide, b.CanCollide = true, true
			AssetRegistry.anchorForDisplay(model)
			expect(a.Anchored and b.Anchored).toBe(true)
			expect(a.CanCollide or b.CanCollide).toBe(false)
		end)

		it("anchors only the root of a rigged model so animations can play", function()
			local model = Instance.new("Model")
			local root = part("HumanoidRootPart", model)
			local torso = part("Torso", model, 2)
			local arm = part("Arm", model, 2)
			local hat = part("Hat", model, 4)
			local loose = part("Prop", model, 0)
			local m1 = Instance.new("Motor6D")
			m1.Part0, m1.Part1, m1.Parent = root, torso, root
			local m2 = Instance.new("Motor6D")
			m2.Part0, m2.Part1, m2.Parent = torso, arm, torso
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = hat, torso, hat
			AssetRegistry.anchorForDisplay(model)
			expect(root.Anchored).toBe(true)
			expect(torso.Anchored).toBe(false)
			expect(arm.Anchored).toBe(false)
			expect(hat.Anchored).toBe(false) -- welded to a moving limb
			expect(loose.Anchored).toBe(true) -- not joined to the rig: must not fall
		end)

		it("returns nil for unset icon/sound/animation ids", function()
			expect(AssetRegistry.icon("NoSuchIcon")).toBeNil()
			expect(AssetRegistry.sound("UIClick")).toBeNil()
			expect(AssetRegistry.animation("MossGolem_Idle")).toBeNil()
		end)
	end)
end
