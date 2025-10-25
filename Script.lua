-- this is the RPG gear module (used for gears with RPG class) 
local rpg = {}
rpg.__index = rpg -- allow for inheriting methods 

--services & misc
local serverStorage = game:GetService("ServerStorage")
local replicatedStorage = game:GetService("ReplicatedStorage")
local trails = serverStorage:FindFirstChild("Trails") -- folder containing trail particle fx
local debris = game:GetService("Debris")
local runService = game:GetService("RunService")
local serverScript = game:GetService("ServerScriptService")
local explosion = require(serverScript.Modules.ToolFunctions.Explosion) -- explosion module

--default properties table - used when specific gear settings module doesnt define a value
local defaultProperties = {
    ["Radius"] = 10.5, -- explosion radius in studs
    ["CoinMultiplier"] = 1, -- coin multiplier (1 coin per brick by default)
    ["DespawnTime"] = 30, -- time in seconds before rocket despawns if it doesnt hit a part
    ["Cooldown"] = 2, -- cooldown time in seconds between shots
    ["RocketSpeed"] = 70, -- speed of rocket projectile
    ["HoldAnimation"] = 8595069583, -- animation ID for holding the launcher
    ["FireAnimation"] = 8613888431, -- animation ID for firing the launcher
    ["Trail"] = trails.Default, -- default trail for rpg
    ["ExplosionSound"] = "Boom", -- name of explosion sound effect
    ["TravelingSound"] = "Swoosh", -- name of rocket traveling sound
    ["FireSound"] = "Fire", -- name of firing sound effect
    ["RocketsPerShot"] = 1, -- number of rockets fired per shot (2+ fires multiple rockets per click)
    ["ExplosionParticle"] = "Default", -- explosion particle effect name 
    ["ExplosionParticleEmit"] = 100, -- particle emit count for explosion (needed for some particles)
    ["RocketHiding"] = true, -- whether to hide rocket on the gear when rocket is fired
    ["ShotsBetweenCooldown"] = 0.5 -- delay in seconds between multiple rockets in one shot (if RocketsPerShot>1)
}

--handles explosion effects when a part is hit by the rocket
local function explosionOnHit(part, spawnPos)
    local joint -- stores the first joint found on the part
    
    for _, v in pairs(part:GetJoints()) do  -- iterate through all joints connected to the part
        if joint == nil then -- check if nil
            joint = v -- store first joint for later use
        end
        
        debris:AddItem(v, 0.1) -- remove joint after 0.1 seconds
    end
    
    local function applyPartVelocity() -- applies fling force to parts
        local blastForce = Instance.new('BodyForce') -- creates force object to move part
        
        -- calculate force direction from explosion to part, multiply by mass and random factors
        local force = ((spawnPos - part.Position)).unit * 650 * part:GetMass() * Vector3.new(
            math.random(1, 2) * math.random(1.111, 2.999), -- random X force multiplier
            math.random(1, 2) * math.random(1.111, 2.999), -- random Y force multiplier
            math.random(1, 2) * math.random(1.111, 2.999)  -- random Z force multiplier
        )
        
        blastForce.Force = -force -- negate force to push away from explosion
        blastForce.Parent = part -- apply force to the part
        
        debris:AddItem(blastForce, 0.1) -- remove force after 0.1 seconds
    end
    
    -- check if joint exists before setting up connection
    if joint ~= nil then
        -- apply velocity when the joint is destroyed
        joint.Destroying:Connect(function()
            applyPartVelocity() -- apply velocity
        end)
    else
        -- if no joint exists, apply velocity immediately
        applyPartVelocity()
    end
end

