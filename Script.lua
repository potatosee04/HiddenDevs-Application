--This is the rpg module. For any gear with the rpg type, this is the module that will be used.
--This is used for the default rocket launcher (1 in hotbar). Uou may have to wait for the map to load to use it.
 
local rpg = {}
rpg.__index = rpg
 
local serverStorage = game:GetService("ServerStorage")
local replicatedStorage = game:GetService("ReplicatedStorage")
local trails = serverStorage:FindFirstChild("Trails")
local debris = game:GetService("Debris")
local runService = game:GetService("RunService")
local serverScript = game:GetService("ServerScriptService")
local explosion = require(serverScript.Modules.ToolFunctions.Explosion)
 
local defaultProperties = { --Properties of the default rpg if not specified by specific gear Settings module.
    ["Radius"] = 10.5,
    ["CoinMultiplier"] = 1,
    ["DespawnTime"] = 30,
    ["Cooldown"] = 2,
    ["RocketSpeed"] = 70,
    ["HoldAnimation"] = 8595069583,
    ["FireAnimation"] = 8613888431,
    ["Trail"] = trails.Default,
    ["ExplosionSound"] = "Boom",
    ["TravelingSound"] = "Swoosh",
    ["FireSound"] = "Fire",
    ["RocketsPerShot"] = 1,
    ["ExplosionParticle"] = "Default",
    ["ExplosionParticleEmit"] = 100,
    ["RocketHiding"] = true,
    ["ShotsBetweenCooldown"] = 0.5
}
 
local function explosionOnHit(part : Part, spawnPos) --function for explosions if a part is hit
    local joint
 
    for _,v in pairs(part:GetJoints()) do -- remove joints
        if joint == nil then
            joint = v
        end
 
        debris:AddItem(v, 0.1)
    end
 
    local function applyPartVelocity() -- fling parts when exploded
        local blastForce = Instance.new('BodyForce')
        local force = ((spawnPos - part.Position)).unit * 650 * part:GetMass() * Vector3.new(math.random(1,2) * math.random(1.111, 2.999), math.random(1,2) * math.random(1.111, 2.999), math.random(1,2) * math.random(1.111, 2.999))
 
        blastForce.Force = -force
        blastForce.Parent = part
 
        debris:AddItem(blastForce, 0.1)
    end
 
    if joint ~= nil then
        joint.Destroying:Connect(function()
            applyPartVelocity()
        end)
    else
        applyPartVelocity()
    end
end
 
function rpg.new(settings : ModuleScript, tool : Tool, plr : Player) --new rpg tool
    assert(settings, "Settings provided for tool are nil")
    settings = require(settings)
 
    local self = setmetatable({
        ToolObject = tool,
        Settings = settings,
        Player = plr
    }, rpg)
 
    for i,v in pairs(settings.Properties) do
        self[i] = v
    end
 
    for i,v in pairs(defaultProperties) do
        if self[i] == nil then
            self[i] = v
        end
    end
 
    assert(self.Rocket, "No rocket instance in tool defined")
    assert(serverStorage.Explosions:FindFirstChild(self.ExplosionParticle), "Explosion particle not found")
 
    if self.Rocket:IsA("Part") and not self.Rocket:FindFirstChildWhichIsA("SpecialMesh") then
        self.RealRocket = self.Rocket:Clone()
    else
        self.RealRocket = Instance.new("Part")
        self.RealRocket.Size = self.Rocket.Size
        self.RealRocket.Color = self.Rocket.Color
        self.RealRocket.Name = "Rocket"
        
        local rocketMesh = Instance.new("SpecialMesh")
        rocketMesh.MeshId = self.Rocket:IsA("MeshPart") and self.Rocket.MeshId or self.Rocket:FindFirstChildWhichIsA("SpecialMesh") and self.Rocket:FindFirstChildWhichIsA("SpecialMesh").MeshId
        rocketMesh.TextureId = self.Rocket:IsA("MeshPart") and self.Rocket.TextureID or self.Rocket:FindFirstChildWhichIsA("SpecialMesh") and self.Rocket:FindFirstChildWhichIsA("SpecialMesh").TextureId
        rocketMesh.Parent = self.RealRocket
    end
    
    if self.Trail ~= "None" then
        local trail = trails:FindFirstChild(self.Trail).Attachment:Clone()
 
        trail.Parent = self.RealRocket
        trail.WorldPosition = self.RealRocket.Position - self.RealRocket.CFrame.LookVector
    end
 
    return self
