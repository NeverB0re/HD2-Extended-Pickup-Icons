-- Fixed-mission Hellbomb warning. Observe the replicated visual layer, never player input.
-- Installed graph: layer 2, top_retracted (1) -> top_extend (0), hellbomb_activate. Fuse is an estimate.
return function(chef, log)
    local H = {}
    -- Extracted hellbomb_activate clip: 5 s. Allow that visual deployment plus the requested 10 s fuse.
    -- Locally timed from the observed animation transition; not a replicated detonation deadline.
    local DURATION = 15
    local RESOURCE = 'content/fac_helldivers/hellpod/hellbomb/hellbomb'
    local states = setmetatable({}, {__mode = 'k'})
    local function call(name, kind, ...)
        if type(chef) ~= 'table' or type(chef.call_kind) ~= 'function' then return nil end
        local ok, a, b, c = pcall(chef.call_kind, name, kind, ...)
        if ok then return a, b, c end
    end
    local function alive(u)
        if u == nil or type(chef) ~= 'table' or type(chef.unit_alive) ~= 'function' then return false end
        local ok, value = pcall(chef.unit_alive, u)
        return ok and value == true
    end
    local build = call('Application.build_identifier', 'hellbomb_countdown.build')
    H.enabled = type(build) == 'string' and string.gsub(build, '%s+', '') ==
        'stingray:46805437a3d445f9df7662b60086ac8ae3c65b5c95da6'
    if not H.enabled then log('hellbomb countdown: no verified animation graph for this build - ordinary markers only') end

    function H.reset() states = setmetatable({}, {__mode = 'k'}) end
    function H.forget(u) if u ~= nil then states[u] = nil end end
    function H.observe(p, now, visible)
        if not H.enabled or p.kind ~= RESOURCE or visible ~= true then return nil end
        local u = p.unit
        if not alive(u) then H.forget(u); return nil end
        local state = states[u]
        if not state then state = {next_at = now}; states[u] = state end
        if state.warning then return state.warning end -- never ask an armed/detonating unit its animation again
        if now < state.next_at then return nil end
        state.next_at = now + 0.2 -- at most five guarded observations/s, this one resource only
        local machine = call('Unit.has_animation_state_machine', p.kind, u)
        if machine ~= true or not alive(u) then
            state.top, state.at, state.next_at = nil, nil, now + 1
            return nil
        end
        local base, top, bridge = call('Unit.animation_get_state', p.kind, u)
        if not alive(u) then H.forget(u); return nil end
        -- Refused/missing/malformed tuples cannot become state zero. Do not infer undocumented tuple layouts.
        if type(base) ~= 'number' or base ~= math.floor(base) or base < 0 or base > 3 or
            (top ~= 0 and top ~= 1) or (bridge ~= 0 and bridge ~= 1) then
            state.top, state.at, state.next_at = nil, nil, now + 1
            if not state.noted then
                state.noted = true
                log('hellbomb countdown: animation tuple unavailable/unrecognized - no guessed timer')
            end
            return nil
        end
        if top == 0 then
            local fresh_transition = state.top == 1 and state.at ~= nil and now - state.at <= 0.5
            state.warning = fresh_transition and {started = now, deadline = now + DURATION} or {unknown = true}
            log(fresh_transition and 'hellbomb countdown: activation layer transition - calibrated estimate 15 s' or
                'hellbomb countdown: first seen activated - remaining time unknown')
            return state.warning
        end
        state.top, state.at = top, now
        return nil
    end

    function H.visual(warning, now)
        if not warning then return nil end
        if warning.unknown then return {label = 'ARMED', rgb = {255, 150, 35}, alpha = 1, scale = 1.2} end
        local elapsed = math.max(0, now - warning.started)
        local progress = math.min(1, elapsed / DURATION)
        -- The derivative of this phase rises from 1 to 4 Hz over the full estimate.
        local t = math.min(elapsed, DURATION)
        local phase = t + 1.5 * t * t / DURATION + math.max(0, elapsed - DURATION) * 4
        local pulse = 0.5 + 0.5 * math.cos(2 * math.pi * phase)
        local remaining = math.max(0, warning.deadline - now)
        local centiseconds = math.max(0, math.ceil(remaining * 100 - 1e-7))
        return {label = string.format('%02d:%02d', math.floor(centiseconds / 100), centiseconds % 100),
            rgb = {255, math.floor(180 * (1 - progress)), math.floor(35 * (1 - progress))},
            alpha = 0.4 + 0.6 * pulse, scale = 1.18 + 0.18 * pulse}
    end
    return H
end
