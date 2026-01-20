
-- Bootstrapper.lua (main)
-- ScreenGui version: tabs + dropdowns + keybinds + scans + export. (global hit-test)

local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local GroupService = game:GetService("GroupService")
local StudioService = game:GetService("StudioService")
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")

local ScanCore = require(script.Modules.ScanCore)
local Exporter = require(script.Modules.Exporter)
local LoggerMod = require(script.Modules.Logger)
local Draggable = require(script.Modules.DraggableObject)
local RegValidate = require(script.Modules.RegisterValidate)
local RegistryMod = require(script.Modules.Registry)

-- ==== CONFIG ====
local WEBHOOK_URL = "" -- set your Discord webhook URL here
local CHECK_COOLDOWN = 10
local COLOR_INACTIVE = Color3.fromRGB(70, 27, 119)
local COLOR_ACTIVE = Color3.fromRGB(193, 135, 255)
local DEFAULT_API_URL = "https://your-railway-app.up.railway.app"

-- ==== Registry settings ====
local function getSetting(key)
	if not plugin then return nil end
	local ok, value = pcall(function() return plugin:GetSetting(key) end)
	return ok and value or nil
end

local function setSetting(key, value)
	if not plugin then return end
	pcall(function() plugin:SetSetting(key, value) end)
end

local function setupRegistry()
	local apiUrl = getSetting("Palantir.ApiUrl") or DEFAULT_API_URL
	local ownerKey = getSetting("Palantir.OwnerKey")
	local modelId = getSetting("Palantir.ModelId")
	RegistryMod.setup({
		apiUrl = apiUrl,
		ownerKey = ownerKey,
		modelId = modelId,
	})
end

local function setOwnerKey(ownerKey)
	RegistryMod.OwnerKey = ownerKey
	setSetting("Palantir.OwnerKey", ownerKey)
end

local function setModelId(modelId)
	RegistryMod.ModelId = modelId
	setSetting("Palantir.ModelId", modelId)
end

setupRegistry()

local refreshRegistryView

-- ==== GUI mount ====
local coreGui = game:GetService("CoreGui")
local gui = coreGui:FindFirstChild("Palantir")
if gui then
	for _, child in ipairs(coreGui:GetChildren()) do
		if child:IsA("ScreenGui") and child.Name == "Palantir" then
			child:Destroy()
		end
	end
	local src = script:FindFirstChild("Palantir") or script.Parent:FindFirstChild("Palantir")
	assert(src, "Put your 'Palantir' ScreenGui next to this script")
	gui = src:Clone()
	gui.Parent = coreGui
else
	local src = script:FindFirstChild("Palantir") or script.Parent:FindFirstChild("Palantir")
	assert(src, "Put your 'Palantir' ScreenGui next to this script")
	gui = src:Clone()
	gui.Parent = coreGui
end

gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- ==== refs ====
local main = gui:WaitForChild("Main")
local mainDrag = Draggable.new(main)
mainDrag:Enable()
local topBar = main:WaitForChild("TopBar")
local tabBar = topBar:WaitForChild("TabBar"):WaitForChild("TBar")
local tabsFolder = tabBar:WaitForChild("Tabs")

local tab_File = tabsFolder:WaitForChild("File")
local tab_Scans = tabsFolder:WaitForChild("Scans")

local tab_Tools = tabsFolder:FindFirstChild("Tools")
local tab_Chassis = tabsFolder:FindFirstChild("Chassis")
local tab_Registry = tabsFolder:WaitForChild("Registry")

local dd_File = tabBar:WaitForChild("File_DropDown")
local dd_Scans = tabBar:WaitForChild("Scans_DropDown")

local popup = main:WaitForChild("Popup")
local inputUser = (popup:FindFirstChild("Content") and popup.Content:WaitForChild("InputUser")) or popup:WaitForChild("InputUser")
local popClose = popup:FindFirstChild("TopBar"):WaitForChild("Close")
local btnSubmit = popup:WaitForChild("Submit")
local unfocused = nil -- overlay not used

local regPop = main:WaitForChild("RegModel")
local regSubmit = regPop:WaitForChild("Submit")
local regCont = regPop:WaitForChild("Content")
local whitelistInput = regCont:WaitForChild("InputWL")
local regUserInfo = regCont:WaitForChild("UserInfo")

