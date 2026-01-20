-- Registry.lua
-- Handles asset registration with the Palantir server

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")

local Registry = {}
Registry.API_URL = "YOUR_VERCEL_URL_HERE" -- e.g., "https://palantir-registry.vercel.app"

-- ============ UTILITY FUNCTIONS ============

-- Extract numeric asset ID from various formats
local function parseAssetId(idString)
	if not idString or idString == "" then return nil end
	-- Handle "rbxassetid://12345" or just "12345"
	local id = tostring(idString):match("%d+")
	return id and tonumber(id) or nil
end

-- Get full hierarchy path of an instance
local function getPath(instance, root)
	local parts = {}
	local current = instance
	while current and current ~= root and current.Parent do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

-- Generate a fingerprint for a model (for quick identification)
local function generateFingerprint(meshIds)
	-- Simple hash: sorted asset IDs concatenated
	table.sort(meshIds)
	local str = table.concat(meshIds, "-")
	-- Basic hash (could use a proper hash function if needed)
	local hash = 0
	for i = 1, #str do
		hash = (hash * 31 + string.byte(str, i)) % 2147483647
	end
	return tostring(hash)
end

-- ============ DATA EXTRACTION ============

-- Extract all mesh data from a model
function Registry.ParseModel(model)
	if not model or not model:IsA("Model") then
		return nil, "Invalid model"
	end
	
	local meshes = {}
	local meshIds = {}
	
	for _, inst in ipairs(model:GetDescendants()) do
		local meshId, meshData = nil, nil
		
		if inst:IsA("MeshPart") then
			meshId = parseAssetId(inst.MeshId)
			if meshId then
				meshData = {
					assetId = meshId,
					name = inst.Name,
					path = getPath(inst, model),
					sizeX = inst.Size.X,
					sizeY = inst.Size.Y,
					sizeZ = inst.Size.Z,
					material = inst.Material.Name,
					textureId = parseAssetId(inst.TextureID),
				}
			end
		elseif inst:IsA("SpecialMesh") then
			meshId = parseAssetId(inst.MeshId)
			if meshId then
				local parent = inst.Parent
				meshData = {
					assetId = meshId,
					name = inst.Name .. " (in " .. (parent and parent.Name or "?") .. ")",
					path = getPath(inst, model),
					sizeX = inst.Scale.X,
					sizeY = inst.Scale.Y,
					sizeZ = inst.Scale.Z,
					material = parent and parent:IsA("BasePart") and parent.Material.Name or nil,
					textureId = parseAssetId(inst.TextureId),
				}
			end
		end
		
		if meshId and meshData then
			-- Dedupe by assetId (same mesh used multiple times)
			if not meshIds[meshId] then
				meshIds[meshId] = true
				table.insert(meshes, meshData)
			end
		end
	end
	
	-- Build asset ID list for fingerprint
	local idList = {}
	for id in pairs(meshIds) do
		table.insert(idList, id)
	end
	
	return {
		name = model.Name,
		meshCount = #meshes,
		meshes = meshes,
		fingerprint = generateFingerprint(idList),
	}
end

-- Extract data for individual mesh selection
function Registry.ParseMeshes(instances)
	local meshes = {}
	local seen = {}
	
	for _, inst in ipairs(instances) do
		local meshId, meshData = nil, nil
		
		if inst:IsA("MeshPart") then
			meshId = parseAssetId(inst.MeshId)
			if meshId and not seen[meshId] then
				seen[meshId] = true
				meshData = {
					assetId = meshId,
					name = inst.Name,
					sizeX = inst.Size.X,
					sizeY = inst.Size.Y,
					sizeZ = inst.Size.Z,
					material = inst.Material.Name,
					textureId = parseAssetId(inst.TextureID),
				}
				table.insert(meshes, meshData)
			end
		elseif inst:IsA("SpecialMesh") then
			meshId = parseAssetId(inst.MeshId)
			if meshId and not seen[meshId] then
				seen[meshId] = true
				local parent = inst.Parent
				meshData = {
					assetId = meshId,
					name = inst.Name,
					sizeX = inst.Scale.X,
					sizeY = inst.Scale.Y,
					sizeZ = inst.Scale.Z,
					material = parent and parent:IsA("BasePart") and parent.Material.Name or nil,
					textureId = parseAssetId(inst.TextureId),
				}
				table.insert(meshes, meshData)
			end
		elseif inst:IsA("Model") then
			-- Recursively get meshes from model
			for _, child in ipairs(inst:GetDescendants()) do
				local childId = nil
				if child:IsA("MeshPart") then
					childId = parseAssetId(child.MeshId)
				elseif child:IsA("SpecialMesh") then
					childId = parseAssetId(child.MeshId)
				end
				if childId and not seen[childId] then
					seen[childId] = true
					-- Recurse with single item
					local parsed = Registry.ParseMeshes({child})
					for _, m in ipairs(parsed) do
						table.insert(meshes, m)
					end
				end
			end
		end
	end
	
	return meshes
