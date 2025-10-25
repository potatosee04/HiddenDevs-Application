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
    
    --[[
        Applies velocity to parts when they're exploded
        Creates a force that flings the part away from explosion center
    ]]
    local function applyPartVelocity()
        local blastForce = Instance.new('BodyForce') -- creates force object to move part
        -- Calculate force direction from explosion to part, multiply by mass and random factors
        local force = ((spawnPos - part.Position)).unit * 650 * part:GetMass() * Vector3.new(
            math.random(1, 2) * math.random(1.111, 2.999), -- random X force multiplier
            math.random(1, 2) * math.random(1.111, 2.999), -- random Y force multiplier
            math.random(1, 2) * math.random(1.111, 2.999)  -- random Z force multiplier
        )
        
        blastForce.Force = -force -- negate force to push away from explosion
        blastForce.Parent = part -- attach force to the part
        
        debris:AddItem(blastForce, 0.1) -- remove force after 0.1 seconds
    end
    
    -- Check if joint exists before setting up connection
    if joint ~= nil then
        -- Apply velocity when joint is destroyed (part breaks off)
        joint.Destroying:Connect(function()
            applyPartVelocity() -- call velocity application function
        end)
    else
        -- If no joint exists, apply velocity immediately
        applyPartVelocity()
    end
end

--[[
    Creates a new RPG tool instance with all necessary properties and methods
    @param settings - ModuleScript containing gear-specific settings
    @param tool - The Tool object that represents this weapon
    @param plr - The Player who owns this tool
    @return self - New RPG instance with all properties initialized
]]
function rpg.new(settings, tool, plr)
    assert(settings, "Settings provided for tool are nil") -- ensure settings exist
    settings = require(settings) -- load the settings module
    
    -- Create new instance with metatable inheritance
    local self = setmetatable({
        ToolObject = tool, -- reference to the tool object
        Settings = settings, -- reference to settings table
        Player = plr, -- reference to player who owns tool
        _explosionCache = {}, -- cache for explosion particles (optimization)
        _soundCache = {}, -- cache for sound objects (optimization)
        _activeRockets = {} -- table to track active rockets
    }, rpg)
    
    -- Copy all properties from settings to self
    for i, v in pairs(settings.Properties) do -- pairs used for dictionary iteration
        self[i] = v -- assign each property to self
    end
    
    -- Fill in any missing properties with defaults
    for i, v in pairs(defaultProperties) do -- pairs used for dictionary iteration
        if self[i] == nil then -- check if property wasn't defined in settings
            self[i] = v -- use default value
        end
    end
    
    -- Validate required properties exist
    assert(self.Rocket, "No rocket instance in tool defined") -- rocket model must exist
    assert(serverStorage.Explosions:FindFirstChild(self.ExplosionParticle), "Explosion particle not found") -- explosion effect must exist
    
    -- Create the real rocket model that will be cloned when firing
    if self.Rocket:IsA("Part") and not self.Rocket:FindFirstChildWhichIsA("SpecialMesh") then
        -- If rocket is a simple Part without mesh, clone it directly
        self.RealRocket = self.Rocket:Clone()
    else
        -- If rocket is MeshPart or has mesh, create new Part with mesh
        self.RealRocket = Instance.new("Part") -- create new part
        self.RealRocket.Size = self.Rocket.Size -- copy size
        self.RealRocket.Color = self.Rocket.Color -- copy color
        self.RealRocket.Name = "Rocket" -- set name
        
        local rocketMesh = Instance.new("SpecialMesh") -- create mesh object
        -- Get MeshId from MeshPart or existing SpecialMesh
        rocketMesh.MeshId = self.Rocket:IsA("MeshPart") and self.Rocket.MeshId or 
                           self.Rocket:FindFirstChildWhichIsA("SpecialMesh") and 
                           self.Rocket:FindFirstChildWhichIsA("SpecialMesh").MeshId
        -- Get TextureId from MeshPart or existing SpecialMesh
        rocketMesh.TextureId = self.Rocket:IsA("MeshPart") and self.Rocket.TextureID or 
                              self.Rocket:FindFirstChildWhichIsA("SpecialMesh") and 
                              self.Rocket:FindFirstChildWhichIsA("SpecialMesh").TextureId
        rocketMesh.Parent = self.RealRocket -- attach mesh to part
    end
    
    -- Add trail effect if specified
    if self.Trail ~= "None" then -- check if trail is enabled
        local trail = trails:FindFirstChild(self.Trail).Attachment:Clone() -- clone trail attachment
        
        trail.Parent = self.RealRocket -- attach trail to rocket
        trail.WorldPosition = self.RealRocket.Position - self.RealRocket.CFrame.LookVector -- position trail behind rocket
    end
    
    return self -- return initialized instance
