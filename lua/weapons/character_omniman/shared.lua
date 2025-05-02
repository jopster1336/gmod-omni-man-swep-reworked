AddCSLuaFile()

local gebLib = gebLib
local Action = gebLib.Action

include("networking.lua")
AddCSLuaFile("networking.lua")
include("flying.lua")
AddCSLuaFile("flying.lua")
--
SWEP.PrintName = "#character.omni_man.printname"
SWEP.Author    = "jopster1336, Killer-Rabbid306"
SWEP.Purpose   = "#character.omni_man.purpose"
SWEP.Instructions  = "#character.omni_man.instructions"
SWEP.Category = "jopster1336"

if CLIENT then
    SWEP.PrintName = language.GetPhrase(SWEP.PrintName)
    SWEP.Purpose = language.GetPhrase(SWEP.Purpose)
    SWEP.Instructions = language.GetPhrase(SWEP.Instructions)
end

SWEP.Spawnable = true
SWEP.AdminOnly = true

SWEP.CharacterModel = "models/player/omniman_swep/omniman/omniman.mdl"
SWEP.WorldModel = ""
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.HoldType = "omniman"
--
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = true
--
SWEP.DefaultFlyingSpeed = 450
SWEP.DefaultSuperFlySpeed = 3000
--
game.AddParticles("particles/omniman_character_particles.pcf")
PrecacheParticleSystem("omniman_superflight_hit")
PrecacheParticleSystem("omniman_superflight_trail")
PrecacheParticleSystem("omniman_superflight_boom")
PrecacheParticleSystem("omniman_punch_hit_dust")
PrecacheParticleSystem("omniman_punch_hit")
PrecacheParticleSystem("omniman_normalpunch_hit")
PrecacheParticleSystem("omniman_shockwave")
PrecacheParticleSystem("omniman_omniclap_clap")
PrecacheParticleSystem("omniman_omniclap_clap_05")
PrecacheParticleSystem("omniman_omniclap_dust")
--

function SWEP:SetupDataTables()
---@diagnostic disable-next-line
    self:NetworkVar( "String", "PrevModel" )

    self:NetworkVar( "Bool", "IsBusy" )

    self:NetworkVar( "Float", "FlyingSpeed" )
    self:NetworkVar( "Bool", "IsFlying" )
    self:NetworkVarNotify( "IsFlying", function(self, name, old, new) 
        local owner = self:GetOwner()
        if SERVER then
            owner:SetLocalVelocity( owner:GetVelocity() / 3 )

            local mtype = owner:GetMoveType() ~= MOVETYPE_NOCLIP and MOVETYPE_NOCLIP or MOVETYPE_WALK
            owner:ViewPunchReset()
            owner:SetMoveType( mtype )

            self:SetSuperFlying(false)
        end
    end)

    self:NetworkVar( "Bool", "SuperFlying" )
    self:NetworkVarNotify( "SuperFlying", self.EnableSuperFlying )
    

    self:NetworkVar( "Entity", "LockTarget" )
    self:NetworkVar( "Entity", "GrabbedVictim" )

end

function SWEP:Initialize()
    timer.Simple( 0, function()
        self:SetHoldType("omniman")        
    end)

    self.m_SmoothAnimData = {}
    self.m_CurrentCombo = 0
    self.m_PunchCharge = -2
    self.m_NextDamageTime = {}
    self:SetFlyingSpeed( self.DefaultFlyingSpeed )
end

function SWEP:Equip()
    local owner = self:GetOwner()
    local hp = GetConVar("omniman_cfg_defaulthealth"):GetInt() or 30000

    if owner:Health() >= owner:GetMaxHealth() * 0.8 then
        owner:SetHealth( hp )
    end
    owner:SetMaxHealth( hp )
end

function SWEP:Deploy()
    local owner = self:GetOwner()
    local model = owner:GetModel()

---@diagnostic disable-next-line: undefined-field
    self:SetPrevModel(model)
    self.m_OldSkin = owner:GetSkin()
    self.m_OldBodygroups = owner:GetBodyGroups()

    owner:SetSkin(0)
    owner:SetModel(self.CharacterModel)
    owner:SetBodygroup( 2, 1 )
    owner:SetBodygroup( 4, 0 )

    local checkModel = Action.Create(self, 1)
    checkModel:SetEnd(function ()
        if IsValid(owner) and owner:GetModel() != self.CharacterModel then
            if SERVER then
                owner:gebLib_ChatAddText(Color(200, 0, 0), "[OMNI-MAN SWEP] ", color_white, "character.omni_man.warning.modelfailed")
                owner:EmitSound("common/bugreporter_failed.wav")
            end
        end
    end)
    checkModel:Start()

    self:PlayVoiceline("vo/deploy_0"..math.random(1,3)..".wav")
    if SERVER then
		owner:GetViewModel():SendViewModelMatchingSequence( owner:GetViewModel():LookupSequence( "fists_draw" ) )
	end

    return true
end

function SWEP:Holster()
    local owner = self:GetOwner()
    local model = self:GetPrevModel()
    local skin = self.m_OldSkin
    local bodygroups = self.m_OldBodygroups

    if model then
        owner:SetModel(model)
    end
    if skin then
        owner:SetSkin(skin)
    end
    if bodygroups then
        for k, bodygroup in ipairs(bodygroups) do
            owner:SetBodygroup(k - 1, bodygroup.num - 1)
        end
    end

    self:SetSuperFlying(false)

    if self:GetIsFlying() then
        self:SetIsFlying( false )
        owner:SetMoveType( MOVETYPE_WALK )

        owner:SetLocalVelocity( owner:GetVelocity() / 3 )
    end

    if CLIENT then
        if IsValid(self.m_FirstPersonPlayerModel) then
            self.m_FirstPersonPlayerModel:Remove()
        end
        if IsValid(self.m_ArmsFirstPersonModel) then
            self.m_ArmsFirstPersonModel:Remove()
        end
    else
        if self.m_FlyingWhooshSound then
            self.m_FlyingWhooshSound:Stop()
            self.m_FlyingWhooshSound = nil
        end
    end 

    return true
end

--

local soundMap = {
    ["metal"] = {
        "physics/metal/metal_solid_impact_hard1.wav", 
        "physics/metal/metal_solid_impact_hard2.wav", 
        "physics/metal/metal_solid_impact_hard3.wav", 
        "physics/metal/metal_solid_impact_hard4.wav"
    },
    ["wood"] = {
        "physics/wood/wood_box_impact_hard1.wav",
        "physics/wood/wood_box_impact_hard2.wav", 
        "physics/wood/wood_box_impact_hard3.wav", 
        "physics/wood/wood_box_impact_hard4.wav"
    },
    ["glass"] = {
        "physics/glass/glass_impact_bullet1.wav", 
        "physics/glass/glass_impact_bullet2.wav", 
        "physics/glass/glass_impact_bullet3.wav"
    },
    ["plastic"] = {
        "physics/plastic/plastic_box_impact_hard1.wav", 
        "physics/plastic/plastic_box_impact_hard2.wav", 
        "physics/plastic/plastic_box_impact_hard3.wav"
    },
    ["concrete"] = {
        "physics/concrete/concrete_impact_bullet1.wav", 
        "physics/concrete/concrete_impact_bullet2.wav", 
        "physics/concrete/concrete_impact_bullet3.wav"
    },
    ["flesh"] = {
        "physics/flesh/flesh_impact_hard1.wav", 
        "physics/flesh/flesh_impact_hard2.wav",
        "physics/flesh/flesh_impact_hard3.wav"
    }
}

local flyingDmgEntWhitelist = {
    ["prop_physics"] = true,
    ["prop_physics_multiplayer"] = true,
    ["prop_dynamic"] = true,
	["prop_ragdoll"] = true,
	["prop_physics_clipped"] = true,
    ["prop_door_rotating"] = true,
    ["func_breakable_surf"] = true,
    ["func_physbox"] = true,
    ["func_breakable"] = true,
}

local bonesToHide = {
    ["ValveBiped.Bip01_Head1"] = true,
}

local armsBones = {
    -- ["ValveBiped.Bip01_R_Clavicle"] = true,
    ["ValveBiped.Bip01_R_UpperArm"] = true,
    ["ValveBiped.Bip01_R_Forearm"] = true,
    ["ValveBiped.Bip01_R_Hand"] = true,
    ["ValveBiped.Bip01_R_Finger0"] = true,
    ["ValveBiped.Bip01_R_Finger01"] = true,
    ["ValveBiped.Bip01_R_Finger02"] = true,
    ["ValveBiped.Bip01_R_Finger1"] = true,
    ["ValveBiped.Bip01_R_Finger11"] = true,
    ["ValveBiped.Bip01_R_Finger12"] = true,
    ["ValveBiped.Bip01_R_Finger2"] = true,
    ["ValveBiped.Bip01_R_Finger21"] = true,
    ["ValveBiped.Bip01_R_Finger22"] = true,
    ["ValveBiped.Bip01_R_Finger31"] = true,
    ["ValveBiped.Bip01_R_Finger4"] = true,
    ["ValveBiped.Bip01_R_Finger41"] = true,
    ["ValveBiped.Bip01_R_Finger42"] = true,
    --Left Hand
    -- ["ValveBiped.Bip01_L_Clavicle"] = true,
    ["ValveBiped.Bip01_L_UpperArm"] = true,
    ["ValveBiped.Bip01_L_Forearm"] = true,
    ["ValveBiped.Bip01_L_Hand"] = true,
    ["ValveBiped.Bip01_L_Finger0"] = true,
    ["ValveBiped.Bip01_L_Finger01"] = true,
    ["ValveBiped.Bip01_L_Finger02"] = true,
    ["ValveBiped.Bip01_L_Finger1"] = true,
    ["ValveBiped.Bip01_L_Finger11"] = true,
    ["ValveBiped.Bip01_L_Finger12"] = true,
    ["ValveBiped.Bip01_L_Finger2"] = true,
    ["ValveBiped.Bip01_L_Finger21"] = true,
    ["ValveBiped.Bip01_L_Finger22"] = true,
    ["ValveBiped.Bip01_L_Finger31"] = true,
    ["ValveBiped.Bip01_L_Finger4"] = true,
    ["ValveBiped.Bip01_L_Finger41"] = true,
    ["ValveBiped.Bip01_L_Finger42"] = true,    
}

