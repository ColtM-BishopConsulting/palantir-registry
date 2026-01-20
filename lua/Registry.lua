-- Registry.lua
-- Client for the Palantir registry server

local HttpService = game:GetService("HttpService")
local Registry = {}
Registry.API_URL = "" -- set via Registry.setup({ apiUrl = "..." })
Registry.OwnerKey = nil
Registry.ModelId = nil

-- ============ SETUP ============

function Registry.setup(cfg)
	cfg = cfg or {}
	if cfg.apiUrl then
		Registry.API_URL = cfg.apiUrl
	end
	if cfg.ownerKey then
		Registry.OwnerKey = cfg.ownerKey
	end
	if cfg.modelId then
		Registry.ModelId = cfg.modelId
	end
end

-- ============ UTILITY FUNCTIONS ============

local function parseAssetId(idString)
	if not idString or idString == "" then return nil end
	local id = tostring(idString):match("%d+")
	return id and tonumber(id) or nil
end

local function getPath(instance, root)
	local parts = {}
	local current = instance
	while current and current ~= root and current.Parent do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

local function generateFingerprint(meshIds)
	table.sort(meshIds)
	local str = table.concat(meshIds, "-")
	local hash = 0
	for i = 1, #str do
		hash = (hash * 31 + string.byte(str, i)) % 2147483647
	end
	return tostring(hash)
end

local function buildQuery(params)
	if not params then return "" end
	local parts = {}
	for key, value in pairs(params) do
		if value ~= nil then
			local encoded = HttpService:UrlEncode(tostring(value))
			table.insert(parts, key .. "=" .. encoded)
		end
	end
	if #parts == 0 then return "" end
	return "?" .. table.concat(parts, "&")
end

local function request(method, endpoint, data, query)
	local url = Registry.API_URL .. endpoint .. buildQuery(query)
	local body = data and HttpService:JSONEncode(data) or nil

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = method,
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
	end

	return false, {
		statusCode = response.StatusCode,
		statusMessage = response.StatusMessage,
		body = response.Body,
	}
end

local function post(endpoint, data)
	return request("POST", endpoint, data)
end

local function get(endpoint, query)
	return request("GET", endpoint, nil, query)
end

local function ownerBody(data)
	data = data or {}
	data.owner_key = data.owner_key or Registry.OwnerKey
	return data
end

-- ============ DATA EXTRACTION ============

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
			if not meshIds[meshId] then
				meshIds[meshId] = true
				table.insert(meshes, meshData)
			end
		end
	end

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
			for _, child in ipairs(inst:GetDescendants()) do
				local childId = nil
				if child:IsA("MeshPart") then
					childId = parseAssetId(child.MeshId)
				elseif child:IsA("SpecialMesh") then
					childId = parseAssetId(child.MeshId)
				end
				if childId and not seen[childId] then
					seen[childId] = true
					local parsed = Registry.ParseMeshes({ child })
					for _, m in ipairs(parsed) do
						table.insert(meshes, m)
					end
				end
			end
		end
	end

	return meshes
end

function Registry.collectMeshIdsFromModel(model)
	local ids = {}
	local seen = {}

	if not model or not model:IsA("Model") then
		return ids
	end

	for _, inst in ipairs(model:GetDescendants()) do
		local meshId = nil
		if inst:IsA("MeshPart") then
			meshId = parseAssetId(inst.MeshId)
		elseif inst:IsA("SpecialMesh") then
			meshId = parseAssetId(inst.MeshId)
		end

		if meshId and not seen[meshId] then
			seen[meshId] = true
			table.insert(ids, meshId)
		end
	end

	return ids
end

-- ============ API CALLS ============

function Registry.createOwner(displayName)
	return post("/owner/create", {
		display_name = displayName,
	})
end

function Registry.rotateOwnerKey(ownerId, oldKey)
	return post("/owner/rotate-key", {
		owner_key = oldKey or Registry.OwnerKey,
		owner_id = ownerId,
	})
end

function Registry.registerModel(displayName, robloxAssetId, meshCount, fingerprint)
	local payload = ownerBody({
		display_name = displayName,
		roblox_asset_id = robloxAssetId,
	})

	if type(meshCount) == "table" then
		payload.mesh_count = meshCount.meshCount or meshCount.mesh_count
		payload.fingerprint = meshCount.fingerprint
	else
		payload.mesh_count = meshCount
		payload.fingerprint = fingerprint
	end

	return post("/model/register", payload)
end

function Registry.whitelistAdd(userId, note)
	return post("/whitelist/add", ownerBody({
		model_id = Registry.ModelId,
		user_id = userId,
		note = note,
	}))
end

function Registry.whitelistAddMany(userIds, note)
	return post("/whitelist/add-many", ownerBody({
		model_id = Registry.ModelId,
		user_ids = userIds,
		note = note,
	}))
end

function Registry.whitelistRemove(userId)
	return post("/whitelist/remove", ownerBody({
		model_id = Registry.ModelId,
		user_id = userId,
	}))
end

function Registry.upsertModelMeshes(meshList)
	return post("/meshes/upsert", ownerBody({
		model_id = Registry.ModelId,
		meshes = meshList,
	}))
end

function Registry.checkAccessAndLog(actorUserId, meshIds, meta)
	meta = meta or {}
	local payload = {
		model_id = Registry.ModelId,
		actor_user_id = actorUserId,
		mesh_ids = meshIds,
		meta = meta,
		place_id = meta.place_id or meta.placeId,
		server_job_id = meta.server_job_id or meta.serverJobId,
	}

	return post("/access/check", payload)
end

function Registry.listUsageLogs(modelId, opts)
	opts = opts or {}
	return get("/usage-logs/" .. tostring(modelId), {
		owner_key = Registry.OwnerKey,
		page = opts.page,
		page_size = opts.page_size or opts.pageSize,
	})
end

function Registry.getStats(modelId)
	return get("/stats/" .. tostring(modelId), {
		owner_key = Registry.OwnerKey,
	})
end

return Registry