end

--[[
    Pre-creates a rocket instance to avoid creating function inside Fire loop
    This improves performance by reusing the creation logic
    @return newRocket - A configured rocket Part ready to be fired
]]
function rpg:CreateRocket()
    local newRocket = self.RealRocket:Clone() -- clone the base rocket model
    newRocket:SetAttribute("Rocket", true) -- mark as rocket for collision detection
    newRocket.CanCollide = false -- disable collision initially
    
    -- Remove all welds from rocket to prevent issues
    for _, v in ipairs(newRocket:GetDescendants()) do -- ipairs used for array-like traversal
        if v:IsA("Weld") or v:IsA("WeldConstraint") then -- check if descendant is a weld
            v:Destroy() -- destroy the weld
        end
    end
    
    newRocket.Transparency = 0 -- make rocket visible
    
    return newRocket -- return configured rocket
end

--[[
    Sets up sound effects for a rocket
    @param newRocket - The rocket Part to attach sounds to
    @return travelSound, explosionSound - The two sound objects created
]]
function rpg:SetupRocketSounds(newRocket)
    local travelSound -- sound that plays while rocket travels
    local explosionSound -- sound that plays on explosion
    
    -- Setup traveling sound if specified
    if self.TravelingSound then -- check if traveling sound is enabled
        travelSound = self.ToolObject:FindFirstChild(self.TravelingSound):Clone() -- clone sound from tool
        travelSound.Parent = newRocket -- attach to rocket
        travelSound:Play() -- start playing immediately
    end
    
    -- Setup explosion sound if specified
    if self.ExplosionSound then -- check if explosion sound is enabled
        explosionSound = self.ToolObject:FindFirstChild(self.ExplosionSound):Clone() -- clone sound from tool
        explosionSound.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.15 -- randomize pitch slightly (between 0.925 and 1.075)
        explosionSound.PlayOnRemove = true -- sound plays when destroyed
        explosionSound.Parent = newRocket -- attach to rocket
    end
    
    return travelSound, explosionSound -- return both sound objects
end