local dmgExceptions = {
    ["npc_strider"] = bit.bor(DMG_GENERIC),
    ["npc_antlionguardian"] = bit.bor(DMG_GENERIC),
    ["npc_zombie"] = bit.bor(DMG_GENERIC),
    ["npc_poisonzombie"] = bit.bor(DMG_GENERIC),
    ["npc_fastzombie"] = bit.bor(DMG_GENERIC),
    ["npc_zombine"] = bit.bor(DMG_GENERIC),
    ["npc_hunter"] = bit.bor(DMG_GENERIC),
    ["npc_alyx"] = bit.bor(DMG_GENERIC),
    ["npc_antlion"] = bit.bor(DMG_GENERIC),
    ["npc_gman"] = bit.bor(DMG_GENERIC),
    ["npc_monk"] = bit.bor(DMG_GENERIC),
    ["npc_helicopter"] = bit.bor(DMG_AIRBOAT),
    ["npc_rollermine"] = bit.bor(DMG_BLAST),
    ["npc_rollermine_friendly"] = bit.bor(DMG_BLAST),
}

local grabBlacklist = {
    ["npc_hunter"] = true,
    ["npc_strider"] = true,
    ["npc_helicopter"] = true,
}

local lowDmgTaunt = {
    "vo/vo_ughhh_01.wav",
    "vo/vo_tobeimpressed_01.wav",
    "vo/vo_tickles_01.wav",
    "vo/vo_stopembarrasing_01.wav",
}

local weakAttackerDeadTaunt = {
    "vo/vo_tryharder_01.wav",
    "vo/vo_werestronger_01.wav",
    "vo/vo_amateur_01.wav",
    "vo/vo_fragile_01.wav",
    "vo/vo_hadenough_01.wav",
    "vo/vo_insignificant_01.wav",
    "vo/vo_somucheffort_01.wav",
    "vo/vo_tooeasy_01.wav",
}

local punchingAnimOrder = {
    [0] = "attackcombo1",
    [1] = "attackcombo3",
    [2] = "attackcombo2",
    [3] = "attackcombo4",
}

local animsOffGround = {
    ["attack1"] = true,
    ["attack2"] = true,
    ["attack3"] = true,
    ["attackcombo1"] = true,
    ["attackcombo2"] = true,
    ["attackcombo3"] = true,
    ["attackcombo4"] = true,
    ["attack1_charge"] = true,
    ["attack2_charge"] = true,
}

local tr = { collisiongroup = COLLISION_GROUP_WORLD, output = {} }
local function IsInWorld( pos )
	tr.start = pos
	tr.endpos = pos

	return not util.TraceLine( tr ).HitWorld
end
--

function SWEP:Think()
    ---@type Player
    local owner = self:GetOwner()

    if owner:KeyPressed( IN_JUMP ) then
        if !self.m_CanDoubleJump then
            self.m_CanDoubleJump = true
            timer.Simple( 0.3, function()
                if IsValid(self) then
                    self.m_CanDoubleJump = false
                end
            end)
        else
            if !owner:Crouching() then
                self.m_CanDoubleJump = false

                local isFlying = self:GetIsFlying()
                
            ---@diagnostic disable-next-line: undefined-field
                if SERVER then
                    self:SetIsFlying( !isFlying )
                end
            end
        end
    end
    -- Punching
    if !self:IsSuperFlying() and !self:GetIsBusy() then
        if owner:KeyDown( IN_ATTACK ) and (!self.m_NextNormalPunch or CurTime() >= self.m_NextNormalPunch) then
            if !self.m_CurrentChargedPunchAnim then
                local anim = table.Random({"attack1_charge", "attack2_charge"})
                self:NormalAnim(anim)

                self.m_CurrentChargedPunchAnim = anim
            else
                if owner:GetLayerCycle(1) >= 0.99 then
                    self:NormalAnim(self.m_CurrentChargedPunchAnim)
                end
            end

            local maxCharge = 3.0
            if !self.m_NextPunchCharge or CurTime() >= self.m_NextPunchCharge then
                if self.m_PunchCharge < maxCharge then
                    self.m_PunchCharge = math.Clamp( self.m_PunchCharge + 0.55, -2, 3.0 )
                    self.m_NextPunchCharge = CurTime() + 0.1
                else
                    if self.m_PunchCharge != (maxCharge + 0.5) then
                        self.m_PunchCharge = self.m_PunchCharge + 0.5
                        if SERVER then
                            owner:EmitSound("punch/charge_0"..math.random(1,2)..".wav", 80, 100, 0.5)
                        end
                    end
                end
            end

            if SERVER then

            end
        end
    end
    if owner:KeyReleased( IN_ATTACK ) then
        if !self:IsSuperFlying() then
            if self.m_PunchCharge > 1 then
                self:ChargedPunch(self.m_PunchCharge)
            else
                if !self.m_NextNormalPunch or CurTime() >= self.m_NextNormalPunch then
                    self:NormalPunch()
                end
            end
        else
            owner:gebLib_StopAction()
        end
        self.m_PunchCharge = -2
        self.m_CurrentChargedPunchAnim = nil
    end
    -- Grab
    -- self:GrabThink()
    --
    --
    self:LockThink()
    if self:GetIsFlying() then
        if owner:KeyPressed( IN_SPEED ) then
            if !self.m_CanSuperFly then
                self.m_CanSuperFly = true
    
                timer.Simple( 0.3, function()
                    if IsValid(self) then
                        self.m_CanSuperFly = false
                    end
                end)
            else
                if !self:SuperFlyingCheckHit( 1.5 ) and !self:GetIsBusy() then
                    if SERVER then
                        -- owner:EmitSound("flying/start_01.mp3", 90, 100)
                        owner:EmitSound("flying/sonicboom_0"..math.random(1,2)..".mp3", 90, 100)

                        util.ScreenShake( owner:GetPos(), 5, 155, 1.8, 2000, true )

                        self:SetSuperFlying(true)
                    end
            
                    self.m_CanSuperFly = false         
                end
            end
        end
    
        if owner:KeyReleased( IN_SPEED ) then
            if SERVER then
                self:SetSuperFlying(false)
            end
        end
        
        if SERVER then
            local speed = self:GetCurrentFlyingSpeed()
            local volume = math.Clamp( speed / 2000, 0, 100 ) 

            if !self.m_FlyingWhooshSound then
                self.m_FlyingWhooshSound = CreateSound(owner, "flying/fling_whoosh.wav")
            else
                self.m_FlyingWhooshSound:Play()
                self.m_FlyingWhooshSound:ChangeVolume( volume * 0.6, 0.0 )
                self.m_FlyingWhooshSound:ChangePitch( math.Clamp(200 * (volume * 1.2), 80, 90), 0 )

                self.m_FlyingWhooshSound:SetSoundLevel( 100 * volume )
            end
        end

        self:FlyingDamage()
        if SERVER and self:IsSuperFlying() then
            local hit, trace = self:SuperFlyingCheckHit()
            if hit then
                self:SuperFlyingOnHit(trace)
            end
        end
    else
        if SERVER then
            if self.m_FlyingWhooshSound then
                self.m_FlyingWhooshSound:Stop()
                self.m_FlyingWhooshSound = nil
            end
            self:SetSuperFlying(false)
        end
    end

    if SERVER then
        if GetConVar("omniman_cfg_regenenabled"):GetInt() == 1 then
            local health, maxHealth = owner:Health(), owner:GetMaxHealth()
            if health < maxHealth then
                if !self.m_NextRegen or CurTime() >= self.m_NextRegen then
                    owner:SetHealth( math.Clamp( health + (maxHealth * 0.001), 0, maxHealth ) )
                    self.m_NextRegen = CurTime() + 1
                end
            end
        end
    end

    if CLIENT then
        -- local thirdpersonEnabled = GetConVar("omniman_thirdperson_enabled"):GetInt() == 1
        local thirdpersonEnabled = true
        if thirdpersonEnabled and IsValid(self.m_FirstPersonPlayerModel) then
            self.m_FirstPersonPlayerModel:Remove()
        end
        if thirdpersonEnabled and IsValid(self.m_ArmsFirstPersonModel) then
            self.m_ArmsFirstPersonModel:Remove()
        end
    end 

    self:NextThink(CurTime())
    return true
end

--

function SWEP:DamageMul()
    return GetConVar("omniman_cfg_damagemul"):GetFloat() or 1
end

function SWEP:PrimaryAttack() end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.8)

    self:Lock()
    -- if !self.m_NextGrab or CurTime() >= self.m_NextGrab then
    --     if self:GetGrabbedVictim() == NULL then
    --         self.m_NextGrab = CurTime() + 0.5
    --         self:GrabAttempt()
    --     else
    --         self.m_NextGrab = CurTime() + 0.5
    --         if SERVER then
    --             self:UnGrab()
    --         end
    --     end
    -- end
end

function SWEP:Lock()
    local locked = IsValid(self:GetLockTarget())
    if !locked then
        local target = self:CalculateLockTarget()

        if !target then return end
        self:SetLockTarget( target ) 
    else
        self:LockRemove()
    end
end

function SWEP:CalculateLockTarget()
    local owner = self:GetOwner()
    local target = NULL
    local trace = util.TraceLine( {
        start = owner:GetShootPos() + owner:GetAimVector(),
        endpos = owner:GetShootPos() + owner:GetAimVector() * 2000,
        filter = { self, owner },
    } )
    local tocompare = {}

    local sphere = ents.FindInSphere( trace.HitPos, 160 )
    for k, ent in ipairs( sphere ) do
        if ent == owner then continue end
        if !ent:gebLib_IsPerson() then continue end

        table.insert( tocompare, ent )
    end

    
    table.sort( tocompare, function( a, b ) return trace.HitPos:Distance( a:GetPos() ) < trace.HitPos:Distance( b:GetPos() ) end)
    target = tocompare[1]

    return target
end

function SWEP:LockRemove()
    self:SetLockTarget( nil ) 
end

