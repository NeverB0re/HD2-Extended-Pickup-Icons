-- HD2-Addon: mods/codex/pickup_icon_range_supplies
local choices = rawget(_G, 'CodexPickupIconChoices')
if type(choices) ~= 'table' then
    choices = {}
    rawset(_G, 'CodexPickupIconChoices', choices)
end
choices.supplies = true