-- === Plugin toolbar button: toggle Palantir UI ===
if plugin then
	local TOOLBAR_NAME = "Palantir"
	local BUTTON_TOOLTIP = "Toggle Palantir"
	local ICON_ASSET = "rbxassetid://102326359525955"

	local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
	local button = toolbar:CreateButton("Palantir", BUTTON_TOOLTIP, ICON_ASSET)
	pcall(function() button.ClickableWhenViewportHidden = true end)

	local function setVisible(v)
		gui.Enabled = v
		if unfocused then unfocused.Visible = false end
		pcall(function() button:SetActive(v) end)
		pcall(function() plugin:SetSetting("Palantir.Visible", v) end)
	end

	local last = false
	local ok, saved = pcall(function() return plugin:GetSetting("Palantir.Visible") end)
	if ok and typeof(saved) == "boolean" then last = saved else last = true end
	setVisible(last)

	button.Click:Connect(function()
		setVisible(not gui.Enabled)
	end)

	plugin.Unloading:Connect(function()
		pcall(function() plugin:SetSetting("Palantir.Visible", gui.Enabled) end)
	end)
end

local view = main:WaitForChild("View")
-- === Views ===
local regView = main:WaitForChild("RegistryView")
view.Visible = true
regView.Visible = false

-- === Dashboards ===
local dashboard = regView:WaitForChild("Dashboard")

local Dash_Overview = dashboard:WaitForChild("Overview")
local Dash_ListCont = dashboard:WaitForChild("ListingContainer")
local Dash_LCCont = Dash_ListCont:WaitForChild("Content")
local Dash_Listings = Dash_LCCont:WaitForChild("Listings")
local Dash_Content = Dash_Overview:WaitForChild("Content")
local Dash_RegMod = Dash_Content:WaitForChild("Register")
local Dash_SwapDash = Dash_Content:WaitForChild("SwapOwner")

local grp_dashboard = regView:WaitForChild("Group_Dashboard")

local gDash_Overview = grp_dashboard:WaitForChild("Overview")
local gDash_ListCont = grp_dashboard:WaitForChild("ListingContainer")
local gDash_LCCont = gDash_ListCont:WaitForChild("Content")
local gDash_Listings = gDash_LCCont:WaitForChild("Listings")
local gDash_Content = gDash_Overview:WaitForChild("Content")
local gDash_RegMod = gDash_Content:WaitForChild("Register")
local gDash_SwapDash = gDash_Content:WaitForChild("SwapOwner")

local dd_Tools = tabBar:FindFirstChild("Tools_DropDown")
local dd_Chassis = tabBar:FindFirstChild("Chassis_DropDown")
local dd_RegArc = tabBar:FindFirstChild("RegistryArchived_DropDown") -- should never be opened by tab click
if dd_RegArc then dd_RegArc.Visible = false end

local output = view:WaitForChild("Output")
local outScroll = output:WaitForChild("Logs")
local template = outScroll:WaitForChild("Template")
local clearBtn = output:FindFirstChild("ConsoleClear")

-- start hidden

dd_File.Visible = false

dd_Scans.Visible = false

-- ===== Logger (safe) =====
local okL, LogObj = pcall(function() return LoggerMod.new(outScroll, template) end)
local Logger = okL and LogObj or { Line = function() end, Clear = function() end }
if not okL then warn("Palantir Logger: fallback to no-op logger") end
Logger:Clear()
local function logRT(t) if Logger and Logger.Line then Logger:Line(t) else warn((t or ""):gsub("<.->", "")) end end

-- ===== State =====
local lastMesh, lastRunAt, currentUID = nil, 0, nil
local readyForExport = false -- freshness gate

local function isModelSelected()
	local sel = Selection:Get()
	return sel[1] and sel[1]:IsA("Model") and sel[1] or nil
end

-- ---------- TAB MANAGER (global hit-test) ----------
local TabMan = {}
TabMan.tabs = {
	{ btn = tab_File, dd = dd_File, hovering = false, open = false },
	{ btn = tab_Scans, dd = dd_Scans, hovering = false, open = false },
	{ btn = tab_Tools, dd = dd_Tools, hovering = false, open = false },
	{ btn = tab_Chassis, dd = dd_Chassis, hovering = false, open = false },
	{ btn = tab_Registry, dd = nil, hovering = false, open = false }
	-- NOTE: Registry tab intentionally NOT here (no dropdown; swaps view instead)
}
TabMan.openTab = nil

local function findBack(guiObj)
	return guiObj:FindFirstChild("Back") or guiObj:FindFirstChildWhichIsA("Frame") or guiObj:FindFirstChildWhichIsA("ImageLabel")
end
local function ensureStroke(guiObj)
	local s = guiObj:FindFirstChildOfClass("UIStroke") or guiObj:FindFirstChildWhichIsA("UIStroke", true)
	if not s then s = Instance.new("UIStroke"); s.Thickness = 1; s.Enabled = false; s.Parent = guiObj end
	return s