function SWEP:LockThink()
    local target = self:GetLockTarget()
    if !IsValid( target ) or !target:gebLib_Alive() then
        self:LockRemove()
    else
        local owner = self:GetOwner()
        local targetPos = target:WorldSpaceCenter() or target:GetPos()

        local angle = ( targetPos - owner:EyePos() ):Angle()
        if self:GetIsFlying() then
            local mul = self:IsSuperFlying() and 4 or 8
            owner:SetEyeAngles( LerpAngle( FrameTime() * mul, owner:EyeAngles(), ( targetPos - owner:EyePos() ):Angle() ) )
        else
            owner:SetEyeAngles( ( targetPos - owner:EyePos() ):Angle() )
        end
    end
end

function SWEP:Reload()
    if self:GetIsBusy() then return end
    if self:IsSuperFlying() then return end
    if self.m_NextOmniClap and CurTime() < self.m_NextOmniClap then return end
    if self.m_ActionOmniClap then return end

    local owner = self:GetOwner()

    self.m_NextOmniClap = CurTime() + 1.9
    self:SetIsBusy(true)
    self:NormalAnim( "omniclap", 1 )

    if SERVER then
        owner:EmitSound("punch/miss_02.wav", 100, 90, 1)
    end

    self.m_ActionOmniClap = Action.Create(self, 0.6)
    self.m_ActionOmniClap:AddEvent( "clap", 0.2, function()
        if SERVER then
            owner:EmitSound("physics/wood/wood_panel_break1.wav", 100, math.random(100,120), 0.8)
            owner:EmitSound("punch/heavyhit0"..math.random(1,4)..".wav", 100, 120, 1)
            owner:EmitSound("punch/heavyhit_bass.wav", 100, 90, 1)

            util.ScreenShake( owner:GetPos(), 350900, 359000, 3.5, 2500, true )  

            net.Start("OmniMan.Network.HandleOmniClap")
                net.WriteEntity(self)
            net.Broadcast()

            self:HandleOmniClap()
        end
    end)
    self.m_ActionOmniClap:SetEnd( function()
        self:SetIsBusy(false)
        self.m_ActionOmniClap = nil
    end)

    self.m_ActionOmniClap:Start()
end

function SWEP:NormalPunch()
    if self:GetIsBusy() then return end
    local owner = self:GetOwner()
    
    local punch = Action.Create(self, 0.05)
    local cooldown = 0.3

    if self.m_CurrentCombo >= 4 then
        self.m_CurrentCombo = 0
        cooldown = 0.4
    end
    local anim = punchingAnimOrder[self.m_CurrentCombo]
    self:NormalAnim(anim, 0.9)
    self:SetIsBusy(true)
    
    self.m_CurrentCombo = self.m_CurrentCombo + 1
    self.m_NextNormalPunch = CurTime() + cooldown
    punch:SetInit(function()
        if SERVER then
            owner:EmitSound("punch/swing_00" .. math.random(1, 2) .. ".wav", 100, math.random(70, 80), 0.8)
            -- owner:EmitSound("punch/heavyswing_0" .. math.random(1, 3) .. ".wav", 90, math.random(97, 103), 0.4)
        end
    end)

    punch:SetEnd(function()
        if SERVER then
            local trace = self:PunchTrace()
            local traceToSend = {}
            traceToSend.Hit = trace.Hit
            traceToSend.HitPos = trace.HitPos
            traceToSend.HitNormal = trace.HitNormal
            traceToSend.HitWorld = trace.HitWorld
            traceToSend.Entity = trace.Entity

            traceToSend = util.TableToJSON(traceToSend)

            net.Start("OmniMan.Network.NormalPunchHit")
                net.WriteEntity(self)
                net.WriteString(traceToSend)
            net.Broadcast()

            self:HandleNormalPunch(trace)
        end

        self:SetIsBusy(false)
    end)

    punch:Start()
end    