--[[
    Handles rocket collision detection and explosion
    @param newRocket - The rocket Part to monitor
    @param travelSound - The traveling sound to stop on collision
    @param explosionSound - The explosion sound to destroy on collision
    @return connection - The Heartbeat connection for cleanup
]]
function rpg:SetupCollisionDetection(newRocket, travelSound, explosionSound)
    local exploded = false -- flag to prevent multiple explosions
    
    -- Connect to Heartbeat for collision detection every frame
    local connection = runService.Heartbeat:Connect(function()
        if newRocket ~= nil and not exploded then -- check rocket exists and hasn't exploded
            -- Get all parts intersecting with rocket
            for _, hit in ipairs(workspace:GetPartsInPart(newRocket)) do -- ipairs used for array returned by GetPartsInPart
                -- Check if hit part is valid target (not self, not another rocket, not debris)
                if not hit:IsDescendantOf(self.ToolObject.Parent) and -- not part of player
                   not exploded and -- hasn't already exploded
                   not hit:GetAttribute("Rocket") and -- not another rocket
                   not hit:IsDescendantOf(workspace.Debris) then -- not in debris folder
                    
                    exploded = true -- set explosion flag
                    
                    if travelSound then -- check if travel sound exists
                        travelSound:Stop() -- stop the traveling sound
                    end
                    
                    -- Create explosion at rocket position
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
                    
                    -- Disable particle emitters and calculate total lifetime
                    for _, v in ipairs(newRocket:GetDescendants()) do -- ipairs for array-like traversal
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
    
    return connection -- return connection for external cleanup if needed
end

--[[
    Fires the RPG towards the mouse position
    This is the main function called when player clicks to fire
    @param mousePos - Vector3 position where player is aiming
]]
function rpg:Fire(mousePos)
    -- Check if tool is not on cooldown and mousePos is valid
    if not self.ToolObject:GetAttribute("Cooldown") and mousePos then
        self.ToolObject:SetAttribute("Cooldown", true) -- set cooldown flag
        
        -- Spawn new thread to handle firing without blocking
        task.spawn(function()
            -- Fire multiple rockets if RocketsPerShot > 1
            for i = 1, self.RocketsPerShot do -- simple for loop, no need for pairs/ipairs
                local newRocket = self:CreateRocket() -- create rocket using pre-defined method
                
                -- Set rocket position (use Offset if defined, otherwise use Rocket position)
                newRocket.Position = self.Offset or self.Rocket.Position
                
                -- Hide original rocket model if RocketHiding is enabled
                if self.RocketHiding then
                    self.Rocket.Transparency = 1 -- make original rocket invisible
                end
                
                -- Setup sound effects for this rocket
                local travelSound, explosionSound = self:SetupRocketSounds(newRocket)
                
                -- Aim rocket towards mouse position
                newRocket.CFrame = CFrame.new(self.Rocket.Position, mousePos) -- create CFrame looking at target
                newRocket.Position = newRocket.Position + newRocket.CFrame.LookVector -- move rocket forward slightly
                
                -- Play firing sound if it exists
                local fireSound = self.ToolObject:FindFirstChild(self.FireSound)
                if fireSound ~= nil then -- check if fire sound exists
                    fireSound.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.15 -- randomize pitch slightly
                    fireSound:Play() -- play the sound
                end
                
                -- Setup antigravity force so rocket travels straight
                local bodyForce = Instance.new("BodyForce") -- create force object
                bodyForce.Name = "Antigravity" -- name for identification
                bodyForce.Force = Vector3.new(0, newRocket:GetMass() * workspace.Gravity, 0) -- counteract gravity
                bodyForce.Parent = newRocket -- attach to rocket
                
                newRocket.Parent = workspace -- add rocket to workspace
                newRocket:SetNetworkOwner(nil) -- set network ownership to server for physics
                
                -- Apply velocity to rocket in forward direction
                newRocket.AssemblyLinearVelocity = newRocket.CFrame.LookVector * self.RocketSpeed
                
                debris:AddItem(newRocket, self.DespawnTime) -- schedule rocket removal after DespawnTime
                
                -- Setup collision detection for this rocket
                self:SetupCollisionDetection(newRocket, travelSound, explosionSound)
                
                -- Wait before firing next rocket (for multi-shot weapons)
                task.wait(self.ShotsBetweenCooldown)
            end
            
            -- Start cooldown timer in separate thread
            task.spawn(function()
                task.wait(self.Cooldown) -- wait for cooldown duration
                
                -- Restore original rocket visibility if RocketHiding is enabled
                if self.RocketHiding then
                    self.Rocket.Transparency = 0 -- make rocket visible again
                end
                
                self.ToolObject:SetAttribute("Cooldown", false) -- remove cooldown flag
            end)
        end)
    end
end

--[[
    Cleanup method to disconnect all active connections
    Should be called when tool is unequipped or destroyed
]]
function rpg:Cleanup()
    -- Clean up any active rocket connections
    for _, rocketData in pairs(self._activeRockets) do -- pairs used for dictionary iteration
        if rocketData.connection then -- check if connection exists
            rocketData.connection:Disconnect() -- disconnect the connection
        end
    end
    
    self._activeRockets = {} -- clear active rockets table
end

-- Return module for requiring
return rpg