end
 
function rpg:Fire(mousePos) -- fire rpg
    if not self.ToolObject:GetAttribute("Cooldown") and mousePos then
        self.ToolObject:SetAttribute("Cooldown", true)
 
        --if self.RocketsPerShot > 1 then
        --  self.Cooldown += 0.5 * self.RocketsPerShot
        --end
 
        task.spawn(function()
            for i = 1, self.RocketsPerShot do
                local newRocket : Part = self.RealRocket:Clone()
                newRocket:SetAttribute("Rocket", true)
                newRocket.CanCollide = false
 
                for _,v in pairs(newRocket:GetDescendants()) do
                    if v:IsA("Weld") or v:IsA("WeldConstraint") then
                        v:Destroy()
                    end
                end
                
                newRocket.Transparency = 0
                newRocket.Position = self.Offset or self.Rocket.Position
                if self.RocketHiding then
                    self.Rocket.Transparency = 1
                end
                
                local travelSound
                
                if self.TravelingSound then
                    travelSound = self.ToolObject:FindFirstChild(self.TravelingSound):Clone()
                    travelSound.Parent = newRocket
                    travelSound:Play()
                end
                
                local explosionSound
                
                if self.ExplosionSound then
                    explosionSound = self.ToolObject:FindFirstChild(self.ExplosionSound):Clone()
                    explosionSound.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.15
                    explosionSound.PlayOnRemove = true
                    explosionSound.Parent = newRocket
                end
 
                newRocket.CFrame = CFrame.new(self.Rocket.Position, mousePos)
                newRocket.Position = newRocket.Position + newRocket.CFrame.LookVector --* Vector3.new(5, 1, 5)
                
                local fireSound = self.ToolObject:FindFirstChild(self.FireSound)
                
                if fireSound ~= nil then
                    fireSound.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.15
                    fireSound:Play()
                end
 
                local bodyForce = Instance.new("BodyForce")
                bodyForce.Name = "Antigravity"
                bodyForce.Force = Vector3.new(0, newRocket:GetMass() * workspace.Gravity, 0)
                bodyForce.Parent = newRocket
                newRocket.Parent = workspace
                newRocket:SetNetworkOwner(nil)
 
                newRocket.AssemblyLinearVelocity = newRocket.CFrame.LookVector * self.RocketSpeed
 
                debris:AddItem(newRocket, self.DespawnTime)
 
                local collisionListener = {}
                local exploded = false
 
                collisionListener.collisionDetector = runService.Heartbeat:Connect(function()
                    if newRocket ~= nil and not exploded then
                        for _, hit in pairs(workspace:GetPartsInPart(newRocket)) do
                            if not hit:IsDescendantOf(self.ToolObject.Parent) and not exploded and not hit:GetAttribute("Rocket") and not hit:IsDescendantOf(workspace.Debris) then
                                exploded = true
                                travelSound:Stop()
 
                                explosion.new(newRocket.CFrame, self.Radius, serverStorage.Explosions:FindFirstChild(self.ExplosionParticle):Clone(), self.ExplosionParticleEmit, explosionOnHit, self.Settings, self.Player, self.CustomTween)
 
                                newRocket.Anchored = true
                                newRocket.Transparency = 1
                                    
                                explosionSound:Destroy()
                                local lifetime = 0
 
                                for _,v in pairs(newRocket:GetDescendants()) do
                                    if v:IsA("ParticleEmitter") then
                                        v.Enabled = false
                                        lifetime += v.Lifetime.Max
                                    end
                                end
 
                                debris:AddItem(newRocket, lifetime)
                            end
                        end
                    else
                        collisionListener.collisionDetector:Disconnect()
                    end
                end)
                task.wait(self.ShotsBetweenCooldown)
            end
            
            task.spawn(function()
                task.wait(self.Cooldown)
                if self.RocketHiding then
                    self.Rocket.Transparency = 0
                end
                
                self.ToolObject:SetAttribute("Cooldown", false)
            end)
        end)
    end
end
 
return rpg