function SWEP:HandleNormalPunch(trace)
    local owner = self:GetOwner()

    if trace.Hit then
        if SERVER then
            owner:EmitSound("punch/lighthit0"..math.random(1,4)..".wav", 120, math.random(97,103) )
            -- owner:EmitSound("punch/heavyhit0"..math.random(1,4)..".wav", 120, math.random(97,103) )
            owner:EmitSound("punch/heavyhit_bass.wav", 100, 130, 1, 0, 0, 29 )

            util.ScreenShake( owner:GetPos(), 350900, 359000, 0.5, 2500, true )  
        else
            local angle = owner:GetAimVector():GetNormalized():Angle()
            angle:RotateAroundAxis( angle:Right(), 90 )
            ParticleEffect( "omniman_normalpunch_hit", trace.HitPos, angle )   
        end

        if trace.HitWorld then
            if CLIENT then
                local center = trace.HitPos
                local normal = trace.HitNormal

                local angle = normal:Angle()
                angle:RotateAroundAxis( angle:Right(), 90 )

                -- local decal = gebLib_utils.CreateDecal("decals/concrete/shot"..math.random(1,4), util.QuickTrace(center, normal * -9).HitPos, angle, math.random(8,12), 6)
                -- decal:DoAnimation(true, 48)
                -- ParticleEffect( "omniman_punch_hit_dust", center, Angle( 0, 0, 0 ) )          
            else
                -- EmitSound("punch/hit_earthquake.wav", trace.HitPos, 0, 0, 1, 0, 90 )
            end
        else
            local hitEnt = trace.Entity
            if !IsValid(hitEnt) then return end

            local velocity = ( owner:GetAimVector() * ( 1000000 ) ) 
            local dmg = math.random(1600, 1800)
            
            self:TauntDeadAttacker(hitEnt, dmg)

            local damage = DamageInfo()
            damage:SetDamage( dmg * self:DamageMul() )
            damage:SetDamageType( dmgExceptions[hitEnt:GetClass()] and dmgExceptions[hitEnt:GetClass()] or bit.bor( DMG_GENERIC ) )
            damage:SetAttacker( owner )
            damage:SetInflictor( self )
            damage:SetDamageForce( velocity )

            if SERVER then
                if hitEnt.Health and hitEnt:Health() > 0 then
                    hitEnt:TakeDamageInfo( damage )
                end  
                
                if IsValid(hitEnt:GetPhysicsObject()) then
                    local phys = hitEnt:GetPhysicsObject()
                    phys:SetVelocity(velocity / 30)

                    local mat = hitEnt:GetPhysicsObject():GetMaterial()

                    if soundMap[mat] then
                        hitEnt:EmitSound(soundMap[mat][math.random(#soundMap[mat])], 75, 100)
                    end
                end
            end

            if hitEnt:GetClass() == "prop_door_rotating" then
                self:BustDoor(hitEnt, velocity)
            end
        end 
    end        
end

function SWEP:ChargedPunch(power)
    if self:GetIsBusy() then return end
    local owner = self:GetOwner()

    local heavyPunch = Action.Create(self, 0.05)
    local anim = string.TrimRight(self.m_CurrentChargedPunchAnim, "_charge")

    self:SetIsBusy(true)
    self:NormalAnim(anim, 0.8)
    heavyPunch:SetInit(function()
        if SERVER then
            owner:EmitSound("punch/swing_00" .. math.random(1, 2) .. ".wav", 100, 90, 0.8)
            owner:EmitSound("punch/heavyswing_0" .. math.random(1, 3) .. ".wav", 90, math.random(97, 103), 0.4)
        end
    end)

    heavyPunch:SetEnd(function()
        if SERVER then
            local trace = self:PunchTrace()
            local traceToSend = {}
            traceToSend.Hit = trace.Hit
            traceToSend.HitPos = trace.HitPos
            traceToSend.HitNormal = trace.HitNormal
            traceToSend.HitWorld = trace.HitWorld
            traceToSend.Entity = trace.Entity

            traceToSend = util.TableToJSON(traceToSend)

            net.Start("OmniMan.Network.ChargedPunchHit")
                net.WriteEntity(self)
                net.WriteString(traceToSend)
                net.WriteFloat(power)
            net.Broadcast()

            self:HandleChargedPunch(trace, power)
        end

        self:SetIsBusy(false)
    end)

    heavyPunch:Start()
end

function SWEP:HandleChargedPunch(trace, power)
    local owner = self:GetOwner()

    power = power + 1
    if trace.Hit then
        if SERVER then
            owner:EmitSound("punch/lighthit0"..math.random(1,4)..".wav", 120, math.random(97,103) )
            owner:EmitSound("punch/heavyhit0"..math.random(1,4)..".wav", 120, math.random(97,103) )
            owner:EmitSound("punch/heavyhit_bass.wav", 100, 50, 1, 0, 0, 29 )

            util.ScreenShake( owner:GetPos(), 350900, 359000, 3.5, 2500, true )  
        else
            local angle = owner:GetAimVector():GetNormalized():Angle()
            angle:RotateAroundAxis( angle:Right(), 90 )

            ParticleEffect( "omniman_punch_hit", trace.HitPos, angle )   
        end

        if trace.HitWorld then
            if CLIENT then
                local center = trace.HitPos
                local normal = trace.HitNormal
                local sizeFactor = 1.2 * (math.Clamp(power/2, 1, 1.5))

                local angle = normal:Angle()
                angle:RotateAroundAxis( angle:Right(), 90 )

                local decal = gebLib_utils.CreateDecal("decals/unburrow", util.QuickTrace(center, normal * -9).HitPos, angle, math.random(200,235) * sizeFactor, GetConVar("omniman_debris_lifetime"):GetFloat() + math.Rand(-1,1))
                decal:DoAnimation(true, 48)    
        
                local tangent1 = normal:Angle():Right()
                local tangent2 = normal:Angle():Up()
                local tangent3 = normal:Angle():Forward()
        
                if GetConVar("omniman_debris_enabled"):GetInt() == 1 then
                    local function createDebris(angleDeg, radius, mdlScale)
                        local radians = math.rad(angleDeg)
                        local offset = math.cos(radians) * tangent1 + math.sin(radians) * tangent2
                        local pos = center + offset * radius + normal * 2
                        
                        local tr = util.TraceLine( { start = pos, endpos = pos + tangent3 * -radius / 5, filter = {owner, self}, mask = MASK_NPCWORLDSTATIC } )
                        if !tr.Hit then return end
            
                        if GetConVar("omniman_ldm_enabled"):GetInt() == 0 or (GetConVar("omniman_ldm_enabled"):GetInt() == 1 and angleDeg % 8 == 0) then
                            local debris = gebLib_utils.CreateDebris("models/props_debris/concrete_chunk03a.mdl", false, GetConVar("omniman_debris_lifetime"):GetFloat() + math.Rand(-1,1))
                            debris:SetPos(pos + normal * -10)
                            debris:SetAngles(normal:Angle() + AngleRand(-180, 180))
                            debris:Spawn()
                            debris:SetModelScale(math.Rand(mdlScale.x, mdlScale.y))                                
                        end
                    end
            
                    for i = 0, 360, 8 do
                        createDebris(i, 90 * math.Clamp(math.random(sizeFactor * 1.2, sizeFactor * 1.8), -3, 3 * (math.Clamp(power/2, 1, 1.5))), Vector(1, 3.5) * sizeFactor)
                    end
                    sizeFactor = sizeFactor * 1.8
                    for i = 0, 360, 2 do
                        createDebris(i, 95 * math.Clamp(math.random(sizeFactor * 1.2, sizeFactor * 1.8), -100, 100 * (math.Clamp(power/2, -1.5, 1.5))), Vector(1, 3.5) * sizeFactor)
                    end
                end
        
                ParticleEffect( "omniman_punch_hit_dust", center, Angle( 0, 0, 0 ) )          
            else
                for _, ent in ipairs(ents.FindInSphere(trace.HitPos, 600)) do
                    if !flyingDmgEntWhitelist[ent:GetClass()] then
                        if ent:IsWorld() or ent == owner or !(ent:IsVehicle() or ent:gebLib_IsProp() or ent:gebLib_IsPerson()) then
                            continue
                        end
                    end
            
                    local dir = (ent:GetPos() - trace.HitPos):GetNormalized()
                    local velocity = dir * 300000 + vector_up * 200
                    local damage = (math.Rand( 800, 1000 ) * (1 + (power / 0.5))) * self:DamageMul()
                    --
                    local dmg = DamageInfo()
                    dmg:SetDamage( damage )
                    dmg:SetDamageForce(velocity)
                    dmg:SetAttacker( owner )
                    dmg:SetInflictor( self )
                    dmg:SetDamageType( dmgExceptions[ent:GetClass()] and dmgExceptions[ent:GetClass()] or bit.bor( DMG_GENERIC ) )
        
                    if ent.Health and ent:Health() > 0 then
                        ent:TakeDamageInfo( dmg )
                    end

                    local phys = ent:GetPhysicsObject()
                    if IsValid(phys) then
                        phys:ApplyForceCenter(velocity)
                    end
                end

                EmitSound("punch/hit_earthquake.wav", trace.HitPos, 0, 0, 1, 0, 90 )
            end
        else
            local hitEnt = trace.Entity
            if !IsValid(hitEnt) then return end

            local velocity = ( owner:GetAimVector() * ( 1000000 ) ) * power
            local dmg = math.random(2500, 4500) * power
            
            self:TauntDeadAttacker(hitEnt, dmg)

            local damage = DamageInfo()
            damage:SetDamage( dmg * self:DamageMul() )
            damage:SetDamageType( dmgExceptions[hitEnt:GetClass()] and dmgExceptions[hitEnt:GetClass()] or bit.bor( DMG_GENERIC ) )
            damage:SetAttacker( owner )
            damage:SetInflictor( self )
            damage:SetDamageForce( velocity )

            if SERVER then
                if hitEnt.Health and hitEnt:Health() > 0 then
                    hitEnt:TakeDamageInfo( damage )
                end
                
                if IsValid(hitEnt:GetPhysicsObject()) then
                    local phys = hitEnt:GetPhysicsObject()
                    phys:SetVelocity(velocity / 3)

                    local mat = hitEnt:GetPhysicsObject():GetMaterial()

                    if soundMap[mat] then
                        hitEnt:EmitSound(soundMap[mat][math.random(#soundMap[mat])], 75, 100)
                    end
                end
            end

            if hitEnt:IsPlayer() then
                hitEnt:SetVelocity(( velocity + vector_up * 32000 ) / 8000)
            end

            if hitEnt:GetClass() == "prop_door_rotating" then
                self:BustDoor(hitEnt, velocity)
            end
        end 
    end        
end

function SWEP:PunchTrace()
    local owner = self:GetOwner()

    -- if SERVER then
    --     owner:LagCompensation( true )
    -- end

    ---@diagnostic disable-next-line: missing-fields
    local trace = util.TraceHull( {
		start = owner:EyePos(),
		endpos = owner:EyePos() + owner:GetAimVector() * 70,
		filter = { owner, self },
		mins = Vector( -10, -10, -8 ),
		maxs = Vector( 10, 10, 8 ),
		mask = MASK_SHOT_HULL
	} )

    -- if SERVER then
    --     owner:LagCompensation( false )
    -- end

    return trace
end

local directions = {
    Vector(0,0,1),
    Vector(0,0,-1),
    Vector(0,1,0),
    Vector(0,-1,0),
    Vector(1,0,0),
    Vector(-1,0,0),
}
local hullmins, hullmaxs 
    = Vector(-200, -200, -200),
    Vector(200, 200, 200)

function SWEP:HandleOmniClap()
    local owner = self:GetOwner()

    local length = 2500
    local sNormal = owner:GetAimVector()
    local startPos = owner:EyePos()
    local endPos = startPos + sNormal * length

    local checkLengthLine = {
        start = startPos,
        endpos = endPos,
        filter = {owner, self},
        mask = MASK_SOLID_BRUSHONLY,
    }
    checkLengthLine = util.TraceLine(checkLengthLine)

    local resultLength = length * checkLengthLine.Fraction

    local function omniClapDebris(i, pos, normal, offset)
        local width = math.Clamp(150, 150, math.huge)
        local size = math.Rand(3,8)

        normal:Rotate(sNormal:Angle()) -- shit is weird if you don't rotate it

        local right = normal:Angle():Right()
        local forward = normal:Angle():Up()

        local vecRand = (right * math.Rand(-width * offset, width * offset)) + (forward * math.Rand(-width, width))

        local startPoint = pos
        pos = pos + vecRand + normal * -5

        local tr = util.TraceLine( { start = pos, endpos = pos + normal * (size+20), filter = {owner, self}, mask = MASK_NPCWORLDSTATIC } )
        if !tr.Hit then return end
        
        if GetConVar("omniman_debris_enabled"):GetInt() == 1 then
            if  GetConVar("omniman_ldm_enabled"):GetInt() == 0 or (GetConVar("omniman_ldm_enabled"):GetInt() == 1 and i % 2 == 0) then
                local debris = gebLib_utils.CreateDebris( "models/props_debris/concrete_chunk03a.mdl", false, GetConVar("omniman_debris_lifetime"):GetFloat() + math.Rand(-1,1) )
                debris:SetModelScale(size)
                debris:SetPos( pos )
                debris:SetAngles( AngleRand( 0, 360 ) )
                debris:Spawn()

                debris:EmitSound("physics/concrete/boulder_impact_hard"..math.random(1, 4)..".wav", 90, math.random(60,82), 0.6 )
            end
        end

        if i % 8 == 0 then
            if !IsInWorld(pos) then
                ParticleEffect( "omniman_omniclap_dust", pos, Angle( 0, 0, 0 ) )    
            end
        end 
    end

    local omniClapEffect = Action.Create(self, 0.1)
    omniClapEffect:SetEnd(function ()
        if CLIENT then
            local angle = owner:GetAimVector():Angle()
            angle:RotateAroundAxis( angle:Right(), 90 )
            angle:RotateAroundAxis( angle:Forward(), 90 )

            local att1Pos, att2Pos = owner:GetBonePosition(owner:LookupBone("ValveBiped.Bip01_R_Hand")), owner:GetBonePosition(owner:LookupBone("ValveBiped.Bip01_L_Hand"))
            local pos = (att1Pos + att2Pos) / 2
    
            ParticleEffect( "omniman_omniclap_clap", pos, angle )   

            angle:RotateAroundAxis( angle:Forward(), 90 )
            -- ParticleEffect( "omniman_omniclap_clap_05", pos, angle )   
        end    
    end)
    omniClapEffect:Start()

    local omniClap = Action.Create(self, 0.1)
    omniClap.effectOffset = 0

    omniClap:SetInit(function()
        local currentOffset = math.min(omniClap.effectOffset, resultLength)

        local hitWorldHull = {
            mins = hullmins * 1.25,
            maxs = hullmaxs * 1.25,
            mask = MASK_SOLID_BRUSHONLY,
            filter = {owner, self},
            start = startPos + sNormal * currentOffset,
            endpos = startPos + sNormal * (currentOffset + 5),
        }
        hitWorldHull = util.TraceHull(hitWorldHull)

        local hitPos = hitWorldHull.HitPos
        if hitWorldHull.HitWorld then
            if CLIENT then
                if omniClap.RepeatedFor > 0 then
                    local debrisHit = {
                        start = hitPos,
                        mask = MASK_SOLID_BRUSHONLY,
                        filter = {owner, self},
                    }
                    for _, dir in ipairs(directions) do
                        debrisHit.endpos = hitPos + dir * 200

                        local tr = util.TraceLine(debrisHit)
                        if tr.HitWorld then
                            local hitPos = tr.HitPos
                            local hitNormal = tr.Normal

                            for i = 1, 28 do
                                omniClapDebris(i, hitPos, hitNormal, (currentOffset + 100) / 300)
                            end
                        end
                    end
                end
            else
                util.ScreenShake( owner:GetPos(), 350, 359, 0.25, 1500, true )  
                EmitSound("punch/hit_earthquake.wav", hitPos, 0, 0, 1, 0, 90 )
            end
        end

        if SERVER then
            local offsetFactor = (currentOffset + 200) / 500
            local mins, maxs = hullmins * offsetFactor, hullmaxs * offsetFactor
            local entities = ents.FindInBox(hitPos + mins, hitPos + maxs)
            for _, ent in ipairs(entities) do
                if !flyingDmgEntWhitelist[ent:GetClass()] then
                    if ent:IsWorld() or ent == owner or !(ent:IsVehicle() or ent:gebLib_IsProp() or ent:gebLib_IsPerson()) then
                        continue
                    end
                end
                local damage = math.Rand( 300, 500 )
                local velocity = sNormal * 300000 + vector_up * 200

                local dmg = DamageInfo()
                dmg:SetDamage( damage * self:DamageMul() )
                -- dmg:SetDamageForce( velocity )
                dmg:SetAttacker( owner )
                dmg:SetInflictor( self )
                dmg:SetDamageType( dmgExceptions[ent:GetClass()] and dmgExceptions[ent:GetClass()] or bit.bor( DMG_GENERIC ) )
                
                self:TauntDeadAttacker(ent, damage)

                if ent.Health and ent:Health() > 0 then
                    ent:TakeDamageInfo( dmg )
                end
                
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(velocity / 3)
                end
        
                if ent:GetClass() == "prop_door_rotating" then
                    self:BustDoor(ent, velocity)
                end
            end
        end

        omniClap.effectOffset = omniClap.effectOffset + 300
    end)

    local repeats = resultLength / 250
    omniClap:Start(repeats)
end

-- function SWEP:GrabThink()
--     local grabbed = self:GetGrabbedVictim()
--     local owner = self:GetOwner()

--     -- This code was mainly copied from gStands by Copper because i fuckin hate this sht
--     if IsValid(grabbed) then
--         if SERVER and 
--             ( (!self:IsSuperFlying() and grabbed:GetPos():Distance(owner:EyePos()) > 350) or 
--             grabbed:GetMoveType() != MOVETYPE_NONE ) then
--             self:UnGrab()
--         end
        
--         local verticalOffset = 1
--         if grabbed:LookupBone( "ValveBiped.Bip01_Head1" ) then
--             verticalOffset = -50
--         end

--         local bonePos = owner:GetAttachment(5).Pos
--         local mins, maxs = grabbed:GetCollisionBounds()
--         local trace = util.TraceHull(
--         {
--             start = bonePos, 
--             endpos = bonePos + owner:GetAimVector() * 40,
--             filter = { owner, self, grabbed },
--             mask = MASK_SOLID,
--             mins = mins,
--             maxs = maxs,
--         })
--         local pos = trace.HitPos + owner:GetUp() * verticalOffset
--         local headPos = grabbed:GetBonePosition(grabbed:LookupBone( "ValveBiped.Bip01_Head1" ) or 0) or vector_origin

--         local targetPos = (headPos + pos) / 2
--         local newPos = targetPos
    
--         grabbed:SetPos(newPos)
--         grabbed:SetLocalVelocity(vector_origin)
--         if grabbed:GetPhysicsObject() and IsValid(grabbed:GetPhysicsObject()) then
--             grabbed:GetPhysicsObject():Sleep()
--         end
--     end
-- end

-- function SWEP:GrabAttempt()
--     local owner = self:GetOwner()
    
--     local grab = Action.Create(self, 0.05)
--     local cooldown = 0.3

--     owner:gebLib_PlayAction("zombie_attack_06", 0.9)
    
--     grab:SetInit(function()
--         if SERVER then
--             owner:EmitSound("punch/swing_00" .. math.random(1, 2) .. ".wav", 100, math.random(70, 80), 0.8)
--             -- owner:EmitSound("punch/heavyswing_0" .. math.random(1, 3) .. ".wav", 90, math.random(97, 103), 0.4)
--         end
--     end)

--     grab:SetEnd(function()
--         if SERVER then
--             local trace = self:PunchTrace()

--             if IsValid(trace.Entity) and trace.Entity:gebLib_IsPerson() then
--                 local traceToSend = {}
--                 traceToSend.Hit = trace.Hit
--                 traceToSend.HitPos = trace.HitPos
--                 traceToSend.HitNormal = trace.HitNormal
--                 traceToSend.HitWorld = trace.HitWorld
--                 traceToSend.Entity = trace.Entity

--                 net.Start("OmniMan.Network.GrabSuccesful")
--                     net.WriteEntity(self)
--                     net.WriteTable(traceToSend)
--                 net.Broadcast()

--                 self:GrabSuccesful(trace)
--             end
--         end
--     end)

--     grab:Start()
-- end

-- function SWEP:GrabSuccesful(trace)
--     self:SetGrabbedVictim(trace.Entity)

--     self.m_GrabbedEntOldCollGroup = trace.Entity:GetCollisionGroup()
--     self.m_GrabbedEntOldMoveType = trace.Entity:GetMoveType()
--     trace.Entity:SetCollisionGroup(COLLISION_GROUP_DEBRIS_TRIGGER)
--     trace.Entity:SetMoveType(MOVETYPE_NONE)
-- end

-- function SWEP:UnGrab()
--     local grabbed = self:GetGrabbedVictim()

--     if SERVER then
--         net.Start("OmniMan.Network.UnGrab")
--             net.WriteEntity(self)
--         net.Broadcast()
--     end

--     if IsValid(grabbed) then
--         grabbed:SetMoveType(self.m_GrabbedEntOldMoveType)
--         grabbed:SetCollisionGroup(self.m_GrabbedEntOldCollGroup)
--         self.m_GrabbedEntOldMoveType = nil

--         self:SetGrabbedVictim(NULL)
--     end
-- end

function SWEP:BustDoor(ent, velocity)
    local doorPos = ent:GetPos()
    local doorAng = ent:GetAngles()
    local doorModel = ent:GetModel()
    local doorSkin = ent:GetSkin() or 0

    if SERVER then
        local doorProp = ents.Create("prop_physics")
        if IsValid(doorProp) then
            doorProp:SetModel(doorModel)
            doorProp:SetPos(doorPos)
            doorProp:SetAngles(doorAng)
            doorProp:SetSkin(doorSkin)
            doorProp:Spawn()

            local phys = doorProp:GetPhysicsObject()
            if IsValid(phys) then
                phys:ApplyForceCenter(velocity)
            end

            doorProp:EmitSound("physics/wood/wood_crate_break"..math.random(1,5)..".wav", 90, 100)
            util.ScreenShake(doorPos, 15, 15, 0.4, 512)

            ent:Remove()

            timer.Simple(30, function()
                if IsValid(doorProp) then
                    doorProp:Remove()
                end
            end)
        end

        return doorProp
    end
end

--

function SWEP:OnRemove()
    if CLIENT then
        if IsValid(self.m_FlightModel) then
            self.m_FlightModel:Remove()
        end
        if IsValid(self.m_FirstPersonPlayerModel) then
            self.m_FirstPersonPlayerModel:Remove()
        end
        if IsValid(self.m_ArmsFirstPersonModel) then
            self.m_ArmsFirstPersonModel:Remove()
        end
    else
        if self.m_FlyingWhooshSound then
            self.m_FlyingWhooshSound:Stop()
            self.m_FlyingWhooshSound = nil
        end
    end 
end

--

function SWEP:EnableSuperFlying(name, old, new)
    if new then
        self:SetFlyingSpeed(self.DefaultSuperFlySpeed)

        if CLIENT then
            self:CreateFlightModel()  
        end
    else
        self:SetFlyingSpeed(self.DefaultFlyingSpeed)

        if CLIENT then
            self:RemoveFlightModel()
        end
    end
end

function SWEP:CreateFlightModel()
    if !IsValid(self.m_FlightModel) then
        local owner = self:GetOwner()
        local mdl = ClientsideModel(self.CharacterModel)
        mdl:SetPos(owner:WorldSpaceCenter() + self:GetForward() * -0)
        mdl:SetAngles(owner:GetAngles())
        mdl:SetBodygroup( 2, 1 )

        mdl:ResetSequence("superflight")

        mdl:SetParent(owner)

        mdl.BonesAdjustedToFPS = false
        mdl.RenderOverride = function(self)
            -- if GetConVar("omniman_thirdperson_enabled"):GetInt() == 0 and LocalPlayer() == self:GetParent() then
            --     if !self.BonesAdjustedToFPS then
            --         for i = 0, self:GetBoneCount() - 1 do
            --             if bonesToHide[self:GetBoneName(i)] then
            --                 self:ManipulateBoneScale(i, vector_origin)
            --             end
            --         end
            --         self.BonesAdjustedToFPS = true
            --     end
            -- else
            --     if self.BonesAdjustedToFPS then
            --         for i = 0, self:GetBoneCount() - 1 do
            --             if bonesToHide[self:GetBoneName(i)] then
            --                 self:ManipulateBoneScale(i, Vector(1,1,1))
            --             end
            --         end
            --         self.BonesAdjustedToFPS = false
            --     end
            -- end
            local ang = owner == LocalPlayer() and owner:GetAngles() or owner:GetAimVector():Angle()
            self:SetPos(owner:GetPos())
            -- print(self:GetAngles(), ang)

            -- self:SetPos(owner:WorldSpaceCenter() + self:GetForward() * -0)
            self:SetAngles(ang)
            if self:GetCycle() != nil and self:GetCycle() >= 1 then self:SetCycle(0) end
            self:FrameAdvance()

            -- if GetConVar("omniman_thirdperson_enabled"):GetInt() == 1 or (self:GetAttachment( 1 ) and EyePos():Distance(self:GetAttachment( 1 ).Pos) < 10) then
                self:DrawModel()
            -- end
            if IsValid(self.Trail) then
                self.Trail:Render()
            end
        end

        mdl:Spawn()

        mdl.Trail = CreateParticleSystem( mdl, "omniman_superflight_trail", PATTACH_POINT_FOLLOW, 1 )
        mdl.Trail:SetShouldDraw(false)

        ParticleEffect( "omniman_superflight_boom", mdl:GetPos(), angle_zero )  
        self.m_FlightModel = mdl
    end
end

function SWEP:RemoveFlightModel()
    if IsValid(self.m_FlightModel) then
        if IsValid(self.m_FlightModel.Trail) then
            self.m_FlightModel.Trail:SetShouldDraw(true)
            self.m_FlightModel.Trail:StopEmission()
        end

        self.m_FlightModel:Remove()
        self.m_FlightModel = nil
    end
end

function SWEP:IsSuperFlying()
    return self:GetSuperFlying()
end

function SWEP:GetCurrentFlyingSpeed()
    local owner = self:GetOwner()
    local velocity = owner:GetVelocity() 
    
    return math.Round(velocity:Length(), 2)
end

function SWEP:FlyingDamage()
    local owner = self:GetOwner()

    local velocity = owner:GetVelocity() 
    local speedfactor = self:GetCurrentFlyingSpeed()

    local dealDamage = speedfactor > 600 
    if dealDamage then
        local radius = speedfactor / 600 

        local didHit = false
        for _, ent in ipairs(ents.FindInSphere(owner:WorldSpaceCenter(), 35 * radius)) do
            if !flyingDmgEntWhitelist[ent:GetClass()] then
                if ent:IsWorld() or ent == owner or !(ent:IsVehicle() or ent:gebLib_IsProp() or ent:gebLib_IsPerson()) or ent == self:GetGrabbedVictim() then
                    continue
                end
            end
            if self.m_NextDamageTime[ent] and CurTime() < self.m_NextDamageTime[ent] then continue end
            if IsValid( ent ) then
                didHit = true
                if SERVER then
                    local dmg = DamageInfo()

                    dmg:SetDamage( ( speedfactor / 5 ) * self:DamageMul() )
                    dmg:SetDamageForce( velocity * (speedfactor * 2) )
                    dmg:SetAttacker( owner )
                    dmg:SetInflictor( self )
                    dmg:SetDamageType( dmgExceptions[ent:GetClass()] and dmgExceptions[ent:GetClass()] or bit.bor( DMG_GENERIC ) )

                    if ent.Health and ent:Health() > 0 then
                        ent:TakeDamageInfo( dmg )
                    end

                    -- Apply knockback force
                    if IsValid(ent:GetPhysicsObject()) then
                        local phys = ent:GetPhysicsObject()
                        phys:SetVelocity((velocity / 300) * math.min(speedfactor, 1000))

                        local mat = ent:GetPhysicsObject():GetMaterial()

                        if soundMap[mat] then
                            ent:EmitSound(soundMap[mat][math.random(#soundMap[mat])], 75, 100)
                        end
                    end
                end

                if ent:GetClass() == "prop_door_rotating" then
                    if SERVER then
                        local fakeDoor = self:BustDoor(ent, velocity * (speedfactor * 0.08))
                        self.m_NextDamageTime[fakeDoor] = CurTime() + 0.3
                    end
                end
                
                self.m_NextDamageTime[ent] = CurTime() + 0.1
            end
        end

        if didHit then
            util.ScreenShake( owner:GetPos(), 4, 25, 0.3, 700, true )
        end
    end
end

function SWEP:SuperFlyingCheckHit( scale )
    local owner = self:GetOwner()

    if scale and scale != 1 then
        local minsA, maxsA = owner:GetRotatedAABB( owner:OBBMins(), owner:OBBMaxs() )

        local t = {}
        t.start = owner:GetPos() + owner:GetAimVector() * ( 15 * scale )
        t.endpos = owner:GetPos() + owner:GetAimVector() * ( 15 * scale )
        t.filter = { owner, self }
        t.maxs = (maxsA * 0.8) * scale
        t.mins = (minsA * 0.8) * scale
        t.mask = MASK_NPCWORLDSTATIC
    
        local trace = util.TraceHull( t ) 
        return trace.Hit, trace
    end

    local endpos = owner:GetPos() + owner:GetAimVector() * 40
	local t = {}
	t.start = owner:GetPos()
	t.endpos = endpos
	t.filter = { owner, self }
    t.mask = MASK_NPCWORLDSTATIC

	local trace = util.TraceEntity( t, owner )
    return trace.Hit, trace
end

function SWEP:SuperFlyingOnHit( trace )
    local owner = self:GetOwner()

    if SERVER then
        owner:EmitSound("flying/superspeed_crush_0"..math.random(1,3)..".mp3", 100, 100)            
        owner:EmitSound("physics/concrete/concrete_break2.wav", 100, 80, 0.2)

        util.ScreenShake( owner:GetPos(), 35000, 35000, 1.5, 2500, true )  

        for _, ent in ipairs(ents.FindInSphere(owner:GetPos(), 1500)) do
            if !flyingDmgEntWhitelist[ent:GetClass()] then
                if ent:IsWorld() or ent == owner or !(ent:IsVehicle() or ent:gebLib_IsProp() or ent:gebLib_IsPerson()) then
                    continue
                end
            end
    
            local dir = (ent:GetPos() - owner:GetPos()):GetNormalized()
            local velocity = dir * 300000 + vector_up * 200
            if SERVER then
                local dmg = DamageInfo()
                dmg:SetDamage( math.Rand( 800, 1000 ) * self:DamageMul() )
                dmg:SetDamageForce(velocity)
                dmg:SetAttacker( owner )
                dmg:SetInflictor( self )
                dmg:SetDamageType( dmgExceptions[ent:GetClass()] and dmgExceptions[ent:GetClass()] or bit.bor( DMG_GENERIC ) )
    
                ent:TakeDamageInfo( dmg )
            end
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                phys:ApplyForceCenter(velocity)
            end
        end
        --
        local compressedTrace = {}
        compressedTrace.HitPos = trace.HitPos
        compressedTrace.HitNormal = trace.HitNormal
        compressedTrace.FlyingSpeed = self:GetCurrentFlyingSpeed()

        compressedTrace = util.TableToJSON(compressedTrace)

        net.Start("OmniMan.Network.SuperFlyingOnHit")
            net.WriteEntity( self )
            net.WriteString( compressedTrace )
        net.Broadcast()

        owner:SetLocalVelocity( vector_origin )

        self:SetSuperFlying(false)
    end

    if CLIENT then
        local center = trace.HitPos
        local normal = trace.HitNormal
        local sizeFactor = math.Clamp(trace.FlyingSpeed, 0, 2)

        local angle = normal:Angle()
        angle:RotateAroundAxis( angle:Right(), 90 )
        angle:RotateAroundAxis( angle:Up(), math.random(360) )

        local decal = gebLib_utils.CreateDecal("omnimanswep/decals/crack", util.QuickTrace(center, normal * -9).HitPos + normal * 2, angle, math.random(100,120) * sizeFactor, GetConVar("omniman_debris_lifetime"):GetFloat())
        decal:DoAnimation(true, 48)    

        local tangent1 = normal:Angle():Right()
        local tangent2 = normal:Angle():Up()
        local tangent3 = normal:Angle():Forward()

        if GetConVar("omniman_debris_enabled"):GetInt() == 1 then
            local function createDebris(angleDeg, radius, mdlScale)
                local radians = math.rad(angleDeg)
                local offset = math.cos(radians) * tangent1 + math.sin(radians) * tangent2
                local pos = center + offset * radius + normal * 2
                
                local tr = util.TraceLine( { start = pos, endpos = pos + tangent3 * -radius / 2, filter = {owner, self}, mask = MASK_NPCWORLDSTATIC } )
                if !tr.Hit then return end
                
                if GetConVar("omniman_ldm_enabled"):GetInt() == 0 or (GetConVar("omniman_ldm_enabled"):GetInt() == 1 and angleDeg % 8 == 0) then
                    local debris = gebLib_utils.CreateDebris("models/props_debris/concrete_chunk03a.mdl", false, GetConVar("omniman_debris_lifetime"):GetFloat() + math.Rand(-1,1))
                    debris:SetPos(pos)
                    debris:SetAngles(normal:Angle() + AngleRand(-180, 180))
                    debris:SetModelScale(math.Rand(mdlScale.x, mdlScale.y))
                    debris:Spawn()
                end
            end
    
            for i = 0, 360, 10 do
                createDebris(i, 60 * math.Clamp(sizeFactor, 1, 3), Vector(0.75, 2.75) * sizeFactor)
            end
            for i = 0, 360, 20 do
                createDebris(i, 90 * math.Clamp(sizeFactor, 1, 3), Vector(0.75, 2.75) * sizeFactor * 2)
            end
    
            for i = 0, 360, 30 do
                createDebris(i, 90 * math.Clamp(sizeFactor * 3, 1, 3), Vector(0.75, 2.75) * sizeFactor * 3)
            end
        end

        -- self:ImpactFrame()
        ParticleEffect( "omniman_superflight_hit", center, Angle( 0, 0, 0 ) )            
    end
end

--
local minDamage = 50
local unGrabDamage = 300
local fractionDamage = 0.1

local function OmniManDamageResistance( target, damage )
    if !target:IsPlayer() then return end
    local wep = target:GetActiveWeapon()
    if !IsValid( wep ) or wep:GetClass() ~= "character_omniman" then return end
    local superArmorMul = GetConVar("omniman_cfg_superarmormul"):GetFloat() or 1

    damage:ScaleDamage( fractionDamage / math.Clamp(superArmorMul, 0.00001, math.huge) )
    -- if damage:GetDamage() >= unGrabDamage and IsValid(wep:GetGrabbedVictim()) then
    --     wep:UnGrab()
    --     return false
    -- end
    if damage:GetDamage() >= minDamage then
        return false
    end

    if IsValid(damage:GetAttacker()) and damage:GetAttacker():gebLib_IsPerson() then
        wep.m_AttackerToTaunt = damage:GetAttacker()

        if math.random(0,100) > 50 then
            wep:Taunt(table.Random(lowDmgTaunt), wep.m_AttackerToTaunt, 4.0)
        end
    end

    return true
end
hook.Add( "EntityTakeDamage", "OmniMan.DamageResistance", OmniManDamageResistance )

local function OmniManDamageBulletResistance( target, hitgroup, damage )
    local wep = target:GetActiveWeapon()
    if !IsValid( wep ) or wep:GetClass() ~= "character_omniman" then return end

    damage:ScaleDamage( fractionDamage )
    if damage:GetDamage() > minDamage then
        return
    end

    return true
end
hook.Add( "ScalePlayerDamage", "OmniMan.DamageBulletResistance", OmniManDamageBulletResistance )

function SWEP:CreateShockwave(pos, speed)
    local owner = self:GetOwner()
    local speedFactor = math.Clamp(speed / 900, 1.5, math.huge)

    if SERVER then
        if speedFactor <= 1.5 then
            owner:EmitSound("shockwave/shockwave_light0"..math.random(1,2)..".mp3", 100, 90)
        else
            owner:EmitSound("shockwave/shockwave_heavy0"..math.random(2,2)..".mp3", 150, 90)            
        end
        owner:EmitSound("physics/concrete/concrete_break2.wav", 100, 80, 0.2)

        util.ScreenShake( owner:GetPos(), 6 * (speedFactor*3), 6 * (speedFactor*3), speedFactor, 10 * speed, true )
    end

    if CLIENT then
        if !IsFirstTimePredicted() then return end
        local center = owner:GetPos()
        local scale = Vector( 60, 60, 0 )
        local segmentdist = 360 / ( 2 * math.pi * math.max( scale.x, scale.y ) / 2 )

        local decal = gebLib_utils.CreateDecal("decals/unburrow", util.QuickTrace(center, center).HitPos, angle_zero, math.random(130,150) * speedFactor, GetConVar("omniman_debris_lifetime"):GetFloat())
        -- decal:DoAnimation(true, 48)    

        if GetConVar("omniman_debris_enabled"):GetInt() == 1 then
            local function createDebris(i, scale, mdlScale)
                local pos = Vector( center.x + math.cos( math.rad( i ) ) * scale.x, center.y - math.sin( math.rad( i ) ) * scale.y, (center.z - 10) )

                local trEndPos = pos + vector_up * -20
                local tr = util.TraceLine( { start = pos, endpos = trEndPos, filter = {owner, self}, mask = MASK_NPCWORLDSTATIC } )
                if !tr.Hit then return end

                if GetConVar("omniman_ldm_enabled"):GetInt() == 0 or (GetConVar("omniman_ldm_enabled"):GetInt() == 1 and i % 8 == 0) then
                    local debris = gebLib_utils.CreateDebris( "models/props_debris/concrete_chunk03a.mdl", false, GetConVar("omniman_debris_lifetime"):GetFloat() + math.Rand(-1,1) )
                    debris:SetPos( pos )
                    debris:SetAngles( AngleRand( 0, 360 ) )
                    debris:SetModelScale( math.Rand(mdlScale.x, mdlScale.y) )   
                    
                    debris:Spawn()
                end
            end

            local sizeFactor = math.Clamp( speedFactor, 0, 10 )

            for i = 0, 360, 10 do
                createDebris(i, scale * math.Clamp( sizeFactor, 1, 3 ), Vector(0.75, 2.75) * sizeFactor )
            end

            local scale = Vector( 90, 90, 0 )
            for i = 0, 360, 20 do
                createDebris(i, scale * math.Clamp( sizeFactor, 1, 3 ), Vector(0.75, 2.75) * sizeFactor * 2 )
            end
        end
        ParticleEffect( "omniman_shockwave", center, Angle( 0, 0, 0 ) )
    end

    for _, ent in ipairs(ents.FindInSphere(pos, speed / 3)) do
        if !flyingDmgEntWhitelist[ent:GetClass()] then
            if ent:IsWorld() or ent == owner or !(ent:IsVehicle() or ent:gebLib_IsProp() or ent:gebLib_IsPerson()) then
                continue
            end
        end

        local dir = (ent:GetPos() - pos):GetNormalized()
        local velocity = dir * ( speed * 100 ) + vector_up * 200
        if SERVER then
            local dmg = DamageInfo()
            dmg:SetDamage( speed / 2 )
            dmg:SetDamageForce(velocity)
            dmg:SetAttacker( owner )
            dmg:SetInflictor( self )
            dmg:SetDamageType( dmgExceptions[ent:GetClass()] and dmgExceptions[ent:GetClass()] or bit.bor( DMG_GENERIC ) )

            if ent.Health and ent:Health() > 0 then
                ent:TakeDamageInfo( dmg )
            end
        end
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:ApplyForceCenter(velocity)
        end
    end
end

hook.Add("GetFallDamage", "OmniMan.NoFallDamage", function(ply)
    if IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() == "character_omniman" then
        return 0
    end
end)

hook.Add("OnPlayerHitGround", "OmniMan.FallShockwave", function(ply, inWater, onFloater, speed)
    if IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() == "character_omniman" then
        if speed > 600 then
            ply:GetActiveWeapon():CreateShockwave(ply:GetPos(), speed)
        end
    end
end)

hook.Add( "PlayerFootstep", "OmniMan.FlyingFootsteps", function( ply, pos, foot, sound, volume, rf )
    if IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() == "character_omniman" then
        return ply:GetActiveWeapon():IsCurrentlyOffGround()
    end
end )

--

function SWEP:PlayVoiceline( path )
    if SERVER then
        local owner = self:GetOwner()
        if owner:GetInfo( "omniman_voicelines_enabled" ) == "1" then
            owner:EmitSound(path, 90, 100, 1.0, CHAN_VOICE)
        end
    end
end

function SWEP:Taunt( snd, victim, cooldown )
    if !self.m_NextTaunt or CurTime() >= self.m_NextTaunt then
        self:PlayVoiceline( snd )
        self.m_NextTaunt = CurTime() + (cooldown or 30)
    end
end

function SWEP:TauntDeadAttacker( victim, dmg )
    if !IsValid(victim) or !victim:gebLib_IsPerson() then return end
    if self.m_AttackerToTaunt == victim and (victim:Health() - dmg) <= victim:GetMaxHealth() * 0.2 then
        self:Taunt(table.Random(weakAttackerDeadTaunt), victim, 3.0)
    end
end
--

function SWEP:SmoothAnim(anim, playbackRate, speed)
    speed = speed or 10
    playbackRate = playbackRate or 1
    local owner = self:GetOwner()
    owner:gebLib_PlayAction(anim, playbackRate)
    owner:AnimSetGestureWeight(1, 0)

    local duration = owner:GetLayerDuration(1)
    local action = Action.Create(self, 0.001)
    -- action._startTime = CurTime()
    action._weight = 0

    action:SetInit(function()
        action._weight = Lerp(FrameTime() * speed, action._weight, 1)
        owner:AnimSetGestureWeight(1, action._weight)
        if action._weight >= 0.99 then
            action:Remove()
        end
    end)
    action:Start(100 * speed)
end

function SWEP:NormalAnim(anim, playbackRate)
    local owner = self:GetOwner()

    playbackRate = playbackRate or 1

    if !game.SinglePlayer() or (game.SinglePlayer() and SERVER) then
        owner:gebLib_PlayAction(anim, playbackRate)
    end
end

function SWEP:IsCurrentlyOffGround()
    local owner = self:GetOwner()
    local currentAnim = owner:GetLayerSequence(1)
    return animsOffGround[currentAnim]
end

--

local defaultFov = 90
local defaultLockCamOffset = 0

local camFov = defaultFov
local lockCamOffset = 0

local vectorOrigin = vector_origin
local angleZero = angle_zero

local viewPos   = vectorOrigin
local viewAngle = angleZero

local function FirstPerson( ply, pos, angles, fov, wep )
    if !wep or !IsValid(wep.m_FirstPersonPlayerModel) then return end

    local view = {}
    if !IsValid(wep.m_FlightModel) then
        view = {
            origin = ply:GetAttachment( 1 ).Pos + vector_up * 1,
            angles = angles,
            fov = fov,
            drawviewer = false
        }
    else
        view = {
            origin = wep.m_FlightModel:GetAttachment( 1 ).Pos + ( ply:GetAimVector() * 4.5 ) + ( wep.m_FlightModel:GetUp() * 5 ),
            angles = angles,
            fov = fov,
            drawviewer = false
        }        
    end

    return view
end

local function ThirdPerson( ply, pos, angles, fov, wep )
    if !wep or camFov < 10 then return end

    local lockTarget = wep.GetLockTarget and wep:GetLockTarget() or nil
    ---@diagnostic disable-next-line: missing-fields
    local tr = util.TraceLine( {
        start = pos,
        endpos = pos - ( angles:Forward() * camFov ),
        collisiongroup = COLLISION_GROUP_DEBRIS,
    } )
    
    if IsValid(lockTarget) then
        local targetpos = lockTarget:WorldSpaceCenter() or lockTarget:GetPos()

        local finalPos = ( angles:Forward() * 100 + angles:Right() * -30 )
        angles = (targetpos - (pos - finalPos)):Angle()
            
        ---@diagnostic disable-next-line: missing-fields
        tr = util.TraceLine( {
            start = pos,
            endpos = pos - finalPos,
            collisiongroup = COLLISION_GROUP_DEBRIS,
        } )
    end

    if viewPos == vectorOrigin then
        viewPos = tr.HitPos
    end
    if viewAngle == angleZero then
        viewAngle = angles
    end

    local MAX_DT = 0.01
    local dt = RealFrameTime()

    if dt > MAX_DT then dt = MAX_DT end
    local smooth = math.min(25 * dt, 1)

    local frameTime = (!wep.IsSuperFlying or !wep:IsSuperFlying()) and dt or dt * 3

    camFov = (!wep.IsSuperFlying or !wep:IsSuperFlying()) and defaultFov or 130
    camFov = (!wep.m_ActionOmniClap) and camFov or 120
        
    viewPos = LerpVector( 25 * frameTime, viewPos, tr.HitPos )
    viewAngle = LerpAngle( 25 * frameTime, viewAngle, angles )
    -- viewPos = tr.HitPos
    -- viewAngle = angles

    local view = {
        origin = viewPos,
        angles = viewAngle,
        fov = fov,
        drawviewer = (!wep.IsSuperFlying or !wep:IsSuperFlying())
    }

    return view
end

local function FreezeMouseWhileLocking( cmd ) // So you cant turn your camera when you lock
    local ply = LocalPlayer()

    local wep = ply:GetActiveWeapon()
    if !IsValid( wep ) or wep:GetClass() ~= "character_omniman" then return end
    if ply:GetActiveWeapon().GetLockTarget and !IsValid(ply:GetActiveWeapon():GetLockTarget()) then return end

	cmd:SetMouseX( 0 )
	cmd:SetMouseY( 0 )

	return true
end

hook.Add( "InputMouseApply", "OmniMan.FreezeMouseWhileLocking", FreezeMouseWhileLocking )

function SWEP:CreateFirstPersonMdl(ply)
    local fpsmodel = ClientsideModel(self.CharacterModel)
    local weapon = self

    fpsmodel:SetPos(ply:GetPos())
    fpsmodel:Spawn()
    fpsmodel:SetNoDraw(false)

    for bone, _ in pairs(bonesToHide) do
        fpsmodel:ManipulateBoneScale( fpsmodel:LookupBone(bone), vectorOrigin )
    end

    -- fpsmodel:SetParent(ply)
    fpsmodel:SetOwner(ply)

    fpsmodel.RenderOverride = function( self )
        if !IsValid(weapon) then self:Remove() return end

        local ang = ply:GetAngles()
        ang.x = 0
        self:SetPos(ply:GetPos())
        self:SetAngles(ang)
        --
        local blend = math.Clamp(1.5 - (EyeAngles().x / 90), 0.75, 1)

        local seq = ply:GetLayerSequence(1)

        ply:SetupBones()
        self:SetupBones()
        for i = 0, ply:GetBoneCount() - 1 do
            local boneMatrix = ply:GetBoneMatrix(i)
            if boneMatrix and !bonesToHide[self:GetBoneName(i)] then
                self:SetBoneMatrix(i, boneMatrix)
            end
        end

        if !weapon:IsSuperFlying() then
            if blend < 0.9 then
                render.OverrideColorWriteEnable(true, false)
                self:DrawModel()
                render.OverrideColorWriteEnable(false, false)

                ply:SetupBones()
                self:SetupBones()
                for i = 0, ply:GetBoneCount() - 1 do
                    local boneMatrix = ply:GetBoneMatrix(i)
                    if boneMatrix and !bonesToHide[self:GetBoneName(i)] then
                        self:SetBoneMatrix(i, boneMatrix)
                    end
                end

                render.SetBlend(blend)
                self:DrawModel()
                render.SetBlend(1)
            else
                self:DrawModel()
            end
        end
    end

    self.m_FirstPersonPlayerModel = fpsmodel

    -- local armsmodel = ClientsideModel("models/player/omniman/omniman_arms.mdl")

    -- armsmodel:SetPos(ply:GetPos())
    -- armsmodel:Spawn()
    -- armsmodel:SetNoDraw(false)

    -- armsmodel:SetParent(ply)
    -- armsmodel:SetOwner(ply)

    -- armsmodel.RenderOverride = function(self)
    --     local ang = ply:GetAngles()
    --     self:SetPos(EyePos()) -- Позиция от камеры
    --     self:SetAngles(ang)
    
    --     -- Обновляем кости
    --     ply:SetupBones()
    --     self:SetupBones()
    
    --     for i = 0, ply:GetBoneCount() - 1 do
    --         local boneName = ply:GetBoneName(i)
    --         if boneName and armsBones[boneName] then
    --             local sourceMatrix = ply:GetBoneMatrix(i)
    --             local targetIndex = self:LookupBone(boneName)
    
    --             if sourceMatrix and targetIndex and targetIndex >= 0 then
    --                 local targetMatrix = self:GetBoneMatrix(targetIndex)
    --                 if targetMatrix then
    --                     -- Вместо сложения просто копируем позицию и угол
    --                     targetMatrix:SetTranslation(sourceMatrix:GetTranslation())
    --                     targetMatrix:SetAngles(sourceMatrix:GetAngles())
    
    --                     self:SetBoneMatrix(targetIndex, targetMatrix)
    --                 end
    --             end
    --         end
    --     end
    
    --     self:DrawModel()
    -- end

    -- self.m_ArmsFirstPersonModel = armsmodel
end

local function OmniManCam( ply, pos, angles, fov )
    local wep = ply:GetActiveWeapon()
    if !IsValid( wep ) or wep:GetClass() ~= "character_omniman" then return end

    -- local thirdpersonEnabled = GetConVar("omniman_thirdperson_enabled"):GetInt() == 1
    local thirdpersonEnabled = true

    if !thirdpersonEnabled then
        if wep.CreateFirstPersonMdl and ( !IsValid(wep.m_FirstPersonPlayerModel) ) then
            wep:CreateFirstPersonMdl(ply)
        end

        return FirstPerson( ply, pos, angles, fov, wep )
    else
        return ThirdPerson( ply, pos, angles, fov, wep )
    end
end
hook.Add( "CalcView", "OmniMan.ThirdPerson", OmniManCam )

local function SuperFlightDontDrawPlayer( ply )
    local wep = ply:GetActiveWeapon()
    if !IsValid( wep ) or wep:GetClass() ~= "character_omniman" then return end

    return wep:IsSuperFlying()
end
hook.Add( "PrePlayerDraw", "OmniMan.SuperFlightDontDrawPlayer", SuperFlightDontDrawPlayer )
---

local hide = {
    ["CHudAmmo"] = true,
    ["CHudSecondaryAmmo"] = true
}

function SWEP:HUDShouldDraw(name)
	if ( hide[ name ] ) then
		return false
	end
end

function SWEP:DrawHUD()
end

function SWEP:GetViewModelPosition(pos, ang)
	pos = EyePos()
	return pos, ang
end

function SWEP:AdjustMouseSensitivity()
    if self:IsSuperFlying() then
        return GetConVar("omniman_cfg_superflight_sensitivity"):GetFloat() or 0.3
    end
end

---
local ActIndex = {
	[ "pistol" ]		= ACT_HL2MP_IDLE_PISTOL,
	[ "smg" ]			= ACT_HL2MP_IDLE_SMG1,
	[ "grenade" ]		= ACT_HL2MP_IDLE_GRENADE,
	[ "ar2" ]			= ACT_HL2MP_IDLE_AR2,
	[ "shotgun" ]		= ACT_HL2MP_IDLE_SHOTGUN,
	[ "rpg" ]			= ACT_HL2MP_IDLE_RPG,
	[ "physgun" ]		= ACT_HL2MP_IDLE_PHYSGUN,
	[ "crossbow" ]		= ACT_HL2MP_IDLE_CROSSBOW,
	[ "melee" ]			= ACT_HL2MP_IDLE_MELEE,
	[ "slam" ]			= ACT_HL2MP_IDLE_SLAM,
	[ "normal" ]		= ACT_HL2MP_IDLE,
	[ "fist" ]			= ACT_HL2MP_IDLE_FIST,
	[ "melee2" ]		= ACT_HL2MP_IDLE_MELEE2,
	[ "passive" ]		= ACT_HL2MP_IDLE_PASSIVE,
	[ "knife" ]			= ACT_HL2MP_IDLE_KNIFE,
	[ "duel" ]			= ACT_HL2MP_IDLE_DUEL,
	[ "camera" ]		= ACT_HL2MP_IDLE_CAMERA,
	[ "magic" ]			= ACT_HL2MP_IDLE_MAGIC,
	[ "revolver" ]		= ACT_HL2MP_IDLE_REVOLVER
}
--
function SWEP:SetWeaponHoldType( t )
    local owner = self:GetOwner()
	t = string.lower( t )
	local index = ActIndex[ t ]

	if ( index == nil ) then
		t = "normal"
		index = ActIndex[ t ]
	end

    if !IsValid(owner) then return end
    
	self.ActivityTranslate = {}
	self.ActivityTranslate[ ACT_MP_STAND_IDLE ]					= index
	self.ActivityTranslate[ ACT_MP_WALK ]						= index + 1
	self.ActivityTranslate[ ACT_MP_RUN ]						= index + 2
	self.ActivityTranslate[ ACT_MP_CROUCH_IDLE ]				= index + 3
	self.ActivityTranslate[ ACT_MP_CROUCHWALK ]					= index + 4
    self.ActivityTranslate[ ACT_MP_ATTACK_STAND_PRIMARYFIRE ]	= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )
    self.ActivityTranslate[ ACT_MP_ATTACK_CROUCH_PRIMARYFIRE ]	= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )
    self.ActivityTranslate[ ACT_MP_RELOAD_STAND ]				= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )
    self.ActivityTranslate[ ACT_MP_RELOAD_CROUCH ]				= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )    
	self.ActivityTranslate[ ACT_MP_JUMP ]						= index + 7
	self.ActivityTranslate[ ACT_RANGE_ATTACK1 ]					= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )    
	self.ActivityTranslate[ ACT_MP_SWIM ]						= index + 9
    if ( t == "omniman" ) then
        self.ActivityTranslate[ ACT_MP_ATTACK_STAND_PRIMARYFIRE ]	= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )
        self.ActivityTranslate[ ACT_MP_ATTACK_CROUCH_PRIMARYFIRE ]	= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )
        self.ActivityTranslate[ ACT_MP_ATTACK_STAND_SECONDARYFIRE ]	= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )
        self.ActivityTranslate[ ACT_MP_ATTACK_CROUCH_SECONDARYFIRE ]	= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )
        self.ActivityTranslate[ ACT_MP_RELOAD_STAND ]				= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )
        self.ActivityTranslate[ ACT_MP_RELOAD_CROUCH ]				= owner:GetSequenceActivity( owner:LookupSequence( "flightdeploy" ) )    
    end

	-- "normal" jump animation doesn't exist
	if ( t == "normal" ) then
		self.ActivityTranslate[ ACT_MP_JUMP ] = ACT_HL2MP_JUMP_SLAM
	end
