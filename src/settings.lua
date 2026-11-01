-- Native Chef options. Defaults intentionally start fresh after the 2.6.0 backend change.
-- Configurations are updated only on option changes; the drawing loop reads one cached range.
return function(chef, log, ranges, show, look, targets)
    local S, configs, definitions, by_id = {}, {}, {}, {}
    local active = false
    local groups = {
        {'samples', 'Samples', 150}, {'supplies', 'Supplies', 150},
        {'mission', 'Mission items and objectives', 150}, {'objectives', 'Objective interactions', 150},
        {'hellbombs', 'Hellbombs', 300}, {'vehicles', 'Vehicles', 300}, {'deaths', 'Death marker', 1000},
    }
    local function classify(t)
        local g, n = t.group, t.name or ''
        if g == 'samples' or g == 'supplies' then return g, t.icon end
        if g == 'hellbombs' then return g, t.mission_only and 'mission_bomb' or 'damaged_bomb' end
        if g == 'vehicles' then return g, n:match('([^/]+)$') end
        if g == 'dropoffs' then return 'objectives', n:find('cargo_container', 1, true) and 'cargo' or 'dropoffs' end
        if g == 'controls' then
            return 'objectives', n:find('cooling', 1, true) and 'cooling_valves' or
                (n:find('crank', 1, true) and 'cranks' or 'valves')
        end
        if g == 'carry' then
            return 'mission', n:match('seaf_shell_([%w_]+)$') or
                (n:find('warhead', 1, true) and 'warheads' or 'batteries')
        end
        if g == 'mission' then
            if t.hex then return g, 'other_items' end
            for _, pair in ipairs({{'sarcophagus', 'alien_devices'}, {'black_box', 'black_boxes'},
                {'carry_data', 'data'}, {'larva', 'larva'}, {'briefcase', 'briefcases'},
                {'cy_generic_intel', 'keycards'}, {'generic_intel', 'launch_codes'},
                {'chemicals', 'chemicals'}, {'camera', 'cameras'}}) do
                if n:find(pair[1], 1, true) then return g, pair[2] end
            end
            return g, 'other_items'
        end
    end
    local labels = {
        common='Common samples', rare='Rare samples', super='Super samples', tube='Sample containers', egg='Terminid eggs',
        ammo='Ammo boxes', grenade='Grenade boxes', stim='Stims', supply='Resupply crates',
        alien_devices='Alien devices', black_boxes='Black boxes', data='SSSDs and data drives', larva='Larva containers',
        briefcases='Briefcases', keycards='Keycards', launch_codes='Launch codes', chemicals='Chemical containers',
        cameras='Video cameras', other_items='Other mission items', warheads='Warheads', batteries='Fusion batteries',
        regular='SEAF: explosive', high_yield='SEAF: high-yield explosive', napalm='SEAF: napalm',
        smoke='SEAF: smoke', static_field='SEAF: static field', mini_nuke='SEAF: mini-nuke',
        cargo='Cargo containers', dropoffs='Data drop-off points', cooling_valves='Cooling valves',
        cranks='Cranks', valves='Valves', mission_bomb='Mission Hellbombs', damaged_bomb='Damaged map Hellbombs',
        combat_walker='Exosuits', frv='FRVs', frv_flamer='Flamethrower FRVs', frv_supply='Supply FRVs',
        tank='Tanks', tank_storm='Storm tanks',
    }
    local order = {
        samples={'common','rare','super','tube','egg'}, supplies={'ammo','grenade','stim','supply'},
        mission={'data','black_boxes','larva','briefcases','launch_codes','keycards','cameras','chemicals',
            'alien_devices','other_items','regular','high_yield','napalm','smoke','static_field','mini_nuke','warheads','batteries'},
        objectives={'dropoffs','cargo','valves','cooling_valves','cranks'},
        hellbombs={'mission_bomb','damaged_bomb'}, vehicles={'combat_walker','frv','frv_flamer','frv_supply','tank','tank_storm'},
    }
    for _, t in ipairs(targets) do
        local g, id = classify(t)
        if id then
            local key = g .. '.' .. id
            if not by_id[key] then
                local c = {group=g, id=id, enabled=true, default=ranges[g], distance=ranges[g], range=ranges[g]}
                by_id[key], definitions[#definitions + 1] = c, c
            end
            configs[t] = by_id[key]
        end
    end
    local function refresh()
        for _, c in ipairs(definitions) do
            c.range = show[c.group] ~= false and c.enabled and c.distance or 0
        end
    end
    local function finite(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
    local function option(id, spec, apply)
        id = 'epir.' .. id
        local ok, value, why = pcall(chef.option, id, spec)
        if not ok or value == nil then
            log('settings: option registration failed: ' .. id .. ' ' .. tostring(ok and why or value))
            return
        end
        apply(value)
        pcall(chef.on_change, id, function(v) apply(v); refresh() end)
    end
    local function toggle(id, label, default, apply, heading, sub, hint)
        option(id, {type='toggle', label=label, default=default, heading=heading, sub=sub, hint=hint},
            function(v) if type(v) == 'boolean' then apply(v) end end)
    end
    local function slider(id, label, default, most, apply, hint, least)
        option(id, {type='slider', label=label, default=default, min=least or 0, max=most, step=5, hint=hint},
            function(v) if finite(v) then apply(math.max(least or 0, math.min(most, v))) end end)
    end
    function S.install()
        if type(chef) ~= 'table' then return false end
        for _, name in ipairs({'option', 'get', 'set', 'on_change'}) do
            if type(chef[name]) ~= 'function' then return false end
        end
        local headings = false
        if type(chef.has) == 'function' then
            local ok, value = pcall(chef.has, 'option_headings')
            headings = ok and value == true
        end
        for _, group in ipairs(groups) do
            local g, label, most = group[1], group[2], group[3]
            toggle('show_' .. g, 'Show ' .. (g == 'mission' and 'mission items' or label:lower()), true,
                function(v) show[g] = v end, headings and label or nil, g == 'objectives',
                'Master switch. Individual type choices are kept when this is off.')
            -- Bulk writes are a deliberate user action, never a side effect of loading saved defaults.
            slider('range_' .. g, g == 'deaths' and 'Death marker distance (m)' or
                'Set all ' .. (g == 'mission' and 'mission items' or label:lower()) .. ' distances (m)',
                ranges[g], most, function(v) ranges[g] = v end,
                g ~= 'deaths' and 'Changing this overwrites every type distance in this category. 0 hides markers.' or
                    'Only your last death is marked. Cleared when you reach it. 0 hides the marker.')
            pcall(chef.on_change, 'epir.range_' .. g, function(v)
                if not finite(v) then return end
                for _, c in ipairs(definitions) do
                    if c.group == g then chef.set('epir.' .. g .. '.' .. c.id .. '.distance', ranges[g]) end
                end
            end)
            if g == 'samples' or g == 'supplies' then
                local field = g == 'samples' and 'fade_samples' or 'fade'
                toggle(field, 'Fade markers with distance', look[field], function(v) look[field] = v end)
            end
            if g == 'hellbombs' then
                toggle('hellbomb_warning', 'Mission Hellbomb countdown and warning', true,
                    function(v) look.hellbomb_warning = v end, nil, nil,
                    'Estimated 15-second warning after observed activation. Damaged map bombs have no countdown.')
            end
            for _, id in ipairs(order[g] or {}) do
                local c = by_id[g .. '.' .. id]
                if c then
                    toggle(g .. '.' .. id .. '.show', 'Show ' .. labels[id], true, function(v) c.enabled = v end)
                    slider(g .. '.' .. id .. '.distance', labels[id] .. ' distance (m)', c.default, most,
                        function(v) c.distance = v end, '0 hides this type. Measured in metres.')
                end
            end
        end
        toggle('distance', 'Show vehicle, Hellbomb and death distances', look.distance,
            function(v) look.distance = v end, headings and 'Common appearance' or nil)
        toggle('hide_near', 'Hide markers where the game shows its own icon', look.hide_near,
            function(v) look.hide_near = v end, nil, nil, 'Off keeps markers visible up close, including with first-person camera mods.')
        slider('smallest_size', 'Marker size far away (%)', look.smallest * 100, 100,
            function(v) look.smallest = v / 100 end, 'Full size up to 10 m, shrinking toward the type distance.', 10)
        slider('opacity', 'Marker opacity (%)', look.opacity * 100, 100, function(v) look.opacity = v / 100 end,
            '100 is solid.', 10)
        active = true
        refresh()
        return true
    end
    function S.target_config(t) return active and configs[t] or nil end
    return S
end