end
for _, t in ipairs(TabMan.tabs) do
	t.back = findBack(t.btn)
	t.stroke = ensureStroke(t.btn)
end

local function setBG(obj, alpha) if obj then obj.BackgroundTransparency = alpha end end
local function applyTabVisual(t)
	local on = t.hovering or t.open
	setBG(t.btn, on and 0 or 1)
	if t.back then setBG(t.back, on and 0 or 1) end
	if t.stroke then t.stroke.Enabled = on end
end

local function setDropdownVisible(dd, vis)
	if dd then dd.Visible = vis end
end

local function closeAllDropdowns()
	for _, t in ipairs(TabMan.tabs) do
		t.open = false
		applyTabVisual(t)
		setDropdownVisible(t.dd, false)
	end
	TabMan.openTab = nil
	if dd_RegArc then dd_RegArc.Visible = false end
end

-- Keep track of which view is active ("main" or "registry")
local ActiveView = "main"
local ActiveDashboard = "Group_Dashboard"
local SelectedTabBtn = nil

local function setTabSelected(tabBtn, selected)
	local stroke = tabBtn:FindFirstChildOfClass("UIStroke") or tabBtn:FindFirstChildWhichIsA("UIStroke", true)
	if selected then
		tabBtn.BackgroundTransparency = 0
		if stroke then stroke.Enabled = true end
	else
		tabBtn.BackgroundTransparency = 1
		if stroke then stroke.Enabled = false end
	end
end

local function setActiveView(which)
	if which == "registry" then
		ActiveView = "registry"
		view.Visible = false
		regView.Visible = true
		if refreshRegistryView then
			refreshRegistryView()
		end
	else
		ActiveView = "main"
		regView.Visible = false
		view.Visible = true
	end
end

local function setActiveDashboard(which)
	if which == "Dashboard" then
		ActiveDashboard = "Dashboard"
		grp_dashboard.Visible = false
		dashboard.Visible = true
	else
		ActiveDashboard = "Group_Dashboard"
		grp_dashboard.Visible = true
		dashboard.Visible = false
	end
end

local function ensureMainView()
	if ActiveView ~= "main" then
		setActiveView("main")
		if SelectedTabBtn and SelectedTabBtn ~= tab_Registry then
			setTabSelected(SelectedTabBtn, true)
		end
	end
end

local function pointIn(guiObj, pt)
	local pos, size = guiObj.AbsolutePosition, guiObj.AbsoluteSize
	return pt.X >= pos.X and pt.X <= pos.X + size.X and pt.Y >= pos.Y and pt.Y <= pos.Y + size.Y
end

function TabMan:updateHover()
	local m = UserInputService:GetMouseLocation()
	local hoveredTab = nil

	for _, t in ipairs(self.tabs) do
		local inside = pointIn(t.btn, m)
		if inside ~= t.hovering then
			t.hovering = inside
			applyTabVisual(t)
		end
		if inside then hoveredTab = t end
	end

	if self.openTab and hoveredTab and hoveredTab ~= self.openTab then
		setDropdownVisible(self.openTab.dd, false)
		self.openTab.open = false
		applyTabVisual(self.openTab)

		hoveredTab.open = true
		setDropdownVisible(hoveredTab.dd, true)
		applyTabVisual(hoveredTab)

		self.openTab = hoveredTab
	end
end

function TabMan:clickAt(pt)
	for _, t in ipairs(self.tabs) do
		if pointIn(t.btn, pt) then
			local willOpen = not t.open

			if t.btn == tab_Registry then
				if ActiveView == "main" then
					setActiveView("registry")
					closeAllDropdowns()
					self.openTab = t
				else
					setActiveView("main")
					closeAllDropdowns()
					if self.openTab == t then self.openTab = nil end
				end
				return true
			end

			if willOpen then
				closeAllDropdowns()
				t.open = true
				setDropdownVisible(t.dd, true)
				self.openTab = t
			else
				t.open = false
				setDropdownVisible(t.dd, false)
				if self.openTab == t then self.openTab = nil end
			end
			applyTabVisual(t)
			return true
		end
	end
	return false
end

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		TabMan:updateHover()

		local m = UserInputService:GetMouseLocation()
		local hoveringReg = pointIn(tab_Registry, m)
		setTabSelected(tab_Registry, hoveringReg or ActiveView == "registry")
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local pt = UserInputService:GetMouseLocation()
		if not TabMan:clickAt(pt) then
			closeAllDropdowns()
		end
	end