end

--
local effectData = {
    ["$pp_colour_addr"] = 0,
    ["$pp_colour_addg"] = 0,
    ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = 0.1,
    ["$pp_colour_contrast"] = 1.5,
    ["$pp_colour_colour"] = 0,
    ["$pp_colour_mulr"] = 0,
    ["$pp_colour_mulg"] = 0,
    ["$pp_colour_mulb"] = 0
}

local matGlow = Material("particle/particle_glow_04_additive") 
local matBorder = Material("effects/advisor_fx_003") 
function SWEP:ImpactFrame()
    if SERVER then return end

    -- LocalPlayer():ScreenFade( SCREENFADE.IN, Color( 0, 0, 0, 255 ), 0.2, 0 )

    local impactFrame = Action.Create( self, 0.2 )
    local renderScreenName = "OmniMan.ImpactFrame." .. impactFrame.ActionIndex
    local hudPaintName = "OmniMan.ImpactFrame." .. impactFrame.ActionIndex

    local oldW, oldH = ScrW(), ScrH()
    impactFrame:SetInit( function ()
        hook.Add( "RenderScreenspaceEffects", renderScreenName, function()
            surface.SetDrawColor(255, 255, 255, 255) 
            surface.SetMaterial(matGlow)
            
            local scale = 3
            local w, h = ScrW(), ScrH()
            local scaledW, scaledH = w * scale, h * scale
            local offsetX, offsetY = (w - scaledW) / 2, (h - scaledH) / 2
            
            -- surface.DrawTexturedRect(offsetX, offsetY, scaledW, scaledH)

            DrawSharpen( 1.6, 5 )
            DrawSobel( 0.1 )
        end )                    
    end)
    impactFrame:SetEnd( function ()
        hook.Remove( "RenderScreenspaceEffects", renderScreenName )
        -- hook.Remove( "HUDPaint", hudPaintName )
    end)      
    impactFrame:Start()          
end

---