end

-- ============ API CALLS ============

-- POST request helper
local function post(endpoint, data)
	local url = Registry.API_URL .. endpoint
	local body = HttpService:JSONEncode(data)
	
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
	
	if not success then
		return false, { error = tostring(response) }
	end
	
	if response.Success then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		return true, ok and decoded or { raw = response.Body }
	else
		return false, { 
			statusCode = response.StatusCode, 
			statusMessage = response.StatusMessage,
			body = response.Body 
		}
	end
end

-- GET request helper
local function get(endpoint)
	local url = Registry.API_URL .. endpoint
	
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = { ["Content-Type"] = "application/json" },
		})
	end)
	
	if not success then
		return false, { error = tostring(response) }
	end
	
	if response.Success then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		return true, ok and decoded or { raw = response.Body }
	else
		return false, { 
			statusCode = response.StatusCode, 
			statusMessage = response.StatusMessage 
		}
	end
end

-- Register a full model
function Registry.RegisterModel(model, robloxUserId, robloxUsername)
	local modelData, err = Registry.ParseModel(model)
	if not modelData then
		return false, err
	end
	
	return post("/register/model", {
		robloxUserId = robloxUserId,
		robloxUsername = robloxUsername,
		model = modelData,
	})
end

-- Register individual meshes
function Registry.RegisterMeshes(meshes, robloxUserId, robloxUsername)
	if #meshes == 0 then
		return false, "No meshes to register"
	end
	
	return post("/register/mesh", {
		robloxUserId = robloxUserId,
		robloxUsername = robloxUsername,
		meshes = meshes,
	})
end

-- Check ownership of assets
function Registry.CheckOwnership(assetIds)
	return post("/check", {
		assetIds = assetIds,
	})
end

-- Get user's registered assets
function Registry.GetUserAssets(robloxUserId)
	return get("/user/" .. tostring(robloxUserId))
end

-- Log a scan
function Registry.LogScan(scannerUserId, modelName, assetIds, flaggedAssets)
	return post("/scan/log", {
		scannerUserId = scannerUserId,
		modelName = modelName,
		assetIds = assetIds,
		flaggedAssets = flaggedAssets or {},
	})
end

-- ============ HIGH-LEVEL FUNCTIONS ============

-- Register currently selected model
function Registry.RegisterSelected(robloxUserId, robloxUsername)
	local sel = Selection:Get()
	if #sel == 0 then
		return false, "Nothing selected"
	end
	
	local model = sel[1]
	if model:IsA("Model") then
		return Registry.RegisterModel(model, robloxUserId, robloxUsername)
	else
		-- Try to register as individual meshes
		local meshes = Registry.ParseMeshes(sel)
		if #meshes == 0 then
			return false, "No meshes found in selection"
		end
		return Registry.RegisterMeshes(meshes, robloxUserId, robloxUsername)
	end
end

-- Check selected model against registry
function Registry.CheckSelected()
	local sel = Selection:Get()
	if #sel == 0 then
		return false, "Nothing selected"
	end
	
	local meshes = {}
	local model = sel[1]
	
	if model:IsA("Model") then
		local parsed = Registry.ParseModel(model)
		if parsed then
			for _, m in ipairs(parsed.meshes) do
				table.insert(meshes, m.assetId)
			end
		end
	else
		local parsed = Registry.ParseMeshes(sel)
		for _, m in ipairs(parsed) do
			table.insert(meshes, m.assetId)
		end
	end
	
	if #meshes == 0 then
		return false, "No meshes found"
	end
	
	return Registry.CheckOwnership(meshes)
end

return Registry
