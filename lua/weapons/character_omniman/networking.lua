if SERVER then
    util.AddNetworkString("OmniMan.Network.SuperFlyingOnHit")
    util.AddNetworkString("OmniMan.Network.NormalPunchHit")
    util.AddNetworkString("OmniMan.Network.ChargedPunchHit")
    util.AddNetworkString("OmniMan.Network.GrabSuccesful")
    util.AddNetworkString("OmniMan.Network.UnGrab")
    util.AddNetworkString("OmniMan.Network.HandleOmniClap")
end

if CLIENT then
    net.Receive("OmniMan.Network.NormalPunchHit", function (len, ply)
        local omniman = net.ReadEntity()
        local trace = util.JSONToTable(net.ReadString())

        omniman:HandleNormalPunch(trace)
    end)
    net.Receive("OmniMan.Network.ChargedPunchHit", function (len, ply)
        local omniman = net.ReadEntity()
        local trace = util.JSONToTable(net.ReadString())
        local power = net.ReadFloat()

        omniman:HandleChargedPunch(trace, power)
    end)
    net.Receive("OmniMan.Network.SuperFlyingOnHit", function (len, ply)
        local omniman = net.ReadEntity()
        local trace = util.JSONToTable(net.ReadString())

        omniman:SuperFlyingOnHit(trace)
    end)
    net.Receive("OmniMan.Network.GrabSuccesful", function (len, ply)
        local omniman = net.ReadEntity()
        local trace = net.ReadTable()

        omniman:GrabSuccesful(trace)
    end)
    net.Receive("OmniMan.Network.UnGrab", function (len, ply)
        local omniman = net.ReadEntity()

        omniman:UnGrab()
    end)
    net.Receive("OmniMan.Network.HandleOmniClap", function (len, ply)
        local omniman = net.ReadEntity()

        omniman:HandleOmniClap()
    end)
end