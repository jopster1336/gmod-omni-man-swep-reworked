--This code was borrowed from UClip, huge thanks to the original creators.

local Player = FindMetaTable("Player")

local function isStuck( ply, filter )
	local ang = ply:EyeAngles()
	local directions = {
		ang:Right(),
		ang:Right() * -1,
		ang:Forward(),
		ang:Forward() * -1,
		ang:Up(),
		ang:Up() * -1,
	}
	local ents = {}

	local t = {}
	t.start = ply:GetPos()
	t.filter = filter

	-- Check if they're stuck by checking each direction. A minimum number of directions should hit the same object if they're stuck.
	for _, dir in ipairs( directions ) do
		t.endpos = ply:GetPos() + dir
		local tr = util.TraceEntity( t, ply )
		if tr.Entity:IsValid() and tr.HitPos == tr.StartPos then
			ents[ tr.Entity ] = ents[ tr.Entity ] or 0
			ents[ tr.Entity ] = ents[ tr.Entity ] + 1
		end
	end

	for ent, hits in pairs( ents ) do
		if hits >= 4 then
			return true, ent
		end
	end

	return false
end

-- This function allows us to get the player's *attempted* velocity (incase we're overriding their *actual* velocity).
local function getFlyingVel( ply )
	local forward = ply:KeyDown( IN_FORWARD )
	local back = ply:KeyDown( IN_BACK )
	local left = ply:KeyDown( IN_MOVELEFT )
	local right = ply:KeyDown( IN_MOVERIGHT )
	local jump = ply:KeyDown( IN_JUMP )
	local duck = ply:KeyDown( IN_DUCK )
	local speed = ply:KeyDown( IN_SPEED )

	-- Convert the input to numbers so we can perform arithmetic on them, to make the code smaller and neater.
	local forwardnum = forward and 1 or 0
	local backnum = back and 1 or 0
	local leftnum = left and 1 or 0
	local rightnum = right and 1 or 0
	local jumpnum = jump and 1 or 0
	local ducknum = duck and 1 or 0
	local speednum = speed and 1 or 0

	local vel = Vector( 0, 0, 0 )

    local wep = ply:GetActiveWeapon()
	local flyingSpeed = wep:GetFlyingSpeed()

    if wep:IsSuperFlying() then
        vel = vel + ( ply:EyeAngles():Forward() * 1 )
        vel = vel:GetNormalized()
        vel = vel * flyingSpeed * 0.9
    else
        vel = vel + ( ply:EyeAngles():Forward() * ( forwardnum - backnum ) ) -- Forward and back
        vel = vel + ( ply:EyeAngles():Right() * ( rightnum - leftnum ) ) -- Left and right
        vel = vel + ( Vector( 0, 0, 1 ) * jumpnum ) -- Up
        vel = vel + ( Vector( 0, 0, -1 ) * ducknum ) -- Down
        vel = vel:GetNormalized()
        vel = vel * flyingSpeed * 0.9

        if speed then
            vel = vel * 1.8
        end
    end

	return vel

end

-- Given a velocity, normalized velocity, and a normal:
-- Calculate the velocity toward the wall and remove it so we can "slide" across the wall.
local function calcWallSlide( vel, normal )
	local toWall = normal * -1
	local velToWall = vel:Dot( toWall ) * toWall
	return vel - velToWall
end

SWEP.m_OverrideVelocity = vector_origin -- This will be set as the current desired velocity, so we can later perform the movement manually.

local function zeromove(ply)
	ply:GetActiveWeapon().m_OverrideVelocity = Vector( 0, 0, 0 )
end


local maxrecurse = 4 -- Max recurses. Recursion is used when we need to test a new velocity.
-- Should rarely recurse more than twice or else objects are probably wedged together.
-- (We have checks for wedged objects too so don't worry about it). 0 = disable (not recommended but shouldn't have any problems)

local maxloop = 50 -- Max loops. We need to loop to find objects behind other objects. 0 = infinite (not recommended but shouldn't have any problems)
-- This *could* open an exploit, but users would be hard pressed to use it... so we'll see.

-- The brain of Uclip, this makes sure they can move where they want to.
local function checkVel( ply, move, vel, recurse, hitnorms )

	if vel == Vector( 0, 0, 0 ) then return end -- No velocity, don't bother.

	local ft = FrameTime()

	local veln = vel:GetNormalized()
	hitnorms = hitnorms or {} -- This is used so we won't process the same normal more than once. (IE, we don't get a wedge where we have to process velocity to 0)

	recurse = recurse or 0 -- Keep track of how many recurses
	recurse = recurse + 1
	if recurse > maxrecurse and maxrecurse > 0 then -- Hard break
		zeromove(ply)
		return
	end

	local t = {}
	t.start = ply:GetPos()
	t.endpos = ply:GetPos() + vel * ft + veln -- Add an extra unit in the direction they're headed just to be safe.
	t.filter = table.Merge({ ply, ply:GetActiveWeapon():GetGrabbedVictim() }, table.GetKeys(ply:GetActiveWeapon().m_NextDamageTime) )
	local tr = util.TraceEntity( t, ply )
	local loops = 0
	while tr.Hit do -- Recursively check all the hits. This is so we don't miss objects behind another object.
		loops = loops + 1
		if maxloop > 0 and loops > maxloop then
			zeromove(ply)
			return
		end

		if tr.HitWorld or ( tr.Entity:IsValid() and (tr.Entity:GetClass() == "prop_dynamic" or ( not isStuck( ply, t.filter ))) ) then -- If world or a prop they don't own that they're not stuck inside. Ignore prop_dynamic due to crash.
			local slide = calcWallSlide( vel, tr.HitNormal )
			ply:GetActiveWeapon().m_OverrideVelocity = slide

			if table.HasValue( hitnorms, tr.HitNormal ) then -- We've already processed this normal. We can get this case when the player's noclipping into a wedge.
				zeromove(ply)
				return
			end
			table.insert( hitnorms, tr.HitNormal )

			return checkVel( ply, move, slide, recurse, hitnorms ) -- Return now so this func isn't left on stack
		end

		if tr.Entity and tr.Entity:IsValid() then -- Ent to add!
			table.insert( t.filter, tr.Entity )
		end

		tr = util.TraceEntity( t, ply )
	end
end

local function move( ply, move )
    local wep = ply:GetActiveWeapon()
	if !IsValid( wep ) or wep:GetClass() ~= "character_omniman" or !wep.GetIsFlying or (!wep:GetIsFlying()) then return end

	local ft = FrameTime()
	local vel = getFlyingVel( ply ) -- How far are they trying to move this frame?

	-- wep.m_OverrideVelocity = (wep.m_OverrideVelocity) and LerpVector( ft, wep.m_OverrideVelocity, vel ) or vel
	wep.m_OverrideVelocity = vel
	vel = wep.m_OverrideVelocity

	checkVel( ply, move, vel )

	if wep.m_OverrideVelocity ~= vector_origin then
		move:SetOrigin( move:GetOrigin() + ( wep.m_OverrideVelocity * ft ) ) -- This actually performs the movement.
	end
	move:SetVelocity( wep.m_OverrideVelocity ) -- This doesn't actually move the player (thanks to garry), it just allows other code to detect the player's velocity.

	return true -- Completely disable any engine movement, because we're doing it ourselves.

end

hook.Add( "Move", "OmniMan.Flying.Handle", move )