end)

-- ===== Registry tab wiring (swap view; no dropdown) =====
ensureStroke(tab_Registry)



tab_Registry.MouseEnter:Connect(function()
	setTabSelected(tab_Registry, true)
end)
tab_Registry.MouseLeave:Connect(function()
	setTabSelected(tab_Registry, ActiveView == "registry")
end)

-- ---- Dropdown button style helpers ----
local function styleDDButton(btn, isActive)
	if not btn then return end
	local label = btn:FindFirstChildWhichIsA("TextLabel") or btn
	local stroke = btn:FindFirstChildOfClass("UIStroke") or btn:FindFirstChildWhichIsA("UIStroke", true)
	if stroke then stroke.Enabled = false end
	btn.BackgroundTransparency = 1
	label.TextColor3 = isActive and COLOR_ACTIVE or COLOR_INACTIVE
	btn:SetAttribute("Pal_Active", isActive)
	if not btn:GetAttribute("Pal_Styled") then
		btn:SetAttribute("Pal_Styled", true)
		btn.MouseEnter:Connect(function()
			if stroke then stroke.Enabled = true end
			btn.BackgroundTransparency = 0.85
		end)
		btn.MouseLeave:Connect(function()
			if stroke then stroke.Enabled = false end
			btn.BackgroundTransparency = 1
			label.TextColor3 = (btn:GetAttribute("Pal_Active") and COLOR_ACTIVE or COLOR_INACTIVE)
		end)
	end
end

-- ===== Dropdown wiring =====
local fileContent = dd_File:WaitForChild("Content")
local btnExport = fileContent:FindFirstChild("Export") or fileContent:FindFirstChildWhichIsA("TextButton")
local btnUpload = fileContent:FindFirstChild("UploadRbx") or fileContent:FindFirstChildWhichIsA("TextButton")
styleDDButton(btnExport, false)
styleDDButton(btnUpload, false)

local scansContent = dd_Scans:WaitForChild("Content")
local btnMesh = scansContent:FindFirstChild("MeshCheck")
local btnSec = scansContent:FindFirstChild("Security")
styleDDButton(btnMesh, false)
styleDDButton(btnSec, false)

local function refreshScanButtons()
	local has = isModelSelected() ~= nil

	readyForExport = false
	lastMesh = nil
	if btnExport then styleDDButton(btnExport, false) end
	if btnUpload then styleDDButton(btnUpload, false) end

	styleDDButton(btnMesh, has)
	styleDDButton(btnSec, has)
end

Selection.SelectionChanged:Connect(refreshScanButtons)
refreshScanButtons()

-- ===== Popup (UserId) =====
local function digitsOnly(s) return (tostring(s or ""):gsub("%D", "")) end
inputUser:GetPropertyChangedSignal("Text"):Connect(function()
	inputUser.Text = digitsOnly(inputUser.Text or "")
	readyForExport = false
	lastMesh = nil
	if btnExport then styleDDButton(btnExport, false) end
end)

local function openUserPopup()
	readyForExport = false
	lastMesh = nil
	if btnExport then styleDDButton(btnExport, false) end

	popup.Visible = true
	inputUser:CaptureFocus()
end
local function closePopup()
	popup.Visible = false
end

local function openRegisterPopup()
	regPop.Visible = true
	whitelistInput:CaptureFocus()
end
local function closeRegisterPopup()
	regPop.Visible = false
end

inputUser.FocusLost:Connect(function(enter)
	if enter then
		currentUID = tonumber(inputUser.Text)
		if currentUID then
			local uname = ScanCore.GetUsernameFromId(currentUID)
			local ui = popup:FindFirstChild("Content") and popup.Content:FindFirstChild("UserInfo")
			if ui and ui:FindFirstChild("TextLabel") then
				ui.Frame.Username_Info.Text = uname
				ui.Frame.UserID_Info.Text = tostring(currentUID)
			end
		end
	end
end)
if clearBtn then clearBtn.MouseButton1Click:Connect(function() Logger:Clear() end) end
-- ===== Action Helpers =====
local function getPreferredUploadOwner()
	local myId
	pcall(function()
		if StudioService.GetUserId then
			myId = StudioService:GetUserId()
		end
	end)

	local ct, id = game.CreatorType, game.CreatorId
	if ct == Enum.CreatorType.Group and id and id > 0 then
		return id, "Group", myId or 0, "User"
	end
	return myId or id or 0, "User"
end