-- creates a new rpg tool instance with necessary properties and methods
function rpg.new(settings, tool, plr)
    assert(settings, "Settings provided for tool are nil") -- ensure settings exist
    settings = require(settings) -- load the settings module
    
    local self = setmetatable({
        ToolObject = tool, -- reference to the tool object
        Settings = settings, -- reference to settings table
        Player = plr, -- reference to player who owns tool
        _explosionCache = {}, -- cache for explosion particles (optimization)
        _soundCache = {}, -- cache for sound objects (optimization)
        _activeRockets = {} -- table to track active rockets
    }, rpg)
    
    -- copy all properties from settings to self
    for i, v in pairs(settings.Properties) do
        self[i] = v -- assign each property to self
    end
    
    -- fill in any missing properties with defaults
    for i, v in pairs(defaultProperties) do
        if self[i] == nil then -- check if property wasn't defined in settings
            self[i] = v -- use default value
        end
    end
    
    -- validate required properties exist
    assert(self.Rocket, "No rocket instance in tool defined") -- rocket model must exist
    assert(serverStorage.Explosions:FindFirstChild(self.ExplosionParticle), "Explosion particle not found") -- explosion effect must exist
    
    -- create the real rocket model that will be cloned when firing
    if self.Rocket:IsA("Part") and not self.Rocket:FindFirstChildWhichIsA("SpecialMesh") then
        -- if rocket is a simple Part without mesh, clone it directly
        -- some rockets are parts, some are parts with meshes like the default rpg
        self.RealRocket = self.Rocket:Clone()
    else
        -- if rocket is a MeshPart or has mesh, create a new part with mesh inside
        self.RealRocket = Instance.new("Part") -- create new part
        self.RealRocket.Size = self.Rocket.Size -- copy size
        self.RealRocket.Color = self.Rocket.Color -- copy color
        self.RealRocket.Name = "Rocket" -- set name
        
        local rocketMesh = Instance.new("SpecialMesh") -- create mesh object
        -- get mesh id from MeshPart or existing SpecialMesh
        rocketMesh.MeshId = self.Rocket:IsA("MeshPart") and self.Rocket.MeshId or 
                           self.Rocket:FindFirstChildWhichIsA("SpecialMesh") and 
                           self.Rocket:FindFirstChildWhichIsA("SpecialMesh").MeshId
        -- get texture id from MeshPart or existing SpecialMesh
        rocketMesh.TextureId = self.Rocket:IsA("MeshPart") and self.Rocket.TextureID or 
                              self.Rocket:FindFirstChildWhichIsA("SpecialMesh") and 
                              self.Rocket:FindFirstChildWhichIsA("SpecialMesh").TextureId
        rocketMesh.Parent = self.RealRocket -- attach mesh to part
    end
    
    -- add trail effect if specified
    if self.Trail ~= "None" then -- check if trail is enabled
        local trail = trails:FindFirstChild(self.Trail).Attachment:Clone() -- clone trail attachment
        
        trail.Parent = self.RealRocket -- attach trail to rocket
        trail.WorldPosition = self.RealRocket.Position - self.RealRocket.CFrame.LookVector -- position trail behind rocket
    end
    
    return self -- return initialized instance
end

function rpg:CreateRocket() -- creates a rocket instance
    local newRocket = self.RealRocket:Clone() -- clone the base rocket model
    newRocket:SetAttribute("Rocket", true) -- mark as rocket for collision detection
    newRocket.CanCollide = false -- disable collision initially
    
    -- remove all welds from rocket to prevent issues
    for _, v in ipairs(newRocket:GetDescendants()) do
        if v:IsA("Weld") or v:IsA("WeldConstraint") then -- check if descendant is a weld
            v:Destroy() -- destroy the weld
        end
    end
    
    newRocket.Transparency = 0 -- make rocket visible
    
    return newRocket -- return configured rocket
end

function rpg:SetupRocketSounds(newRocket) -- set up sound effects for rocket
    local travelSound -- sound that plays while rocket travels
    local explosionSound -- sound that plays on explosion
    
    -- setup traveling sound if specified
    if self.TravelingSound then -- check if traveling sound is enabled
        travelSound = self.ToolObject:FindFirstChild(self.TravelingSound):Clone() -- clone sound from tool
        travelSound.Parent = newRocket -- attach to rocket
        travelSound:Play() -- start playing immediately
    end
    
    -- setup explosion sound if specified
    if self.ExplosionSound then -- check if explosion sound is enabled
        explosionSound = self.ToolObject:FindFirstChild(self.ExplosionSound):Clone() -- clone sound from tool
        explosionSound.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.15 -- randomize pitch slightly (between 0.925 and 1.075)
        explosionSound.PlayOnRemove = true -- sound plays when destroyed
        explosionSound.Parent = newRocket -- attach to rocket
    end
    
    return travelSound, explosionSound -- return both sound objects
end

