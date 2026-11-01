-- Read-only local-player identity and death observations. No camera/host fallback and no batched reads.
-- Schema evidence: NarrowHUD 597968c2b9e556812e0376b8a6627926df1f2524, Steam builds 26088801/26251122.
-- Written independently: only the game type/field identifiers are shared facts.
return function(chef, log)
    local P = {mode = 'legacy', status = 'network reads unavailable'}
    local BUILDS = {
        ['stingray:46659e176252a3ac4eb5436b25e7cef665a8c71afa243'] = true,
        ['stingray:46805437a3d445f9df7662b60086ac8ae3c65b5c95da6'] = true,
    }
    local PLAYER, AVATAR = 'un6y1d', 'vvhx8ga'
    local AVATAR_FIELD = 'u4d1h9a'
    local NO_OBJECT = 32767
    local SCAN_BATCH, RETRY_S, MAX_GAP_S = 32, 1, 0.5
    local schema, session, peer, player, scan, life, retry_at

    local function call(kind, name, ...)
        if type(chef) ~= 'table' or type(chef.call_kind) ~= 'function' then return nil end
        local result = {pcall(chef.call_kind, name, 'pickup_identity.' .. kind, ...)}
        if result[1] then return result[2] end
    end

    local function number(v)
        return type(v) == 'number' and v == v and math.abs(v) < 1e7
    end

    local function object_id(v)
        return number(v) and v >= 0 and v < NO_OBJECT and v == math.floor(v)
    end

    local function status(message)
        if P.status ~= message then
            P.status = message
            log('identity: ' .. message)
        end
    end

    function P.reset()
        session, peer, player, scan, life, retry_at = nil, nil, nil, nil, nil, nil
    end

    local build = call('build', 'Application.build_identifier')
    if type(build) ~= 'string' or not BUILDS[(string.gsub(build, '%s+', ''))] then
        status('legacy: no supported network schema for this build')
        function P.update() return nil end
        return P
    end
    -- From this point incomplete/ambiguous reads wait. They never adopt the camera's or the host's player.
    P.mode = 'network'

    local function field_id(v)
        if type(v) == 'number' and v == v and v >= 0 and v <= 4294967295 and v == math.floor(v) then
            return string.format('%08x', v)
        end
        if type(v) ~= 'string' then return nil end
        v = string.lower(v)
        v = string.gsub(v, '^0x', '')
        if not string.match(v, '^%x+$') or #v > 8 then return nil end
        return string.rep('0', 8 - #v) .. v
    end

    local function fields(kind, want)
        local info = call('schema.' .. kind, 'Network.object_info', kind)
        if type(info) ~= 'table' or type(info.fields) ~= 'table' then return false end
        local have = {}
        for _, f in pairs(info.fields) do
            if type(f) == 'table' then
                local id = field_id(f.id)
                if id then have[id] = true end
            end
        end
        for _, id in ipairs(want) do if not have[id] then return false end end
        return true
    end

    local function exists(id, kind)
        return object_id(id) and call('exists', 'GameSession.game_object_exists', session, id) == true
            and call('type.' .. kind, 'GameSession.game_object_is_type', session, id, kind) == true
    end

    local function read(id, kind, field)
        if not exists(id, kind) then return nil end
        return call(kind .. '.' .. field, 'GameSession.game_object_field', session, id, field)
    end

    local function my_player(id)
        return exists(id, PLAYER) and call('owner', 'GameSession.game_object_owner', session, id) == peer
    end

    local function find_player(now)
        if player ~= nil then
            if my_player(player) then return player end
            player, life, scan = nil, nil, nil
        end
        if scan == nil then
            if now < (retry_at or 0) then return nil end
            local ids = call('owned', 'GameSession.objects_owned_by', session, peer)
            retry_at = now + RETRY_S
            if type(ids) ~= 'table' then status('waiting for local player list'); return nil end
            local list, seen = {}, {}
            for _, id in pairs(ids) do
                if object_id(id) and not seen[id] then list[#list + 1], seen[id] = id, true end
            end
            scan = {ids = list, at = 1, matches = {}}
        end
        local last = math.min(#scan.ids, scan.at + SCAN_BATCH - 1)
        for i = scan.at, last do
            local id = scan.ids[i]
            if my_player(id) then scan.matches[#scan.matches + 1] = id end
        end
        scan.at = last + 1
        if scan.at <= #scan.ids then status('resolving local player'); return nil end
        if #scan.matches == 1 and my_player(scan.matches[1]) then
            player = scan.matches[1]
            status('local player confirmed')
        else
            status(#scan.matches > 1 and 'ambiguous local player; waiting' or 'local player not found; waiting')
        end
        scan = nil
        return player
    end

    local function position(v)
        if v == nil then return nil end
        local ok, x, y, z = pcall(function()
            -- Convert engine vectors immediately; never retain one across frames.
            local sr = rawget(_G, 'stingray')
            return sr.Vector3.x(v), sr.Vector3.y(v), sr.Vector3.z(v)
        end)
        if ok and number(x) and number(y) and number(z) then return {x, y, z} end
    end

    local function terminal(avatar, now)
        if not life or life.avatar ~= avatar or not life.hp or life.hp <= 0 or not life.position
            or not life.at or now < life.at or now - life.at > MAX_GAP_S then return nil end
        local hp = read(avatar, AVATAR, 'health')
        if number(hp) and hp <= 0 then
            local v = life.position
            return {v[1], v[2], v[3]}
        end
    end

    function P.update(now, in_mission)
        if not in_mission then P.reset(); return nil end
        if schema ~= true then
            if now < (retry_at or 0) then return nil end
            retry_at = now + RETRY_S
            -- Upper 32 bits of the game's Murmur64 string ids. Check declared fields before any field read.
            schema = fields(PLAYER, {'0f27c68e'}) and fields(AVATAR, {'cb0453ea', '8bbeb160'})
            if not schema then status('network schema unavailable; waiting'); return nil end
            retry_at = nil
        end
        local s = call('session', 'Network.game_session')
        local p = call('peer', 'Network.peer_id')
        if s == nil or p == nil then
            P.reset()
            status('waiting for local session')
            return nil
        end
        if s ~= session or p ~= peer then
            P.reset()
            session, peer = s, p
        end
        if find_player(now) == nil then return nil end
        local av = read(player, PLAYER, AVATAR_FIELD)
        -- The player can clear/replace its avatar reference before the final health sample. Only an explicit
        -- reference change permits one guarded health read of the previously confirmed local avatar. A nil
        -- reference is a refused/missing read and proves nothing.
        local ended
        if av ~= nil and life and life.avatar ~= av then ended = terminal(life.avatar, now) end
        if not object_id(av) or not exists(av, AVATAR) then
            -- Missing/refused reads are not death. Keep only numeric history, break the health transition.
            if life then life.hp, life.at = nil, nil end
            status('waiting for local avatar')
            return ended and {death = ended} or nil
        end
        local hp = read(av, AVATAR, 'health')
        if not number(hp) then
            if life then life.hp, life.at = nil, nil end
            status('local health unavailable; waiting')
            return ended and {death = ended} or nil
        end
        if not life or life.avatar ~= av then life = {avatar = av} end
        local observed = {avatar = av, alive = hp > 0, death = ended}
        if hp > 0 then
            local pos = position(read(av, AVATAR, 'position'))
            if pos then life.position, observed.position = pos, pos else life.position = nil end
        elseif life.hp and life.hp > 0 and life.position and life.at and now >= life.at and now - life.at <= MAX_GAP_S then
            local v = life.position
            observed.death = {v[1], v[2], v[3]}  -- freeze the last living position, before ragdoll/despawn motion
        end
        life.hp, life.at = hp, now
        status('local player confirmed')
        return observed
    end
    return P
end