local function loadRegistryInfo(id, typeUser, userID, tagU)
	if typeUser == "Group" then
		local gInfo
		pcall(function()
			if id ~= nil then
				gInfo = GroupService:GetGroupInfoAsync(id)
				gInfo = gInfo["Name"]
			else
				gInfo = "Not Found"
			end
		end)

		gDash_Content.Name_Info.Text = gInfo
		gDash_Content.OwnerID_Info.Text = id

		if userID ~= nil then
			local username
			pcall(function()
				username = Players:GetNameFromUserIdAsync(userID)
			end)

			if username then
				Dash_Content.Name_Info.Text = username
				Dash_Content.OwnerID_Info.Text = userID
			end
		end
	else
		local username
		pcall(function()
			username = Players:GetNameFromUserIdAsync(id)
		end)
		Dash_Content.Name_Info.Text = username
		Dash_Content.OwnerID_Info.Text = id
	end
end

local function setupDashboards(id, typeUser, userID, tagU)
	if typeUser == "Group" then
		dashboard.Visible = false
		grp_dashboard.Visible = true
		loadRegistryInfo(id, typeUser, userID, tagU)
	else
		dashboard.Visible = true
		gDash_SwapDash.Visible = false
		grp_dashboard.Visible = false
		loadRegistryInfo(id, typeUser, userID, tagU)
	end
end

local function getOwnerDisplayName()
	if ActiveDashboard == "Group_Dashboard" then
		return gDash_Content.Name_Info.Text
	end
	return Dash_Content.Name_Info.Text
end

local function parseWhitelistInput(text)
	local ids = {}
	local seen = {}
	for token in tostring(text or ""):gmatch("[^\n,;%s]+") do
		local id = tonumber((token:gsub("%D", "")))
		if id and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	return ids
end

local function findDescendant(parent, name)
	if not parent then return nil end
	for _, child in ipairs(parent:GetDescendants()) do
		if child.Name == name then
			return child
		end
	end
	return nil
end

local function formatDate(iso)
	if type(iso) ~= "string" then return "-" end
	return iso:sub(1, 10)
end

local function updateStatsLabels(stats)
	local listings = stats and tostring(stats.listings or 0) or "-"
	local wl = stats and tostring(stats.whitelist_count or 0) or "-"
	local usage = stats and tostring(stats.usage_count or 0) or "-"

	Dash_Content.Listings_Info.Text = listings
	Dash_Content.WL_Info.Text = wl
	Dash_Content.Usage_Info.Text = usage
	gDash_Content.Listings_Info.Text = listings
	gDash_Content.WL_Info.Text = wl
	gDash_Content.Usage_Info.Text = usage
end

local function clearListings(container)
	if not container then return end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("ImageButton") then
			if child.Name ~= "Template" then
				child:Destroy()
			end
		end
	end
end

local function populateListing(container, model)
	if not container then return end
	local templateFrame = container:FindFirstChild("Template") or findDescendant(container, "Template")
	if not templateFrame then return end

	clearListings(container)

	if not model then
		return
	end

	local clone = templateFrame:Clone()
	clone.Name = "Listing_" .. tostring(model.id)
	clone.Visible = true
	clone.Parent = container

	local nameLabel = findDescendant(clone, "Name")
	local dateLabel = findDescendant(clone, "Date")
	local meshLabel = findDescendant(clone, "MeshCount")

	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = model.display_name or "Unknown"
	end
	if dateLabel and dateLabel:IsA("TextLabel") then
		dateLabel.Text = formatDate(model.registered_at)
	end
	if meshLabel and meshLabel:IsA("TextLabel") then
		meshLabel.Text = tostring(model.mesh_count or 0)
	end

	local btnDelete = findDescendant(clone, "Delete")
	local btnLogs = findDescendant(clone, "Logs")
	local btnUpdate = findDescendant(clone, "Update")

	if btnDelete and btnDelete:IsA("GuiButton") then
		btnDelete.MouseButton1Click:Connect(function()
			logRT('<font color="#ffd27f">Delete is not implemented on the server.</font>')
		end)
	end

	if btnLogs and btnLogs:IsA("GuiButton") then
		btnLogs.MouseButton1Click:Connect(function()
			local ok, resp = RegistryMod.listUsageLogs(model.id, { page = 1, page_size = 20 })
			if not ok then
				logRT('<font color="#ff6b6b">Failed to load usage logs.</font>')
				return
			end
			local count = resp.total or 0
			logRT(string.format('<font color="#a992ff"><b>Usage Logs</b></font> (%d total)', count))
			for _, entry in ipairs(resp.logs or {}) do
				local line = string.format(
					'[%s] user=%s allowed=%s reason=%s',
					formatDate(entry.created_at),
					tostring(entry.actor_user_id),
					tostring(entry.allowed),
					tostring(entry.reason or "")
				)
				logRT(line)
			end
		end)
	end

	if btnUpdate and btnUpdate:IsA("GuiButton") then
		btnUpdate.MouseButton1Click:Connect(function()
			local modelSel = isModelSelected()
			if not modelSel then
				logRT('<font color="#ff6b6b">Select a model to update meshes.</font>')
				return
			end
			local parsed = RegistryMod.ParseModel(modelSel)
			if not parsed then
				logRT('<font color="#ff6b6b">Failed to parse model meshes.</font>')
				return
			end
			local meshes = {}
			for _, mesh in ipairs(parsed.meshes or {}) do
				table.insert(meshes, {
					mesh_asset_id = mesh.assetId,
					mesh_name = mesh.name,
				})
			end
			local ok, resp = RegistryMod.upsertModelMeshes(meshes)
			if ok then
				logRT('<font color="#65d07d">Meshes updated.</font>')
				local okStats, stats = RegistryMod.getStats(model.id)
				if okStats then
					updateStatsLabels(stats)
				end
				local okModel, modelResp = RegistryMod.getModel(model.id)
				if okModel and modelResp and modelResp.model then
					populateListing(container, modelResp.model)
				end
			else
				logRT('<font color="#ff6b6b">Mesh update failed.</font>')
			end
		end)
	end
