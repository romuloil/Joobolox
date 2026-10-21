-- UIScaler (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > UIScaler
-- Deixa a interface menor em telas pequenas (celular) e normal no PC.
-- Uso: UIScaler.attach(frame)  -- o frame encolhe em volta do seu AnchorPoint.

local Workspace = game:GetService("Workspace")

local UIScaler = {}

local REFERENCE = 720 -- altura de tela (px) em que a escala é 1
local MIN_SCALE = 0.6
local scales = {}
local listeners = {}

local function currentScale()
	local camera = Workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local shortest = math.min(size.X, size.Y)
	return math.clamp(shortest / REFERENCE, MIN_SCALE, 1)
end

local function refresh()
	local s = currentScale()
	for _, uiScale in ipairs(scales) do
		uiScale.Scale = s
	end
	for _, fn in ipairs(listeners) do
		fn(s)
	end
end

-- Chama fn(escala) agora e sempre que a tela mudar de tamanho
function UIScaler.onChanged(fn)
	table.insert(listeners, fn)
	fn(currentScale())
end

function UIScaler.attach(guiObject)
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = currentScale()
	uiScale.Parent = guiObject
	table.insert(scales, uiScale)
	return uiScale
end

function UIScaler.get()
	return currentScale()
end

local function watchCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

return UIScaler