function rpg:SetupCollisionDetection(newRocket, travelSound, explosionSound) -- handles rocket collision, detection. and explosion
    local exploded = false -- flag to prevent multiple explosions
    
    -- connect to heartbeat for collision detection every frame
    local connection = runService.Heartbeat:Connect(function()
        if newRocket ~= nil and not exploded then -- check rocket exists and hasn't exploded
            -- get all parts intersecting with rocket
            for _, hit in ipairs(workspace:GetPartsInPart(newRocket)) do
                -- check if hit part is valid target (not self, not another rocket, not debris)
                if not hit:IsDescendantOf(self.ToolObject.Parent) and -- not part of player
                   not exploded and -- hasnt already exploded
                   not hit:GetAttribute("Rocket") and -- not another rocket
                   not hit:IsDescendantOf(workspace.Debris) then -- not in debris folder
                    
                    exploded = true -- set explosion flag
                    
                    if travelSound then -- check if travel sound exists
                        travelSound:Stop() -- stop the traveling sound
                    end
                    
                    -- create explosion at rocket position
                    explosion.new(
                        newRocket.CFrame, -- explosion position and rotation
                        self.Radius, -- explosion radius
                        serverStorage.Explosions:FindFirstChild(self.ExplosionParticle):Clone(), -- particle effect
                        self.ExplosionParticleEmit, -- number of particles
                        explosionOnHit, -- callback function for hit parts
                        self.Settings, -- settings reference
                        self.Player, -- player reference
                        self.CustomTween -- custom tween settings if any
                    )
                    
                    newRocket.Anchored = true -- anchor rocket in place
                    newRocket.Transparency = 1 -- make rocket invisible
                    
                    if explosionSound then -- check if explosion sound exists
                        explosionSound:Destroy() -- destroy sound (won't play due to PlayOnRemove being overridden)
                    end
                    
                    local lifetime = 0 -- total lifetime of all particle effects
                    
                    -- disable particle emitters and calculate total lifetime
                    for _, v in ipairs(newRocket:GetDescendants()) do
                        if v:IsA("ParticleEmitter") then -- check if descendant is particle emitter
                            v.Enabled = false -- stop emitting new particles
                            lifetime += v.Lifetime.Max -- add max lifetime to total
                        end
                    end
                    
                    debris:AddItem(newRocket, lifetime) -- schedule rocket removal after particles finish
                end
            end
        else
            connection:Disconnect() -- disconnect when rocket is gone or exploded
        end
    end)
    
    return connection -- return connection for cleanup
end

function rpg:Fire(mousePos) -- fires towards mouse pos
    -- check if tool is not on cooldown and mousePos is valid
    if not self.ToolObject:GetAttribute("Cooldown") and mousePos then
        self.ToolObject:SetAttribute("Cooldown", true) -- set cooldown flag
        
        -- spawn new thread
        task.spawn(function()
            -- fire multiple rockets if RocketsPerShot > 1
            for i = 1, self.RocketsPerShot do
                local newRocket = self:CreateRocket() -- create rocket
                
                -- set rocket position (use Offset if defined, otherwise use Rocket position)
                newRocket.Position = self.Offset or self.Rocket.Position
                
                -- hide original rocket model if RocketHiding is enabled
                if self.RocketHiding then
                    self.Rocket.Transparency = 1 -- make original rocket invisible
                end
                
                local travelSound, explosionSound = self:SetupRocketSounds(newRocket) -- setup sound effects
                
                -- aim rocket towards mouse position
                newRocket.CFrame = CFrame.new(self.Rocket.Position, mousePos) -- create cframe looking at target
                newRocket.Position = newRocket.Position + newRocket.CFrame.LookVector -- move rocket forward slightly
                
                -- play firing sound if it exists
                local fireSound = self.ToolObject:FindFirstChild(self.FireSound)
                if fireSound ~= nil then -- check if fire sound exists
                    fireSound.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.15 -- randomize pitch slightly
                    fireSound:Play() -- play the sound
                end
                
                -- setup antigravity force so rocket travels straight
                local bodyForce = Instance.new("BodyForce") -- create force object
                bodyForce.Name = "Antigravity" -- name for identification
                bodyForce.Force = Vector3.new(0, newRocket:GetMass() * workspace.Gravity, 0) -- counteract gravity
                bodyForce.Parent = newRocket -- attach to rocket
                
                newRocket.Parent = workspace -- add rocket to workspace
                newRocket:SetNetworkOwner(nil) -- set network ownership to server for physics
                
                -- apply velocity to rocket in forward direction
                newRocket.AssemblyLinearVelocity = newRocket.CFrame.LookVector * self.RocketSpeed
                
                debris:AddItem(newRocket, self.DespawnTime) -- remove rocket after DespawnTime seconds
                
                -- setup collision detection for this rocket
                self:SetupCollisionDetection(newRocket, travelSound, explosionSound)
                
                -- wait before firing next rocket (for multi shot rpgs)
                task.wait(self.ShotsBetweenCooldown)
            end
            
            -- start cooldown timer in separate thread
            task.spawn(function()
                task.wait(self.Cooldown) -- wait for cooldown duration
                
                -- restore original rocket visibility if RocketHiding is enabled
                if self.RocketHiding then
                    self.Rocket.Transparency = 0 -- make rocket visible again
                end
                
                self.ToolObject:SetAttribute("Cooldown", false) -- remove cooldown flag
            end)
        end)
    end
end

function rpg:Cleanup() -- cleanup to disconnect all active connections
    for _, rocketData in pairs(self._activeRockets) do
        if rocketData.connection then -- check if connection exists
            rocketData.connection:Disconnect() -- disconnect the connection
        end
    end
    
    self._activeRockets = {} -- clear active rockets table
end

return rpg