end

refreshRegistryView = function()
	if not RegistryMod.ModelId then
		updateStatsLabels(nil)
		clearListings(Dash_Listings)
		clearListings(gDash_Listings)
		return
	end

	local okStats, stats = RegistryMod.getStats(RegistryMod.ModelId)
	if okStats then
		updateStatsLabels(stats)
	end

	local okModel, modelResp = RegistryMod.getModel(RegistryMod.ModelId)
	if okModel and modelResp and modelResp.model then
		populateListing(Dash_Listings, modelResp.model)
		populateListing(gDash_Listings, modelResp.model)
	end
end
-- ===== Actions =====
local running = false

local function meshCheck()
	ensureMainView()
	readyForExport = false
	lastMesh = nil
	if btnExport then styleDDButton(btnExport, false) end

	if running then return end
	local now = os.clock()
	if now - lastRunAt < CHECK_COOLDOWN then
		Logger:Line(string.format('<font color="#ffd27f">Cooldown:</font> wait %.0fs...', CHECK_COOLDOWN - (now - lastRunAt)))
		return
	end
	local model = isModelSelected()
	if not model then Logger:Line('<font color="#ff6b6b">Select a Model first.</font>'); return end
	if not currentUID then openUserPopup(); return end

	running = true
	lastRunAt = now
	closePopup()

	local total = 0
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("MeshPart") then
			if inst.MeshId and inst.MeshId ~= "" then total += 1 end
		elseif inst:IsA("SpecialMesh") then
			if inst.MeshId and inst.MeshId ~= "" then total += 1 end
		end
	end

	local function pct(i, n)
		if n <= 0 then return 0 end
		return math.clamp(math.floor((i / n) * 100 + 0.5), 0, 100)
	end

	local progressLabel = Logger:Line(('<font color="#a992ff"><b>Running Mesh Check...</b></font> (0%% - 0/%d)'):format(total))
	local function setProgress(done, n, phase)
		n = n or total
		if not progressLabel or not progressLabel.Parent then return end
		local lineNo = tonumber(progressLabel.Name) or 0
		progressLabel.Text = string.format(
			'<b>%04d</b>  <font color="#a992ff"><b>Running Mesh Check...</b></font> (%d%%%% - %d/%d)%s',
			lineNo, pct(done, n), done, n, phase and ("  <i>" .. phase .. "</i>") or ""
		)
	end

	setProgress(0, total, total == 0 and "No mesh assets detected" or "Counting complete")

	local opts = {
		total = total,
		onProgress = function(done, n)
			setProgress(done, n or total, nil)
		end
	}
	local report, totals, userName = ScanCore.MeshScan(model, currentUID, opts, Logger)

	if not report then
		Logger:Line('<font color="#ff6b6b">Mesh check failed.</font>')
		running = false
		readyForExport = false
		if btnExport then styleDDButton(btnExport, false) end
		return
	end

	setProgress(total, total, "Complete")

	lastMesh = {
		report = report,
		totals = totals,
		uid = currentUID,
		userName = userName,
		modelName = model.Name,
		when = os.time(),
	}

	readyForExport = true
	if btnExport then styleDDButton(btnExport, true) end

	Logger:Line(string.format(
		'<font color="#65d07d">Scan Complete.</font> <i>Asset-backed: %d, Unowned %%: %.1f%%</i>',
		totals.assetBacked or 0,
		(totals.assetBacked or 0) > 0 and (totals.unownedInstances or 0) / (totals.assetBacked) * 100 or 0
	))
	running = false
end

local function rbxUpload()
	ensureMainView()
	local model = nil
	if not model then
		logRT('<font color="#ff6b6b">Plugin feature not available yet.</font>')
		return
	end
	if not plugin then
		logRT('<font color="#ff6b6b">Upload requires running as a Studio plugin.</font>')
		return
	end

	local creatorId, ownerType = getPreferredUploadOwner()
	if creatorId == 0 then
		logRT('<font color="#ff6b6b">Could not resolve upload owner (CreatorId=0).</font>')
		return
	end

	local toUpload = model:Clone()
	toUpload.Name = model.Name
	toUpload.Parent = nil

	local safeName = (ScanCore.safeModelFilename and ScanCore.safeModelFilename(model.Name)) or model.Name
	local req = {
		Name = ("Palantir_%s"):format(safeName),
		Description = ("Uploaded via Palantir - Source place: %s - OwnerType: %s")
			:format(game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name, ownerType),
		CreatorId = creatorId,
	}

	logRT(string.format('<font color="#a992ff"><b>Uploading...</b></font> <i>%s</i> -> <b>%s</b> (%d)',
		model.Name, ownerType, creatorId))

	local ok, res1, res2 = pcall(function()
		return AssetService:CreateAssetAsync(toUpload, Enum.AssetType.Model, req)
	end)

	if not ok then
		logRT('<font color="#ff6b6b">Upload failed:</font> ' .. tostring(res1))
		warn("Upload Failed: " .. tostring(res1))
		return
	end

	local assetId = tonumber(res2) or tonumber(res1 and res1.AssetId)
	if assetId and assetId > 0 then
		logRT(string.format('<font color="#65d07d">Uploaded.</font> <i>Asset ID:</i> %d', assetId))
	else
		logRT('<font color="#ffd27f">Upload completed but no asset ID returned.</font>')
	end
end

local function securityScan()
	ensureMainView()
	local model = isModelSelected()
	if not model then logRT('<font color="#ff6b6b">Select a Model first.</font>'); return end
	logRT('<font color="#a992ff"><b>Running Security Scan...</b></font>')
	local ok, err = pcall(function()
		if ScanCore.SecurityScan then
			ScanCore.SecurityScan(model, Logger)
		elseif ScanCore.CodeScan then
			ScanCore.CodeScan(model, Logger)
		else
			error("ScanCore.SecurityScan function not found")
		end
	end)
	if not ok then
		logRT('<font color="#ff6b6b">Security scan error:</font> ' .. tostring(err))
		warn("Palantir SecurityScan error:", err)
	end
end

local function exportToServer()
	ensureMainView()
	if running then
		Logger:Line('<font color="#ffd27f">A mesh check is still running.</font> Please wait for it to finish.')
		return
	end
	if not readyForExport or not lastMesh then
		Logger:Line('<font color="#ff6b6b">Nothing fresh to export.</font> Run a mesh check first.')
		return
	end
	if WEBHOOK_URL == "" then
		Logger:Line('<font color="#ff6b6b">Missing WEBHOOK_URL.</font> Set it in Bootstrapper.lua.')
		return
	end

	Logger:Line('<font color="#a992ff"><b>Exporting to Discord...</b></font>')
	local ok, resp = Exporter.PostToDiscord(
		WEBHOOK_URL,
		ScanCore.safeModelFilename(lastMesh.modelName),
		lastMesh.uid,
		lastMesh.userName,
		lastMesh.totals,
		lastMesh.report
	)
	if ok then
		Logger:Line('<font color="#65d07d">Exported.</font>')
	else
		local msg = typeof(resp) == "table" and (tostring(resp.StatusCode) .. " " .. (resp.StatusMessage or "")) or tostring(resp)
		Logger:Line('<font color="#ff6b6b">Export failed:</font> ' .. msg)
	end
end

local function ensureOwnerKey()
	if RegistryMod.OwnerKey and RegistryMod.OwnerKey ~= "" then
		return true
	end

	local displayName = getOwnerDisplayName()
	local ok, resp = RegistryMod.createOwner(displayName)
	if not ok or not resp then
		logRT('<font color="#ff6b6b">Failed to create owner.</font>')
		return false
	end
	if resp.owner_key then
		setOwnerKey(resp.owner_key)
		logRT('<font color="#65d07d">Owner key saved.</font>')
		return true
	end
	return false
end

local function registerSelectedModel()
	local model = isModelSelected()
	if not model then
		logRT('<font color="#ff6b6b">Select a Model first.</font>')
		return
	end
	if not ensureOwnerKey() then
		return
	end

	local okValidate, result = pcall(function()
		if RegValidate and RegValidate.validateRegistration then
			return RegValidate.validateRegistration(model, getOwnerDisplayName(), {})
		end
		return { eligible = true }
	end)

	if okValidate and result and result.eligible == false then
		logRT('<font color="#ff6b6b">Registration blocked:</font> ' .. tostring(result.message or "Invalid model."))
		return
	end

	local parsed, err = RegistryMod.ParseModel(model)
	if not parsed then
		logRT('<font color="#ff6b6b">Failed to parse model:</font> ' .. tostring(err))
		return
	end

	local ok, resp = RegistryMod.registerModel(parsed.name, nil, parsed)
	if not ok or not resp or not resp.model then
		logRT('<font color="#ff6b6b">Model registration failed.</font>')
		return
	end

	setModelId(resp.model.id)
	logRT('<font color="#65d07d">Model registered.</font>')

	local meshes = {}
	for _, mesh in ipairs(parsed.meshes or {}) do
		table.insert(meshes, {
			mesh_asset_id = mesh.assetId,
			mesh_name = mesh.name,
		})
	end
	if #meshes > 0 then
		RegistryMod.upsertModelMeshes(meshes)
	end

	refreshRegistryView()
	openRegisterPopup()
end

local function submitWhitelist()
	if not RegistryMod.ModelId then
		logRT('<font color="#ff6b6b">Register a model first.</font>')
		return
	end

	local ids = parseWhitelistInput(whitelistInput.Text)
	if #ids == 0 then
		logRT('<font color="#ff6b6b">No valid user IDs found.</font>')
		return
	end

	local ok, resp = RegistryMod.whitelistAddMany(ids, nil)
	if ok then
		logRT('<font color="#65d07d">Whitelist updated.</font>')
		whitelistInput.Text = ""
		refreshRegistryView()
	else
		logRT('<font color="#ff6b6b">Whitelist update failed.</font>')
	end
end

-- dropdown clicks
btnMesh.MouseButton1Click:Connect(function()
	if not isModelSelected() then return end
	openUserPopup()
end)
btnSec.MouseButton1Click:Connect(function()
	if not isModelSelected() then return end
	closeAllDropdowns()
	securityScan()
end)
btnExport.MouseButton1Click:Connect(function()
	closeAllDropdowns()
	exportToServer()
end)
btnUpload.MouseButton1Click:Connect(function()
	closeAllDropdowns()
	rbxUpload()
end)

btnSubmit.MouseButton1Click:Connect(function()
	meshCheck()
	closePopup()
end)

popClose.MouseButton1Click:Connect(function()
	closePopup()
end)

clearBtn.MouseButton1Click:Connect(function()
	Logger:Clear()
end)

Dash_SwapDash.MouseButton1Click:Connect(function()
	setActiveDashboard("Group_Dashboard")
	refreshRegistryView()
end)

gDash_SwapDash.MouseButton1Click:Connect(function()
	setActiveDashboard("Dashboard")
	refreshRegistryView()
end)

Dash_RegMod.MouseButton1Click:Connect(function()
	registerSelectedModel()
end)

gDash_RegMod.MouseButton1Click:Connect(function()
	registerSelectedModel()
end)

regSubmit.MouseButton1Click:Connect(function()
	submitWhitelist()
	closeRegisterPopup()
end)

-- ===== Keybinds (robust ctrl chord) =====
local function ctrlDown()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.E and ctrlDown() then
		ensureMainView()
		securityScan()
	elseif input.KeyCode == Enum.KeyCode.Q and ctrlDown() then
		ensureMainView()
		openUserPopup()
	elseif input.KeyCode == Enum.KeyCode.KeypadZero then
		ensureMainView()
		exportToServer()
	elseif input.KeyCode == Enum.KeyCode.KeypadNine then
		ensureMainView()
		rbxUpload()
	end
end)

local cuid, typeU, guid, gtpe = getPreferredUploadOwner()

setupDashboards(cuid, typeU, guid, gtpe)
setActiveView("main")
setTabSelected(tab_Registry, false)
SelectedTabBtn = nil

logRT('<font color="#8aa0ff">Palantir Services : Loaded Successfully.</font>')
