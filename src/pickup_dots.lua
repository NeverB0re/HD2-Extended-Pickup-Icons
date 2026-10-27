-- HD2-Addon: mods/codex/pickup_dots
-- Extended Pickup Icons Range (Pickup Dots): markers over samples, supplies, mission items and vehicles near you.
-- Lua-only rebuild of Extended Pickup Icons for Chef Shared Loader (PUC Lua 5.1, no ffi).
-- It only reads unit positions and draws on the screen; it changes no game state.
--
-- 0.1.0 crashed the game on entering the ship: an access violation inside a native call made
-- from Lua, right after a world appeared. The likeliest cause is World.units_by_resource on a
-- unit resource that is not loaded in that world (the ship has no mission items loaded). So:
--   * a resource is looked up only if Application.can_get says it is loaded; without can_get,
--     no target is looked up at all and the log says so;
--   * nothing is looked up until a world has settled and a helldiver is in it.

local MOD_KEY = 'CodexPickupDots'
if rawget(_G, MOD_KEY) then return rawget(_G, MOD_KEY) end

-- Chef Shared Loader (Nexus 17760) hands its helpers in: the game's own camera, guarded engine calls, units and
-- their nodes, whether this is a mission, and drawing on the screen (shapes, text in the game's font, textures
-- of the mod's patch). 2.4.0: the mod runs on them alone (CHEF_NEEDS).
local CHEF = ...
if type(CHEF) ~= 'table' then CHEF = nil end
local CHEF_NEEDS = {'camera', 'call', 'call_kind', 'unit_alive', 'unit_position', 'unit_node', 'in_mission',
                    'screen', 'color', 'rect', 'triangle', 'bitmap', 'text', 'text_width'}

local VERSION = '2.4.0-test.7'
local M = {version = VERSION, status = 'starting'}
rawset(_G, MOD_KEY, M)

-- ------------------------------------------------------------------ settings --
local RANGE = {samples = 50, supplies = 25, mission = 50, objectives = 50, hellbombs = 100, vehicles = 100}   -- metres, settings
local SHOW = {}               -- a setting per kind: false hides it (nil or true: shown)
-- The groups the settings take together (2.2.0): what you carry with mission items, drop-off points with valves.
local SETTING_OF = {carry = 'mission', dropoffs = 'objectives', controls = 'objectives'}
local function setting_of(group) return SETTING_OF[group] or group end
local NEAR_ME = {samples = 9, supplies = 4}   -- this close to you: no marker (the game shows its own icon;
                                               -- a target's own 'near' overrides it; 0: always a marker)
local NEAR_OVERLAP = 0.5      -- metres: ours goes this much inside where the game's icon comes (no gap between)
local ICON_OFFSET = {-28, -35}   -- pixels right and up: sample and supply markers sit where the game's icon does
local LOOK = {                -- settings (2.1.0)
    hide_near = true,         -- false: markers stay on where the game shows its own icon (NEAR_ME)
    smallest = 0.7,           -- size at the edge of a kind's range (full size up to FULL_SIZE_M)
    opacity = 1,              -- 0..1
    fade = true,              -- supplies fainter with distance, down to FADE_LEAST of opacity at the edge
    distance = true,          -- the distance above a vehicle's or hellbomb's marker, in the game's font
}
-- The game's icons as textures of the mod's own patch (2.4.0; tools/bake_icons.py, packed by build.py): icon name ->
-- its sizes, smallest first, each {size along the longer side (pixels), texture id, width, height}. Chef Shared
-- Loader's chef.bitmap draws them.
local ICON_TEX = "@ICONS@"
-- How big each is drawn at full size on a 1080-line screen, along its longer side (pixels): as the 2.3.0 pixel icons
-- (made to match the game's); the framed ones (the stratagem icons' red corners around them) a little bigger, the
-- vehicles' 15% more again
local ICON_SIZE = {ammo = 19, grenade = 22, stim = 27, egg = 20, tube = 20, common = 18, rare = 18, super = 18,
                   package = 28, larva = 28, hellbomb = 28, tank = 34.5, car = 34.5, walker = 34.5}
local VEHICLE_RGB = {110, 205, 255}   -- vehicles: the sky blue of the HUD's support weapon icons
local HELLBOMB_RGB = {255, 90, 70}    -- hellbombs lying about the map (2.3.0): red, they blow up when shot
-- The icons (all white textures) drawn in a colour: the vehicles and what you carry on your back sky blue (2.3.0),
-- the hellbomb red
local ICON_RGB = {package = VEHICLE_RGB, larva = VEHICLE_RGB, tank = VEHICLE_RGB, car = VEHICLE_RGB, walker = VEHICLE_RGB,
                  hellbomb = HELLBOMB_RGB}
local GROUP_RGB = {vehicles = VEHICLE_RGB, hellbombs = HELLBOMB_RGB}   -- their shapes (V, arrow), and the distance
                                                                       -- above them (2.4.0: hellbombs too)
local DISTANCE_PX = 1.6       -- the loader's text size at 1080 pixels of screen (8 drew far too big)
local BOLD = {{0, 0}, {1, 0}, {0, 1}, {1, 1}}   -- the distance drawn at each, in the loader's screen pixels
local DOT_HEIGHT = 0.6        -- metres above the unit's origin
-- Above a target's node (its 'node': where the game shows its interact icon), instead: icons as high above it as
-- above a sample's root, diamonds as DOT_HEIGHT (a drop-off's is 1.2 m up: 1.8, as GROUP_HEIGHT had it)
local ABOVE_NODE = {samples = 0.3, supplies = 0.3}
local GROUP_HEIGHT = {samples = 0.3, supplies = 0.3, dropoffs = 1.8, controls = 1.2, hellbombs = 3, vehicles = 3.2}
                              -- icons (samples, supplies) sit lower than diamonds   -- these stand taller: the marker goes above them
local VEHICLE_BUSY = 4        -- a helldiver this close to a vehicle's origin is in it: no marker while it moves,
                              -- and none ever while you are this close
local VEHICLE_PARKED_S = 3    -- a vehicle that has not moved this long is parked: teammates beside it do not hide it
local WRECK_NEAR = 4          -- an exosuit this close to an exosuit wreck is that wreck
local ARMS_NEAR = 5           -- a vehicle's weapon units (group 'arms') are this close to it
-- 2.3.0: a destroyed supply FRV's gun (and maybe a tank's turret) comes off and may lie beside it, still within
-- ARMS_NEAR. So how far its nearest weapon is from the point it is mounted at (the vehicle's 'mount' node, else
-- its root: two points of one body, the same however it leans) is kept; off by more than ARM_MOVED: come off,
-- destroyed. 2.4.0: vehicles and weapons are read in the same frame while a vehicle is near (READ_TOGETHER), so
-- this holds while it moves too: a wreck rolling or flung, a vehicle falling from orbit (2.3.0 waited for it to
-- stand still, as weapons read on other frames lagged metres behind it, and lost its marker late).
local ARM_MOVED = 0.6
local READ_TOGETHER = {vehicles = true, arms = true, wrecks = true}
local DELIVERED_NEAR = 3      -- a mission item or load this close to a drop-off is in it (an SSSD put in)
local LOADED_NEAR = 1         -- an artillery shell this close to a ready rack (group 'loaders', not drawn) is in it
local VERTICAL_FOV = 50       -- degrees, used when the game's setting cannot be read
local GAME_FOV_EVERY_S = 10   -- how often the game's settings file is read again
local SCREEN_DIAMOND = 7.92   -- screen diamond half-height, pixels (0.11: 20% smaller; 2.1.0: 10% bigger)
local SCREEN_LINE = 2         -- screen diamond outline thickness, pixels
local CHEF_LAYER = 900        -- Chef Shared Loader's layer for them (under the game's HUD and menus)

-- The resupply crate's icon (no texture of the game's matches it), pixel for pixel at its size on screen, from a
-- screenshot of the icon (2.4.0: the other icons are the game's textures, ICON_TEX). In every size a pixel apart
-- along its longest side, from full
-- down to SMALLEST, as rectangles
-- {x0, y0, x1, y1, coverage in quarters} in whole pixels around the item (y up), drawn that see-through,
-- as the game draws its scaled icon (scaled from those images).
local ICON_PIXELS = {
    supply = {
        {{-10, 7, -9, 8, 1}, {-10, 8, -9, 9, 3}, {-9, 6, -8, 7, 3}, {-9, 7, -4, 9, 4}, {-8, 4, -7, 5, 2}, {-8, 5, -4, 7, 4}, {-7, -3, -6, 2, 1}, {-7, 3, -6, 4, 3}, {-7, 4, -4, 5, 4}, {-6, -4, 0, -3, 3}, {-6, -3, 0, 0, 4}, {-6, 0, -4, 2, 4}, {-6, 3, -4, 4, 4}, {-4, 0, -2, 1, 1}, {-4, 3, -2, 9, 2}, {-2, -6, -1, -5, 3}, {-2, -5, 3, -4, 1}, {-2, 0, 0, 2, 4}, {-2, 2, 0, 3, 1}, {-2, 3, 3, 7, 4}, {-2, 7, -1, 9, 4}, {-1, -8, 0, -7, 2}, {-1, -7, 2, -5, 4}, {-1, 7, 0, 9, 2}, {0, -9, 1, -8, 3}, {0, -8, 1, -7, 4}, {0, -3, 1, 2, 1}, {1, -8, 2, -7, 2}, {1, -4, 7, -3, 3}, {1, -3, 7, 0, 4}, {1, 0, 3, 2, 4}, {1, 2, 3, 3, 1}, {1, 7, 2, 9, 2}, {2, -6, 3, -5, 3}, {2, 7, 3, 9, 4}, {3, 0, 5, 1, 1}, {3, 3, 5, 9, 2}, {5, 0, 7, 2, 4}, {5, 3, 7, 4, 4}, {5, 4, 8, 5, 4}, {5, 5, 9, 7, 4}, {5, 7, 10, 9, 4}, {7, -3, 8, 2, 1}, {7, 3, 8, 4, 3}, {8, 4, 9, 5, 2}, {9, 6, 10, 7, 3}, {10, 7, 11, 8, 1}, {10, 8, 11, 9, 3}},
        {{-10, 7, -9, 8, 1}, {-10, 8, -9, 9, 3}, {-9, 5, -8, 6, 1}, {-9, 6, -8, 7, 3}, {-9, 7, -4, 9, 4}, {-8, 4, -7, 5, 2}, {-8, 5, -4, 7, 4}, {-7, -4, -6, 2, 1}, {-7, 3, -6, 4, 3}, {-7, 4, -4, 5, 4}, {-6, -4, -1, -3, 3}, {-6, -3, -1, 0, 4}, {-6, 0, -5, 2, 4}, {-6, 3, -4, 4, 4}, {-5, 0, -4, 2, 3}, {-4, 0, -3, 1, 1}, {-4, 3, -3, 9, 1}, {-3, 0, -2, 2, 2}, {-3, 3, -2, 9, 3}, {-2, -7, -1, -6, 2}, {-2, -6, 2, -5, 4}, {-2, -5, 2, -4, 1}, {-2, 0, -1, 2, 4}, {-2, 2, -1, 3, 1}, {-2, 3, 2, 4, 4}, {-2, 4, 3, 7, 4}, {-2, 7, -1, 9, 4}, {-1, -9, 1, -8, 2}, {-1, -8, 1, -6, 4}, {-1, -4, 1, 2, 2}, {-1, 7, 1, 8, 1}, {-1, 8, 0, 9, 1}, {1, -7, 2, -6, 2}, {1, -4, 6, -3, 3}, {1, -3, 6, 0, 4}, {1, 0, 2, 2, 4}, {1, 2, 2, 3, 1}, {1, 7, 3, 9, 4}, {2, 0, 3, 2, 2}, {2, 3, 3, 4, 3}, {3, 0, 4, 1, 1}, {3, 3, 4, 9, 1}, {4, 0, 5, 2, 3}, {4, 3, 6, 4, 4}, {4, 4, 7, 5, 4}, {4, 5, 8, 7, 4}, {4, 7, 9, 9, 4}, {5, 0, 6, 2, 4}, {6, -4, 7, 2, 1}, {6, 3, 7, 4, 3}, {7, 4, 8, 5, 2}, {8, 5, 9, 6, 1}, {8, 6, 9, 7, 3}, {9, 7, 10, 8, 1}, {9, 8, 10, 9, 3}},
        {{-9, 6, -8, 7, 1}, {-9, 7, -8, 8, 3}, {-8, 4, -7, 5, 1}, {-8, 5, -7, 6, 3}, {-8, 6, -4, 8, 4}, {-7, 3, -6, 4, 2}, {-7, 4, -4, 6, 4}, {-6, -4, -5, 1, 2}, {-6, 1, -5, 2, 1}, {-6, 2, -3, 3, 2}, {-6, 3, -4, 4, 4}, {-5, -4, 0, -1, 4}, {-5, -1, -4, 1, 4}, {-5, 1, -4, 2, 2}, {-4, -1, -2, 0, 3}, {-4, 0, -3, 1, 2}, {-4, 1, -3, 2, 1}, {-4, 3, -3, 8, 3}, {-3, 2, -2, 8, 1}, {-2, -6, -1, -5, 2}, {-2, -5, 0, -4, 1}, {-2, -1, 0, 0, 4}, {-2, 0, -1, 1, 3}, {-2, 1, 0, 2, 2}, {-2, 2, 3, 3, 3}, {-2, 3, 3, 6, 4}, {-2, 6, -1, 8, 4}, {-1, -8, 0, -7, 2}, {-1, -7, 2, -5, 4}, {-1, 0, 0, 1, 4}, {-1, 6, 0, 8, 3}, {0, -9, 1, -8, 3}, {0, -8, 1, -7, 4}, {0, -4, 1, 1, 1}, {0, 6, 1, 7, 1}, {1, -8, 2, -7, 2}, {1, -5, 3, -4, 1}, {1, -4, 6, -1, 4}, {1, -1, 3, 0, 4}, {1, 0, 2, 1, 4}, {1, 1, 3, 2, 2}, {1, 6, 2, 7, 3}, {1, 7, 2, 8, 2}, {2, -6, 3, -5, 2}, {2, 0, 3, 1, 3}, {2, 6, 3, 8, 4}, {3, -1, 5, 0, 3}, {3, 2, 4, 8, 1}, {4, 0, 5, 1, 2}, {4, 1, 5, 2, 1}, {4, 2, 7, 3, 2}, {4, 3, 5, 8, 3}, {5, -1, 6, 1, 4}, {5, 1, 6, 2, 2}, {5, 3, 7, 4, 4}, {5, 4, 8, 6, 4}, {5, 6, 9, 8, 4}, {6, -4, 7, 1, 2}, {6, 1, 7, 2, 1}, {7, 3, 8, 4, 2}, {8, 4, 9, 5, 1}, {8, 5, 9, 6, 3}, {9, 6, 10, 7, 1}, {9, 7, 10, 8, 3}},
        {{-9, 6, -8, 7, 1}, {-9, 7, -8, 8, 3}, {-8, 4, -7, 5, 1}, {-8, 5, -7, 6, 3}, {-8, 6, -4, 8, 4}, {-7, 3, -6, 4, 2}, {-7, 4, -4, 6, 4}, {-6, -4, -5, -3, 1}, {-6, -3, -5, 1, 3}, {-6, 1, -5, 2, 2}, {-6, 2, 6, 3, 1}, {-6, 3, -4, 4, 4}, {-5, -4, -1, -3, 2}, {-5, -3, -1, 0, 4}, {-5, 0, -4, 1, 4}, {-5, 1, -4, 2, 3}, {-4, 0, -2, 2, 1}, {-4, 3, -2, 8, 2}, {-2, -6, -1, -5, 2}, {-2, -5, 2, -4, 3}, {-2, 0, -1, 1, 4}, {-2, 1, -1, 2, 3}, {-2, 3, 2, 6, 4}, {-2, 6, -1, 8, 4}, {-1, -8, 1, -7, 2}, {-1, -7, 1, -5, 4}, {-1, -4, 1, -3, 1}, {-1, -3, 1, 1, 3}, {-1, 1, 1, 2, 2}, {-1, 6, 1, 7, 2}, {-1, 7, 1, 8, 1}, {1, -6, 2, -5, 2}, {1, -4, 5, -3, 2}, {1, -3, 5, 0, 4}, {1, 0, 2, 1, 4}, {1, 1, 2, 2, 3}, {1, 6, 2, 8, 4}, {2, 0, 4, 2, 1}, {2, 3, 4, 8, 2}, {4, 0, 5, 1, 4}, {4, 1, 5, 2, 3}, {4, 3, 6, 4, 4}, {4, 4, 7, 6, 4}, {4, 6, 8, 8, 4}, {5, -4, 6, -3, 1}, {5, -3, 6, 1, 3}, {5, 1, 6, 2, 2}, {6, 3, 7, 4, 2}, {7, 4, 8, 5, 1}, {7, 5, 8, 6, 3}, {8, 6, 9, 7, 1}, {8, 7, 9, 8, 3}},
        {{-8, 5, -7, 6, 1}, {-8, 6, -7, 7, 3}, {-7, 3, -6, 4, 1}, {-7, 4, -6, 5, 3}, {-7, 5, -3, 7, 4}, {-6, 2, -5, 3, 2}, {-6, 3, -3, 5, 4}, {-5, -4, -4, -3, 2}, {-5, -3, -4, 0, 3}, {-5, 0, -3, 1, 3}, {-5, 1, -3, 2, 1}, {-5, 2, -3, 3, 4}, {-4, -4, 0, -3, 3}, {-4, -3, 0, -1, 4}, {-4, -1, -3, 0, 4}, {-3, -1, -1, 0, 3}, {-3, 2, -2, 7, 1}, {-2, -5, -1, -4, 1}, {-2, 0, -1, 1, 2}, {-2, 1, 0, 2, 1}, {-2, 2, -1, 3, 3}, {-2, 3, 3, 5, 4}, {-2, 5, -1, 7, 4}, {-1, -7, 0, -6, 2}, {-1, -6, 2, -5, 4}, {-1, -5, 2, -4, 2}, {-1, -1, 0, 1, 4}, {-1, 2, 3, 3, 4}, {-1, 5, 0, 7, 3}, {0, -8, 1, -7, 3}, {0, -7, 1, -6, 4}, {0, -4, 1, 1, 1}, {0, 5, 1, 6, 2}, {1, -7, 2, -6, 2}, {1, -4, 5, -3, 3}, {1, -3, 5, -1, 4}, {1, -1, 2, 1, 4}, {1, 1, 3, 2, 1}, {1, 5, 2, 7, 3}, {2, -5, 3, -4, 1}, {2, -1, 4, 0, 3}, {2, 0, 3, 1, 2}, {2, 5, 3, 7, 4}, {3, 2, 4, 7, 1}, {4, -1, 5, 0, 4}, {4, 0, 6, 1, 3}, {4, 1, 6, 2, 1}, {4, 2, 6, 3, 4}, {4, 3, 7, 5, 4}, {4, 5, 8, 7, 4}, {5, -4, 6, -3, 2}, {5, -3, 6, 0, 3}, {6, 2, 7, 3, 2}, {7, 3, 8, 4, 1}, {7, 4, 8, 5, 3}, {8, 5, 9, 6, 1}, {8, 6, 9, 7, 3}},
        {{-8, 5, -7, 6, 1}, {-8, 6, -7, 7, 3}, {-7, 4, -6, 5, 3}, {-7, 5, -3, 7, 4}, {-6, 2, -5, 3, 1}, {-6, 3, -3, 5, 4}, {-5, -3, -1, 0, 4}, {-5, 0, -4, 1, 4}, {-5, 1, -4, 2, 3}, {-5, 2, -3, 3, 2}, {-4, 0, -3, 1, 3}, {-4, 1, -3, 2, 1}, {-3, 0, -2, 1, 1}, {-3, 2, -2, 7, 1}, {-2, -5, -1, -4, 2}, {-2, -4, 2, -3, 1}, {-2, 0, -1, 1, 4}, {-2, 1, 2, 2, 2}, {-2, 2, 2, 3, 3}, {-2, 3, 2, 5, 4}, {-2, 5, -1, 7, 4}, {-1, -7, 1, -6, 2}, {-1, -6, 1, -4, 4}, {-1, -3, 1, 1, 3}, {-1, 5, 1, 6, 3}, {-1, 6, 1, 7, 1}, {1, -5, 2, -4, 2}, {1, -3, 5, 0, 4}, {1, 0, 2, 1, 4}, {1, 5, 2, 7, 4}, {2, 0, 3, 1, 1}, {2, 2, 3, 7, 1}, {3, 0, 4, 1, 3}, {3, 1, 4, 2, 1}, {3, 2, 5, 3, 2}, {3, 3, 6, 5, 4}, {3, 5, 7, 7, 4}, {4, 0, 5, 1, 4}, {4, 1, 5, 2, 3}, {5, 2, 6, 3, 1}, {6, 3, 7, 4, 1}, {6, 4, 7, 5, 3}, {7, 5, 8, 6, 1}, {7, 6, 8, 7, 3}},
        {{-7, 4, -6, 5, 1}, {-7, 5, -6, 6, 3}, {-6, 3, -5, 4, 2}, {-6, 4, -3, 6, 4}, {-5, -3, -4, 1, 1}, {-5, 1, 6, 2, 1}, {-5, 2, -3, 4, 4}, {-4, -4, 5, -3, 1}, {-4, -3, 0, -1, 4}, {-4, -1, -3, 1, 4}, {-3, -1, -1, 0, 3}, {-3, 0, -1, 1, 1}, {-3, 2, -1, 5, 3}, {-3, 5, -2, 6, 2}, {-2, 5, 0, 6, 3}, {-1, -6, 0, -5, 2}, {-1, -5, 2, -4, 4}, {-1, -1, 0, 1, 4}, {-1, 2, 2, 4, 4}, {-1, 4, 0, 5, 4}, {0, -7, 1, -6, 3}, {0, -6, 1, -5, 4}, {0, -3, 1, 1, 2}, {0, 4, 1, 5, 3}, {1, -6, 2, -5, 2}, {1, -3, 5, -1, 4}, {1, -1, 2, 1, 4}, {1, 4, 2, 5, 4}, {1, 5, 3, 6, 3}, {2, -1, 4, 0, 3}, {2, 0, 4, 1, 1}, {2, 2, 4, 5, 3}, {3, 5, 4, 6, 2}, {4, -1, 5, 1, 4}, {4, 2, 6, 4, 4}, {4, 4, 7, 6, 4}, {5, -3, 6, 1, 1}, {6, 3, 7, 4, 2}, {7, 4, 8, 5, 1}, {7, 5, 8, 6, 3}},
    },
}

local CARRIED_RADIUS = 1.0    -- closer than this (horizontally) to a helldiver ...
local CARRIED_LOW = -0.5      -- ... and no lower than this below its feet (prone helldivers and bodies too) ...
local STILL_EPS = 0.05        -- metres from where a vehicle stopped: "not moved at all"
local TRACK_STEP = 2          -- metres: the same vehicle as last frame if it is this close
local CARRIED_HEIGHT = 2.5    -- ... and at most this far above its feet: worn or held, no dot
local PLAYERS_HOLD_S = 2      -- keep the last helldiver positions this long if a read comes back empty
local KEYS_PER_FRAME = 12     -- resource lookups per frame
local HOT_PER_FRAME = 10      -- resources with an item near you, read again every frame (at most this many)
local HOT_MARGIN = 10         -- metres beyond a group's range that still counts as near
local MAX_DOTS = 40           -- the nearest dots only, at most this many in one frame (icons are many triangles)
local STARTUP_GRACE_S = 10    -- wait after start before touching the world
local WORLD_SETTLE_S = 8      -- wait after a world appears before looking anything up in it
local STATUS_EVERY_S = 60     -- a summary line in the log this often
local AVATAR = 'content/fac_helldivers/cha_avatar/avatar_helldiver'

local menu_open               -- defined before tick

local TARGETS = "@TARGETS@"   -- filled in by build.py from targets.lua

-- ----------------------------------------------------------------------- log --
local logfile
do
    -- Written fresh each launch, in Chef Shared Loader's folder (%APPDATA%\Arrowhead\Helldivers2), where a mod may write.
    local dir = CHEF and type(CHEF.log_directory) == 'string' and CHEF.log_directory or nil
    if dir then
        local ok, file = pcall(io.open, dir .. '\\PickupDots.log', 'w')
        if ok then logfile = file end
    end
end

local function write_line(file, message)
    if not file then return end
    pcall(function()
        file:write(os.date('%H:%M:%S'), ' ', tostring(message), '\n')
        file:flush()
    end)
end

local function log(message) write_line(logfile, message) end

-- ------------------------------------------------------------- engine access --
local sr = rawget(_G, 'stingray')

local function check_api()
    if CHEF == nil then return 'no Chef Shared Loader' end
    if type(sr) ~= 'table' or not (sr.Application and sr.Application.main_world) then return 'no engine' end
    local missing = {}
    for _, name in ipairs(CHEF_NEEDS) do
        if type(CHEF[name]) ~= 'function' then missing[#missing + 1] = name end
    end
    if #missing > 0 then return 'Chef Shared Loader without ' .. table.concat(missing, ', ') .. ' (too old?)' end
end

-- Worlds are compared with ==: the engine's World has __eq, and tostring gives '[World]' for every world
-- (0.6.1 log), so 0.1.1-0.6.1 never told two worlds apart.
local function same_world(a, b)
    if a == nil or b == nil then return false end
    if rawequal(a, b) then return true end
    local ok, eq = pcall(function() return a == b end)
    return ok and eq == true
end

local can_get = sr and sr.Application and type(sr.Application.can_get) == 'function' and sr.Application.can_get

-- Script temp memory (Vector3 and friends) is not reset for mods; restore it every frame.
local function temp_begin()
    if sr.Script and type(sr.Script.temp_byte_count) == 'function' then
        local ok, saved = pcall(sr.Script.temp_byte_count)
        if ok then return saved end
    end
end

local function temp_end(saved)
    if saved ~= nil then pcall(sr.Script.set_temp_byte_count, saved) end
end

local function as_list(value)
    if type(value) ~= 'table' then return {} end
    if value[1] ~= nil or next(value) == nil then return value end
    local out = {}
    for _, item in pairs(value) do out[#out + 1] = item end
    return out
end

-- Is this unit resource loaded? A nil answer means "do not look it up".
local function loaded(key, label)
    if not can_get or key == nil then return nil end
    local ok, yes = pcall(can_get, 'unit', key)
    if not ok then return nil end
    return yes == true
end

-- Resources known only by their 64-bit id (28 of the targets: the sample container,
-- mission carryables...) are asked about in whichever id form can_get understands on this game, found
-- by a self-test: the helldiver avatar's id must be "loaded" and a made-up id must not be. If no form
-- passes, those resources are not looked up at all (0.1.1-0.4.0 behaviour).
local AVATAR_HEX = '4d1c334d294dfa97'   -- murmur64 of AVATAR (checked by the tests)
local BOGUS_HEX = '0123456789abcdef'
local id_form            -- 'IdString64' | 'text' | false (none works) | nil (not tested yet)

local function id_key(hex, form)
    if form == 'IdString64' then
        if not (sr.IdString64 and type(sr.IdString64.from_hex) == 'function') then return nil end
        local ok, value = pcall(sr.IdString64.from_hex, hex)
        if ok then return value end
        return nil
    elseif form == 'text' then
        return '#ID[' .. hex .. ']'
    end
end

local function detect_id_form()
    if id_form ~= nil or not can_get then return end
    for _, form in ipairs({'IdString64', 'text'}) do
        local yes = loaded(id_key(AVATAR_HEX, form), 'avatar by id (' .. form .. ')')
        local no = loaded(id_key(BOGUS_HEX, form), 'made-up id (' .. form .. ')')
        log(string.format('id self-test %s: avatar=%s made-up=%s', form, tostring(yes), tostring(no)))
        if yes == true and no == false then
            id_form = form
            log('unnamed targets: id form ' .. form .. ' works - looked up by id')
            return
        end
    end
    id_form = false
    log('unnamed targets: no id form passed the self-test - they stay skipped')
end

-- Through Chef Shared Loader's guard: a call that ever ends the game is skipped from then on (per kind).
local function units_of(world, key, label)
    local value, why = CHEF.call_kind('World.units_by_resource', label, world, key)
    if value == nil then return {}, why end
    return as_list(value)
end

-- Position of a unit returned this very frame, as plain numbers (handles are never kept). The loader refuses units
-- that can't be asked (one built at run time, one from a world that's gone) instead of ending the game.
local function position_of(unit)
    if not CHEF.unit_alive(unit) then return nil end
    local x, y, z = CHEF.unit_position(unit)
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return nil end
    for _, v in ipairs({x, y, z}) do
        if v ~= v or math.abs(v) > 1e7 then return nil end  -- NaN or absurd
    end
    return x, y, z
end

-- --------------------------------------------------------------- the sweep --
local keys = {}          -- { group, label, name or hex }
local found = {}         -- per key index: list of {x, y, z} from the last time it was read
local players = {}       -- list of {x, y, z}: every helldiver avatar (teammates and bodies too)
local me                 -- the one of them nearest the camera: you (or whoever the camera follows)
local cursor = 1
local stats = {sweeps = 0, looked_up = 0, skipped_unloaded = 0, units = 0, key_errors = 0, frames = 0, dots_peak = 0}

local function build_keys()
    local unnamed = 0
    for _, t in ipairs(TARGETS) do
        if t.name then
            keys[#keys + 1] = {group = t.group, name = t.name, label = t.name, icon = t.icon, worn = t.worn, near = t.near, taken = t.taken, height = t.height, node = t.node, mount = t.mount}
        elseif t.hex then
            unnamed = unnamed + 1
            keys[#keys + 1] = {group = t.group, hex = t.hex, label = t.hex, icon = t.icon, worn = t.worn, near = t.near, taken = t.taken, height = t.height, node = t.node, mount = t.mount}
        end
    end
    log(string.format('%d target resources: %d named, %d by id only (looked up if the id self-test passes)',
        #keys, #keys - unnamed, unnamed))
end

-- The key to ask can_get and units_by_resource with, or nil to skip this resource.
local function key_for(k)
    if k.name then return k.name, k.name end
    if not id_form then return nil end
    -- units_by_resource takes an IdString64 (as the reference mods use it); can_get takes the tested form
    return id_key(k.hex, id_form), id_key(k.hex, 'IdString64')
end

-- Which resources had units in the last sweep: "label=count ..." for the status line.
local function found_summary()
    local parts = {}
    for i = 1, #keys do
        local n = found[i] and #found[i] or 0
        if n > 0 then
            local short = string.match(keys[i].label, '([^/]+)$') or keys[i].label
            parts[#parts + 1] = short .. '=' .. n
        end
    end
    return #parts > 0 and table.concat(parts, ' ') or 'none'
end

local players_read_at

-- (0.28-0.31 asked vehicles their animation state; that crashed the game soon after an exosuit was
-- destroyed, its state machine gone: no animation call is made any more.)

-- Since when a vehicle has stayed where it stopped. It is matched to the nearest of last frame's within
-- TRACK_STEP; it is still while it stays within STILL_EPS of its anchor (where it stopped). Read every
-- frame, a slow vehicle moves less than STILL_EPS from one frame to the next, so the last frame's
-- position is not the measure.
local function track(previous, x, y, z, now)
    local best, best_d = nil, TRACK_STEP * TRACK_STEP
    for _, q in ipairs(previous) do
        local dx, dy, dz = q[1] - x, q[2] - y, q[3] - z
        local d = dx * dx + dy * dy + dz * dz
        if d < best_d then best, best_d = q, d end
    end
    local armed = best ~= nil and best.armed or nil   -- it had weapons on it (kept while it is followed)
    local arm = best ~= nil and best.arm or nil       -- how far from its mount its weapon sat (2.3.0)
    local off = best ~= nil and best.off or nil       -- its weapon came off (2.3.0)
    if best ~= nil and best.anchor ~= nil then
        local a = best.anchor
        if math.abs(a[1] - x) < STILL_EPS and math.abs(a[2] - y) < STILL_EPS and math.abs(a[3] - z) < STILL_EPS then
            return {x, y, z, still_since = best.still_since, anchor = a, armed = armed, lost = best.lost, arm = arm, off = off}
        end
    end
    return {x, y, z, still_since = now, anchor = {x, y, z}, armed = armed, lost = best ~= nil and best.lost or nil,
            arm = arm, off = off}
end

local function read_players(world, now)
    local list = {}
    -- The avatar is in every world with a helldiver (the ship too); that is how 0.1.0's reference mod uses it.
    for _, unit in ipairs(units_of(world, AVATAR, 'avatar')) do
        local x, y, z = position_of(unit)
        if x then list[#list + 1] = {x, y, z, unit = unit} end
    end
    -- An empty read for a moment (a ragdoll, a respawn) must not blank every dot: keep the last positions briefly.
    if #list > 0 then
        players, players_read_at = list, now
    elseif players_read_at == nil or now - players_read_at > PLAYERS_HOLD_S then
        players = list
    end
end

-- Read one resource: where its units are now (plain numbers; handles are not kept), whether it was looked up
-- (loaded), and what went wrong looking.
local function read_key(world, i)
    local points = {}
    local ask, lookup = key_for(keys[i])
    if loaded(ask, keys[i].label) and lookup ~= nil then
        local units, problem = units_of(world, lookup, keys[i].label)
        for _, unit in ipairs(units) do
            local x, y, z = position_of(unit)
            if x then points[#points + 1] = {x, y, z, unit = unit} end
        end
        return points, true, problem
    end
    return points, false
end

-- Resources with an item near you in the last frame: read again every frame, so an item thrown by an
-- explosion moves smoothly instead of jumping about four times a second.
local hot = {}           -- list of key indices, made by collect_dots
local vehicles_near = false   -- a vehicle near you in the last frame: READ_TOGETHER read every frame (2.4.0)
local hot_reads = 0      -- for the status line

local function refresh_hot(world, first, last)
    local done = 0
    for _, i in ipairs(hot) do
        if done >= HOT_PER_FRAME then break end
        if i < first or i > last then  -- (the sweep has just read the ones in its own batch)
            found[i] = read_key(world, i)
            done = done + 1
        end
    end
    hot_reads = hot_reads + done
end

local function sweep_step(world)
    local first = cursor
    local last = math.min(cursor + KEYS_PER_FRAME - 1, #keys)
    for i = cursor, last do
        local points, looked, problem = read_key(world, i)
        if looked then
            stats.looked_up = stats.looked_up + 1
            if problem ~= nil then
                stats.key_errors = stats.key_errors + 1
                if stats.key_errors <= 5 then log('lookup failed for ' .. keys[i].label .. ': ' .. tostring(problem)) end
            end
            stats.units = stats.units + #points
        else
            stats.skipped_unloaded = stats.skipped_unloaded + 1
        end
        found[i] = points
    end
    refresh_hot(world, first, last)
    if vehicles_near then   -- vehicles and their weapons, all in this frame (the sweep has its own batch)
        for i = 1, #keys do
            if READ_TOGETHER[keys[i].group] and (i < first or i > last) then
                found[i] = read_key(world, i)
                hot_reads = hot_reads + 1
            end
        end
    end
    cursor = last + 1
    if cursor > #keys then
        cursor = 1
        stats.sweeps = stats.sweeps + 1
    end
end

-- ----------------------------------------------------------------- markers --
-- Distance from you (the helldiver nearest the camera; without a camera, the nearest helldiver), the
-- helldiver it is measured from, and whether the unit is on any helldiver's body (worn or held). A body
-- is still a helldiver here (0.16): its empty sample container stays hidden, and what it dropped lands
-- beside it, within reach of the same rule.
local function measure(x, y, z, worn)
    local carried, mine, others, nearest, nearest_d = false, false, false, nil, nil
    for _, p in ipairs(players) do
        local dx, dy, dz = x - p[1], y - p[2], z - p[3]
        -- worn or held, at any height (prone too)
        local radius = worn or CARRIED_RADIUS   -- a target's own reach (the sample container swings wide)
        if dx * dx + dy * dy < radius * radius and dz > CARRIED_LOW and dz < CARRIED_HEIGHT then
            carried = true
        end
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        -- in (or at) a vehicle: you, or someone else
        if d < VEHICLE_BUSY then
            if p == me then mine = true else others = true end
        end
        if nearest_d == nil or d < nearest_d then nearest, nearest_d = p, d end
    end
    local who = me or nearest
    if who == nil then return nil end
    local dx, dy, dz = x - who[1], y - who[2], z - who[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz), who, carried, mine, others
end

-- Vehicles seen last frame, each tracked like a helldiver (track): since when it has stood still.
local vehicles_seen = {}
local wrecked = setmetatable({}, {__mode = 'k'})   -- per unit (as by_unit): a vehicle whose weapon went (2.4.0)

local function follow_vehicle(p, now, seen_now)
    local t = track(vehicles_seen, p[1], p[2], p[3], now)
    seen_now[#seen_now + 1] = t
    return t
end

-- How far the nearest of these points within r of p is from point m; nil if none is.
local function nearest_from(list, p, r, m)
    local best, from = r * r, nil
    for _, v in ipairs(list) do
        local dx, dy, dz = v[1] - p[1], v[2] - p[2], v[3] - p[3]
        local d = dx * dx + dy * dy + dz * dz
        if d < best then
            local mx, my, mz = v[1] - m[1], v[2] - m[2], v[3] - m[3]
            best, from = d, math.sqrt(mx * mx + my * my + mz * mz)
        end
    end
    return from
end

-- Is any of these points within r of p?
local function near(list, p, r)
    for _, v in ipairs(list) do
        local dx, dy, dz = p[1] - v[1], p[2] - v[2], p[3] - v[3]
        if dx * dx + dy * dy + dz * dz < r * r then return true end
    end
    return false
end

local SHIP_HIDDEN = {mission = true, carry = true, dropoffs = true, controls = true}

-- Last frame's counts per group, for the status line: drawn, hidden as worn/held, out of range.
local last_counts = {}

-- Per-unit tables are keyed by the unit itself, weakly: under Chef Shared Loader every unit's tostring is the
-- same (one key for all would mix units up).
local function by_unit() return setmetatable({}, {__mode = 'k'}) end
local taken = by_unit()       -- per unit: picked up (this world)

-- Has this unit no visible mesh left? Unit.box over the visible meshes (its second argument true) comes back
-- empty (2.3.0: a hellbomb that blew up, alive and in place otherwise; not launch codes picked up: test.11).
-- False when it can't be asked.
local function no_visible_mesh(unit)
    if unit == nil then return false end
    local _, extents = CHEF.call('Unit.box', unit, true)
    if extents == nil then return false end
    local ok, x, y, z = pcall(function() return sr.Vector3.x(extents), sr.Vector3.y(extents), sr.Vector3.z(extents) end)
    return ok and type(x) == 'number' and x == 0 and y == 0 and z == 0
end

-- How many of a unit's meshes are visible (Mesh.visibility), or nil when it can't be asked.
local function visible_meshes(unit)
    if unit == nil then return nil end
    local n = tonumber((CHEF.call('Unit.num_meshes', unit)))
    if n == nil then return nil end
    local count = 0
    for m = 1, n do
        local mesh = CHEF.call('Unit.mesh', unit, m)
        if mesh == nil then return nil end
        local shown = CHEF.call('Mesh.visibility', mesh)
        if shown == nil then return nil end
        if shown == true then count = count + 1 end
    end
    return count
end

-- Launch codes and keycards (targets with 'taken'): picked up, the unit stays where it lay, alive, in place.
-- 2.3.0: but it hides three of its six meshes (test.11 log; nothing else changed, as the codes were walked up
-- to, either). So fewer visible meshes than it was first seen with: taken, by whoever, with whatever key.
-- (2.1.0-2.2.0 guessed from the interact key and teammates standing at it; out in 2.3.0.)
local first_visible = by_unit()   -- per unit: how many meshes it showed when first seen

local function check_taken(p)
    if p.unit == nil then return false end
    if taken[p.unit] then return true end
    local shown = visible_meshes(p.unit)
    if shown ~= nil then
        first_visible[p.unit] = first_visible[p.unit] or shown
        if shown < first_visible[p.unit] then
            taken[p.unit] = true
            log(string.format('taken: the item at %.1f %.1f %.1f is taken for picked up (%d of its %d meshes hidden)',
                p[1], p[2], p[3], first_visible[p.unit] - shown, first_visible[p.unit]))
            return true
        end
    end
    return false
end

-- Where a unit's node is now (Chef Shared Loader), or nil. 2.3.0: a Terminid sample on a stalk, shot off it,
-- tumbles about whole, its root left low and its bulb anywhere (test.3 log): the game's icon goes with its
-- 'interact' node, so ours does too. The node's index is kept per unit.
local node_of = by_unit()

local function node_position(p, name)
    if name == nil or p.unit == nil then return nil end
    local ok, x, y, z = pcall(function()
        local n = node_of[p.unit]
        if n == nil then
            n = CHEF.unit_node(p.unit, name) or false
            node_of[p.unit] = n
        end
        if n == false then return nil end
        return CHEF.unit_position(p.unit, n)
    end)
    if ok and type(x) == 'number' and type(y) == 'number' and type(z) == 'number' then return x, y, z end
end

-- A hellbomb that blew up stays, alive, every node where it was; only its meshes go (no_visible_mesh, 2.3.0-test.6
-- log). Once gone, gone (this world).
local blown = by_unit()

local function blown_up(p)
    if p.unit == nil then return false end
    if blown[p.unit] then return true end
    if no_visible_mesh(p.unit) then
        blown[p.unit] = true
        log(string.format('hellbomb: the one at %.1f %.1f %.1f blew up (no visible mesh left)', p[1], p[2], p[3]))
        return true
    end
    return false
end

local function collect_dots(now)
    local dots = {}
    local counts = {}
    local new_hot = {}
    local any_vehicle = false
    local seen_now = {}
    local wrecks = {}        -- exosuit wrecks: the exosuit beside one is destroyed (its unit may stay)
    local arms = {}          -- vehicles' weapon units: a vehicle that had some and has none now is destroyed
    local dropoffs = {}      -- a mission item or load beside one is delivered (2.1.0)
    local racks = {}         -- artillery ready racks: a shell in one is loaded (2.1.0)
    for i = 1, #keys do
        local group = keys[i].group
        local list = (group == 'wrecks' and wrecks) or (group == 'arms' and arms) or (group == 'dropoffs' and dropoffs) or (group == 'loaders' and racks) or nil
        if list and found[i] then
            for _, p in ipairs(found[i]) do list[#list + 1] = p end
        end
    end
    -- on the ship: no mission markers (diamonds were seen under the hellpods after a mission, 2.0.1)
    local on_ship = not CHEF.in_mission()
    for i = 1, #keys do
        local group = keys[i].group
        local range = SHOW[setting_of(group)] ~= false and (RANGE[setting_of(group)] or 0) or 0
        if on_ship and SHIP_HIDDEN[group] then range = 0 end
        local points = found[i]
        if points and range > 0 then
            local c = counts[group] or {drawn = 0, worn = 0, far = 0}
            counts[group] = c
            local near_any = false
            for _, p in ipairs(points) do
                local d, who, carried, mine, others = measure(p[1], p[2], p[3], keys[i].worn)
                if d ~= nil and d <= range + HOT_MARGIN then near_any = true end
                if d == nil or d > range then
                    c.far = c.far + 1
                elseif group == 'vehicles' then
                    -- destroyed, you in or at it, or someone else in a moving one: no marker
                    local v = follow_vehicle(p, now, seen_now)
                    local parked = now - v.still_since >= VEHICLE_PARKED_S
                    local mx, my, mz = node_position(p, keys[i].mount)
                    local from = nearest_from(arms, p, ARMS_NEAR, mx and {mx, my, mz} or p)
                    local armed_now = from ~= nil
                    if p.unit ~= nil and wrecked[p.unit] then v.off = true end   -- destroyed before (this world)
                    if armed_now and not v.off then v.armed, v.lost = true, nil end
                    if v.armed and not armed_now and not v.off then
                        v.off = true   -- its weapon gone: destroyed, for good
                    end
                    -- (only on a vehicle with a mount: an exosuit's weapons are its arms, which move as it walks and
                    -- aims; 2.4.0-test.5 took one just called in for destroyed)
                    if armed_now and not v.off and keys[i].mount then
                        if v.arm == nil then
                            v.arm = from
                        elseif math.abs(from - v.arm) > ARM_MOVED then
                            v.off = true
                            log(string.format('vehicle: %s - its weapon came off (%.1f m from its mount; it sat %.1f)',
                                string.match(keys[i].label, '([^/]+)$') or keys[i].label, from, v.arm))
                        end
                    end
                    -- kept by its unit: followed from frame to frame only while near, a wreck left and come back to
                    -- showed again (2.4.0-test.5), till it sank into the ground as it went (the markers under the
                    -- ground a player told of). Not one by an exosuit wreck: a new exosuit may land beside the old
                    -- one's wreck and walk off.
                    if v.off and p.unit ~= nil then wrecked[p.unit] = true end
                    local destroyed = v.off or near(wrecks, p, WRECK_NEAR)
                    if destroyed and not v.lost then
                        v.lost = true
                        log('vehicle: ' .. (string.match(keys[i].label, '([^/]+)$') or keys[i].label)
                            .. ' lost its weapons (or is by a wreck) - taken for destroyed')
                    end
                    if destroyed or mine or (others and not parked) then
                        c.worn = c.worn + 1
                    else
                        c.drawn = c.drawn + 1
                        dots[#dots + 1] = {p[1], p[2], p[3] + (keys[i].height or GROUP_HEIGHT.vehicles), d, who, group, keys[i].icon}
                    end
                elseif LOOK.hide_near and (keys[i].near or NEAR_ME[group]) and me ~= nil and who == me
                    and d < (keys[i].near or NEAR_ME[group]) - NEAR_OVERLAP then
                    c.worn = c.worn + 1
                elseif group == 'hellbombs' and blown_up(p) then
                    c.worn = c.worn + 1
                elseif keys[i].taken and check_taken(p) then
                    c.worn = c.worn + 1
                elseif carried and group ~= 'dropoffs' and group ~= 'controls' and group ~= 'hellbombs' then
                    -- (those never worn; a teammate may stand at it)
                    c.worn = c.worn + 1
                elseif (group == 'mission' or group == 'carry') and near(dropoffs, p, DELIVERED_NEAR) then
                    c.worn = c.worn + 1
                elseif group == 'carry' and near(racks, p, LOADED_NEAR) then
                    c.worn = c.worn + 1
                else
                    c.drawn = c.drawn + 1
                    local nx, ny, nz = node_position(p, keys[i].node)
                    if nx then   -- above the node as other markers are above their unit
                        dots[#dots + 1] = {nx, ny, nz + (ABOVE_NODE[group] or DOT_HEIGHT), d, who, group, keys[i].icon}
                    else
                        dots[#dots + 1] = {p[1], p[2], p[3] + (keys[i].height or GROUP_HEIGHT[group] or DOT_HEIGHT), d, who,
                                           group, keys[i].icon}
                    end
                end
            end
            if near_any and group == 'vehicles' then
                any_vehicle = true   -- read with its weapons every frame, not among the hot ones
            elseif near_any then
                new_hot[#new_hot + 1] = i
            end
        end
    end
    -- a wreck's unit gone (despawned): let go of it, should the engine hand the same unit to a new vehicle
    if next(wrecked) ~= nil then
        local there = {}
        for i = 1, #keys do
            if keys[i].group == 'vehicles' and found[i] then
                for _, p in ipairs(found[i]) do
                    if p.unit ~= nil then there[p.unit] = true end
                end
            end
        end
        for u in pairs(wrecked) do
            if not there[u] then wrecked[u] = nil end
        end
    end
    last_counts = counts
    hot = new_hot
    vehicles_near = any_vehicle
    vehicles_seen = seen_now
    if #dots > MAX_DOTS then
        table.sort(dots, function(a, b) return a[4] < b[4] end)
        for i = #dots, MAX_DOTS + 1, -1 do dots[i] = nil end
    end
    return dots
end

-- The game's own field of view, when the camera doesn't give it: vertical_fov in its settings file (55 by default on
-- this PC), read again every GAME_FOV_EVERY_S so a change in the game's options follows. 0.6.0-0.7.1 assumed 50 and
-- the diamonds drifted away from items toward the screen edges.
local game_fov = {value = nil, read_at = nil, path = nil}

local function read_game_fov(now)
    if game_fov.read_at ~= nil and now - game_fov.read_at < GAME_FOV_EVERY_S then return game_fov.value end
    game_fov.read_at = now
    if game_fov.path == nil then
        local ok, appdata = pcall(os.getenv, 'APPDATA')
        if not ok or type(appdata) ~= 'string' then return game_fov.value end
        game_fov.path = appdata .. '\\Arrowhead\\Helldivers2\\user_settings.config'
    end
    local okf, f = pcall(io.open, game_fov.path, 'rb')
    if not okf or f == nil then return game_fov.value end
    local okr, text = pcall(f.read, f, '*a')
    pcall(f.close, f)
    local value = okr and type(text) == 'string' and tonumber(string.match(text, 'vertical_fov%s*=%s*([%d%.]+)'))
    if value and value >= 20 and value <= 120 and value ~= game_fov.value then
        game_fov.value = value
        log('field of view: ' .. value .. ' degrees from the game settings')
    end
    return game_fov.value
end

-- screen ----------------------------------------------------------------------
-- Each marker is projected to the screen with the game's own camera and drawn with Chef Shared Loader's shapes and
-- the mod's textures, on CHEF_LAYER. (Through 2.3.0 the mod made a screen GUI of its own, and drew in the 3D scene
-- without one: with anti-aliasing off, or at a low render scale, those showed in the top-left quarter only. 2.4.0:
-- the loader's only.)
local screen = {}   -- what was logged once

-- The game's own camera, through Chef Shared Loader (2.1.0): where it is, where it looks, and its real field
-- of view (a scope or a speeding vehicle changes it; the settings file's does not). Level: no roll.
local function camera_of()
    local ok, d = pcall(CHEF.camera)
    if not ok or type(d) ~= 'table' or type(d.x) ~= 'number' or type(d.fx) ~= 'number' then return nil end
    local fx, fy, fz = d.fx, d.fy, d.fz
    local level = math.sqrt(fx * fx + fy * fy)
    if level < 1e-6 then return nil end                 -- straight up or down
    local rx, ry = fy / level, -fx / level              -- right: forward x up
    local cam = {translation = {d.x, d.y, d.z}, forward = {fx, fy, fz}, right = {rx, ry, 0},
                 up = {ry * fz, -rx * fz, rx * fy - ry * fx}}   -- right x forward
    if type(d.fov) == 'number' and d.fov > 0 then
        cam.fov = d.fov < 3.2 and math.deg(d.fov) or d.fov   -- the engine gives radians
    end
    if not screen.camera_logged then
        screen.camera_logged = true
        log("camera: the game's own (Chef Shared Loader), field of view " .. tostring(cam.fov))
    end
    return cam
end

local function dot3(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

-- How big a marker is drawn: full size up to FULL_SIZE_M away, LOOK.smallest at the edge of its kind's range.
local FULL_SIZE_M = 10
-- The game scales its HUD with the screen: 1 at 1920 x 1080, by the smaller of width / 1920 and height / 1080
-- (2.4.0: at 1920 x 1200 its icons matched ours; at 2560 x 1440 they were bigger). Ours (sizes, offsets) too.
local UI_W, UI_H = 1920, 1080
local SMALLEST = 0.7          -- the smallest of the game icons' pixel sizes (ICON_PIXELS); smaller: scaled from it
local FADE_LEAST = 0.2
local POINTER = {gap = 3, half = 9, slope = 0.5, line = 2}   -- the wide V under a vehicle's icon, pixels at full size
-- A vehicle off screen (2.3.0): at the screen's edge, this much smaller, with an arrow toward it
local EDGE = {margin = 40, size = 0.7, gap = 4, long = 9, half = 6}   -- pixels at full size (margin: from the edge)
-- 0 up to FULL_SIZE_M away, 1 at the edge of its kind's range
local function far_share(d)
    local range = RANGE[setting_of(d[6])] or 0
    if range <= FULL_SIZE_M then return 0 end
    return math.max(0, math.min(1, (d[4] - FULL_SIZE_M) / (range - FULL_SIZE_M)))
end
local function size_of(d) return 1 - (1 - LOOK.smallest) * far_share(d) end
-- How much a pixel icon's rectangles are scaled at this size: the full one above full size (a big screen, 2.4.0),
-- the smallest one below SMALLEST, else none (its own pixel size is picked)
local function scale_of(size)
    if size > 1 then return size end
    if size < SMALLEST then return size / SMALLEST end
    return 1
end
local function opacity_of(d)
    if not LOOK.fade or d[6] ~= 'supplies' then return LOOK.opacity end   -- mission markers stay easy to find
    return LOOK.opacity * (1 - (1 - FADE_LEAST) * far_share(d))
end

-- Screen position (pixels, origin bottom-left, y up) of a dot, or nil if it is behind or off screen.
local function project(cam, d, width, height, f)
    local p = {d[1] - cam.translation[1], d[2] - cam.translation[2], d[3] - cam.translation[3]}
    local depth = dot3(p, cam.forward)
    if depth < 0.5 then return nil end
    local sx = width / 2 + dot3(p, cam.right) / depth * f
    local sy = height / 2 + dot3(p, cam.up) / depth * f
    if sx < -SCREEN_DIAMOND or sx > width + SCREEN_DIAMOND or sy < -SCREEN_DIAMOND or sy > height + SCREEN_DIAMOND then
        return nil
    end
    -- whole pixels: between them the thin outline smears differently each frame and seems to waver
    return math.floor(sx + 0.5), math.floor(sy + 0.5)
end

-- Where an off-screen dot shows at the screen's edge (pixels, as project) and the way to it (a unit vector):
-- the side it is to, seen from the middle of the screen; straight behind, the bottom.
local function edge(cam, d, width, height, ui)
    local p = {d[1] - cam.translation[1], d[2] - cam.translation[2], d[3] - cam.translation[3]}
    local x, y = dot3(p, cam.right), dot3(p, cam.up)
    local len = math.sqrt(x * x + y * y)
    if len < 1e-6 then x, y, len = 0, -1, 1 end
    x, y = x / len, y / len
    local hw, hh = width / 2 - EDGE.margin * ui, height / 2 - EDGE.margin * ui
    local t = math.min(math.abs(x) > 1e-6 and hw / math.abs(x) or math.huge,
                       math.abs(y) > 1e-6 and hh / math.abs(y) or math.huge)
    return math.floor(width / 2 + x * t + 0.5), math.floor(height / 2 + y * t + 0.5), {x, y}
end

-- This frame's: the screen in Gui.resolution's pixels (width, height; ours) and the loader's (cw, ch; its shapes,
-- texts and textures go there), the colours made (by tint, then alpha 0..255), and the marker's.
local width, height, cw, ch, kx, ky
local inks, tint, ink, tex_ink, opacity

local function ink_of(alpha)
    alpha = math.floor(alpha)
    local by = inks[tint or 'white']
    if by == nil then
        by = {}
        inks[tint or 'white'] = by
    end
    local c = by[alpha]
    if c == nil then
        local rgb = tint or {255, 255, 255}
        c = CHEF.color(rgb[1], rgb[2], rgb[3], alpha)
        by[alpha] = c
    end
    return c
end

-- a filled triangle in the marker's colour, a rectangle in this one; in our pixels (origin bottom-left, y up)
local function tri(x1, y1, x2, y2, x3, y3)
    CHEF.triangle(x1 * kx, y1 * ky, x2 * kx, y2 * ky, x3 * kx, y3 * ky, ink, CHEF_LAYER)
end
local function rect(x0, y0, x1, y1, color)
    CHEF.rect(x0 * kx, y0 * ky, (x1 - x0) * kx, (y1 - y0) * ky, color, CHEF_LAYER)
end

-- under a vehicle's icon, a wide V pointing down at it (like the 0.11-0.25 vehicle marker's lower V)
local THICK = POINTER.line * math.sqrt(1 + POINTER.slope * POINTER.slope)   -- vertical, for the line at right angles
local function band(x1, y1, x2, y2, t)   -- a line t thick upward from (x1, y1)-(x2, y2)
    tri(x1, y1, x2, y2, x2, y2 + t)
    tri(x1, y1, x2, y2 + t, x1, y1 + t)
end
local function pointer(sx, sy, size, half_h)   -- half_h: the icon's half height
    local w, t = POINTER.half * size, THICK * size
    local top = sy - half_h - POINTER.gap * size
    local ay = top - w * POINTER.slope
    band(sx - w, top, sx, ay, t)
    band(sx, ay, sx + w, top, t)
end

-- beside an off-screen vehicle's icon, an arrow toward the vehicle
local function arrow(sx, sy, size, dir, reach)   -- reach: how far the icon reaches from its middle
    local from = reach + EDGE.gap * size
    local bx, by = sx + dir[1] * from, sy + dir[2] * from
    local w = EDGE.half * size
    tri(bx - dir[2] * w, by + dir[1] * w, bx + dir[1] * EDGE.long * size, by + dir[2] * EDGE.long * size,
        bx + dir[2] * w, by - dir[1] * w)
end

-- the distance above a marker, in the game's font (in the loader's pixels), bold: the loader's text has one
-- weight, too thin at this size, so it goes down four times, a pixel apart
local function distance_above(sx, top, d)
    local c = GROUP_RGB[d[6]]
    if not LOOK.distance or c == nil then return end
    pcall(function()
        local px = math.max(1, ch / 1080 * DISTANCE_PX)
        local text = string.format('%dm', math.floor(d[4] + 0.5))
        local color = CHEF.color(c[1], c[2], c[3], math.floor(255 * opacity))
        local x = sx * kx - CHEF.text_width(text, px) / 2
        local y = (top + 3) * ky
        for _, o in ipairs(BOLD) do CHEF.text(x + o[1], y + o[2], text, px, color) end
    end)
end

-- an icon from the mod's textures (ICON_TEX): the smallest baked size at least as big as it is drawn, so it is
-- shrunk a little at most (no mips). Its half width and height, or nil when it can't be drawn.
local function texture_icon(name, sx, sy, size)
    local sizes = ICON_TEX[name]
    if sizes == nil then return nil end
    local long = ICON_SIZE[name] * size                 -- along its longer side, our pixels
    local need = long * kx                               -- the loader's
    local t = sizes[#sizes]
    for _, s in ipairs(sizes) do
        if s[1] >= need then t = s; break end
    end
    local w, h = t[3] * long / t[1], t[4] * long / t[1]
    local okd, drawn = pcall(CHEF.bitmap, t[2], math.floor((sx - w / 2) * kx + 0.5), math.floor((sy - h / 2) * ky + 0.5),
        w * kx, h * ky, tex_ink, CHEF_LAYER)
    if okd and drawn then return w / 2, h / 2 end
    if not screen.texture_note then
        screen.texture_note = true
        log('icons: the texture ' .. tostring(t[2]) .. ' could not be drawn (' .. tostring(drawn) .. ') - diamonds instead')
    end
    return nil
end

-- a diamond: an outline, the band between an outer and an inner one (one quad per side), its lower half filled;
-- its half size
local CORNERS = {{0, 1}, {1, 0}, {0, -1}, {-1, 0}}        -- top, right, bottom, left
local OUTER, INNER = {}, {}                               -- their corners, x then y
local function diamond_at(sx, sy, size)
    local outer = SCREEN_DIAMOND * size
    local inner = math.max(0, outer - math.max(1.5, SCREEN_LINE * size) * math.sqrt(2))  -- the band at right angles
    for k, c in ipairs(CORNERS) do
        OUTER[2 * k - 1], OUTER[2 * k] = sx + c[1] * outer, sy + c[2] * outer
        INNER[2 * k - 1], INNER[2 * k] = sx + c[1] * inner, sy + c[2] * inner
    end
    local o, i = OUTER, INNER
    for k = 1, 4 do
        local a, n = 2 * k - 1, 2 * (k % 4) + 1
        tri(o[a], o[a + 1], o[n], o[n + 1], i[n], i[n + 1])
        tri(o[a], o[a + 1], i[n], i[n + 1], i[a], i[a + 1])
    end
    tri(o[3], o[4], o[5], o[6], o[7], o[8])   -- right, bottom, left: the lower half
    return outer, outer
end

-- a pixel icon (the supply crate's) at this size: its half width and height
local function pixel_icon(sizes, sx, sy, size)
    local step = math.floor((1 - size) / (1 - SMALLEST) * (#sizes - 1) + 0.5) + 1
    local list = sizes[math.max(1, math.min(#sizes, step))]
    local k = scale_of(size)
    for _, r in ipairs(list) do
        rect(sx + r[1] * k, sy + r[2] * k, sx + r[3] * k, sy + r[4] * k, ink_of(255 * r[5] / 4 * opacity))
    end
    if list.half == nil then   -- how far it reaches from its middle, across and up, worked out once
        local hw, hh = 0, 0
        for _, r in ipairs(list) do
            hw = math.max(hw, math.abs(r[1]), math.abs(r[3]))
            hh = math.max(hh, math.abs(r[2]), math.abs(r[4]))
        end
        list.half = {hw, hh}
    end
    return list.half[1] * k, list.half[2] * k
end

local function screen_draw(dots, cam)
    if #dots == 0 or cam == nil then return end
    local oks, w, h = pcall(CHEF.screen)
    if not oks or type(w) ~= 'number' or type(h) ~= 'number' or w <= 0 or h <= 0 then return end
    cw, ch = w, h
    local okr, rw, rh = pcall(sr.Gui.resolution)
    if okr and type(rw) == 'number' and type(rh) == 'number' and rw >= 1 and rh >= 1 then
        width, height = rw, rh
    else
        width, height = cw, ch
    end
    kx, ky = cw / width, ch / height
    inks = {}
    local ok, problem = pcall(function()
        local f = (height / 2) / math.tan(math.rad(cam.fov or read_game_fov(os.clock()) or VERTICAL_FOV) / 2)
        local ui = math.min(width / UI_W, height / UI_H)
        for _, d in ipairs(dots) do
            local sx, sy = project(cam, d, width, height, f)
            local dir   -- a vehicle off screen: the way to it
            if not sx and d[6] == 'vehicles' then sx, sy, dir = edge(cam, d, width, height, ui) end
            if sx then
                local size = size_of(d) * (dir and EDGE.size or 1) * ui
                opacity = opacity_of(d)
                -- a texture tinted (ICON_RGB, else white); the shapes around it, the vehicles' V and arrow, the
                -- group's colour
                tint = d[7] and ICON_RGB[d[7]] or nil
                tex_ink = ink_of(255 * opacity)
                tint = tint or GROUP_RGB[d[6]]
                ink = ink_of(255 * opacity)
                if d[6] == 'samples' or d[6] == 'supplies' then
                    sx, sy = math.floor(sx + ICON_OFFSET[1] * ui + 0.5), math.floor(sy + ICON_OFFSET[2] * ui + 0.5)
                end
                local hw, hh
                if d[7] and ICON_PIXELS[d[7]] then
                    hw, hh = pixel_icon(ICON_PIXELS[d[7]], sx, sy, size)
                elseif d[7] then
                    hw, hh = texture_icon(d[7], sx, sy, size)
                end
                if hw == nil then hw, hh = diamond_at(sx, sy, size) end   -- a diamond, or the icon could not be drawn
                if dir then
                    arrow(sx, sy, size, dir, math.max(hw, hh))
                elseif d[6] == 'vehicles' then
                    pointer(sx, sy, size, hh)
                end
                distance_above(sx, sy + hh, d)
            end
        end
    end)
    if not ok then   -- this frame skipped; the next tries again
        screen.failures = (screen.failures or 0) + 1
        if screen.failures <= 3 then log('drawing: failed (' .. tostring(problem) .. ')') end
    end
end

local function draw(now, cam)
    local dots = collect_dots(now)
    M.dots = dots   -- this frame's markers (the tests read them)
    if menu_open() then return end   -- a menu is open: nothing drawn
    screen_draw(dots, cam)
    if #dots > stats.dots_peak then stats.dots_peak = #dots end
end

-- A menu is open (Esc, the map...) while the mouse cursor shows: the markers are hidden then. Asked of
-- Window.show_cursor, if the engine has it; each change is logged (the first 20) to see that it works.
local cursor_shown = {last = nil, changes = 0, off = false}

menu_open = function()
    if cursor_shown.off then return false end
    local fn = sr.Window and sr.Window.show_cursor
    if type(fn) ~= 'function' then
        cursor_shown.off = true
        log('menus: no Window.show_cursor - markers stay over menus')
        return false
    end
    local ok, value = pcall(fn)
    if not ok then
        cursor_shown.off = true
        log('menus: Window.show_cursor failed (' .. tostring(value) .. ') - markers stay over menus')
        return false
    end
    local open = value == true
    if open ~= cursor_shown.last then
        cursor_shown.last = open
        cursor_shown.changes = cursor_shown.changes + 1
        if cursor_shown.changes <= 20 then log('menus: cursor ' .. (open and 'shown - markers hidden' or 'hidden')
            .. ' (Window.show_cursor gave ' .. tostring(value) .. ')') end
    end
    return open
end

-- You: the helldiver nearest the camera (third or first person alike); nil without a camera. 2.1.0: and the same one from frame to frame, by its unit, unless
-- another is clearly nearer (under ME_SWITCH of your distance): a teammate passing the camera no longer
-- takes your place for a moment; after a respawn the camera is on the new one, far from the body.
local ME_SWITCH = 0.5
local me_unit
local me_changes = 0

local function pick_me(cam)
    if #players == 0 then return nil end
    if #players == 1 then
        me_unit = players[1].unit
        return players[1]
    end
    if cam == nil then return nil end
    local best, who, mine, mine_d
    for _, p in ipairs(players) do
        local dx, dy, dz = p[1] - cam.translation[1], p[2] - cam.translation[2], p[3] - cam.translation[3]
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if best == nil or d < best then best, who = d, p end
        if me_unit ~= nil and p.unit == me_unit then mine, mine_d = p, d end
    end
    if mine ~= nil and (who == mine or best >= ME_SWITCH * mine_d) then return mine end
    local id = who.unit
    if id ~= me_unit then
        me_unit = id
        me_changes = me_changes + 1
        if me_changes <= 50 then
            log(string.format('you: the helldiver at %.1f %.1f %.1f (%d helldivers)', who[1], who[2], who[3], #players))
        end
    end
    return who
end

-- -------------------------------------------------------------------- tick --
local started_at, next_status, last_world, world_seen_at
local world_seq, world_id = 0, nil

local function main_world()
    local ok, world = pcall(sr.Application.main_world)
    if ok then return world end
end

local function tick()
    local now = os.clock()
    if now - started_at < STARTUP_GRACE_S then return end
    local world = main_world()
    if world == nil then
        if last_world ~= nil then last_world, cursor, found, players, me, hot = nil, 1, {}, {}, nil, {} end
        return
    end
    if not same_world(world, last_world) then
        -- a new mission or the ship: forget everything read in the old world
        world_seq = world_seq + 1
        world_id = 'world #' .. world_seq
        last_world, world_seen_at, cursor, found, players, players_read_at, me = world, now, 1, {}, {}, nil, nil
        vehicles_seen = {}
        wrecked = by_unit()
        taken, blown, first_visible, me_unit = by_unit(), by_unit(), by_unit(), nil
        hot = {}
        log('world changed: ' .. world_id)
    end
    if now - world_seen_at < WORLD_SETTLE_S then return end
    stats.frames = stats.frames + 1
    local saved = temp_begin()
    local ok, problem = pcall(function()
        read_players(world, now)   -- every frame: a running helldiver's own items stay hidden
        local cam = camera_of()   -- once a frame, after the game moved it
        me = pick_me(cam)
        if #players > 0 and can_get then
            detect_id_form()
            sweep_step(world)
        end
        draw(now, cam)   -- every frame: the loader draws what it is given each frame only
    end)
    temp_end(saved)
    if not ok then
        M.tick_errors = (M.tick_errors or 0) + 1
        if M.tick_errors <= 5 then log('tick failed: ' .. tostring(problem)) end
    end
    if now >= (next_status or 0) then
        next_status = now + STATUS_EVERY_S
        log(string.format('status: players=%d sweeps=%d looked_up=%d skipped_unloaded=%d units=%d '
            .. 'dots_peak=%d lookup_errors=%d near_resources=%d hot_reads=%d', #players, stats.sweeps, stats.looked_up,
            stats.skipped_unloaded, stats.units, stats.dots_peak, stats.key_errors, #hot, hot_reads))
        hot_reads = 0
        if #players > 0 then
            log('found: ' .. found_summary())
            local parts = {}
            for _, group in ipairs({'samples', 'supplies', 'mission', 'carry', 'dropoffs', 'controls', 'hellbombs', 'vehicles'}) do
                local c = last_counts[group]
                if c then parts[#parts + 1] = string.format('%s drawn=%d worn=%d far=%d', group, c.drawn, c.worn, c.far) end
            end
            log('last frame: ' .. (#parts > 0 and table.concat(parts, ' | ') or 'nothing found'))
        end
        stats.dots_peak = 0
    end
end

-- ---------------------------------------------------------------- settings --
-- Through the loader's Mod Options Menu stand-in: Chef Shared Loader shows them in its F9 menu, in this order,
-- and a change applies at once. 2.2.0: mission items and the loads you carry are one kind, drop-off points and
-- valves another (mission objectives); kinds and how they look sit together.
local ROWS = {   -- {id, kind ('show', 'range' with its most metres, or a LOOK field's)}
    {'show_samples', 'show', 'samples'}, {'range_samples', 'range', 'samples', 150},
    {'show_supplies', 'show', 'supplies'}, {'range_supplies', 'range', 'supplies', 150},
    {'fade', 'toggle', 'fade'},
    {'show_mission', 'show', 'mission'}, {'range_mission', 'range', 'mission', 150},
    {'show_objectives', 'show', 'objectives'}, {'range_objectives', 'range', 'objectives', 150},
    {'show_hellbombs', 'show', 'hellbombs'}, {'range_hellbombs', 'range', 'hellbombs', 300},
    {'show_vehicles', 'show', 'vehicles'}, {'range_vehicles', 'range', 'vehicles', 300},
    {'distance', 'toggle', 'distance'},
    {'hide_near', 'toggle', 'hide_near'},
    {'smallest_size', 'percent', 'smallest', 10, 70},
    {'opacity', 'percent', 'opacity', 10, 100},
}

-- Each row's label and description.
local TEXTS = {
    show_samples = {'Show samples (common, rare, super, Terminid eggs)', 'Samples, sample containers and Terminid eggs.'},
    range_samples = {'Samples distance (m)', 'Marked within this many metres of you. 0 shows none.'},
    show_supplies = {'Show supplies (ammo, grenades, stims, resupply)', 'Ammo boxes, grenade boxes, stims and resupply pod crates.'},
    range_supplies = {'Supplies distance (m)', 'Marked within this many metres of you. 0 shows none.'},
    fade = {'Fade supplies far away', 'Supply markers get fainter the farther away they are.'},
    show_mission = {'Show mission items (SSSDs, launch codes, shells)', 'Mission items you pick up or carry: SSSDs, data drives, launch codes, keycards, artillery shells, warheads.'},
    range_mission = {'Mission items distance (m)', 'Marked within this many metres of you. 0 shows none.'},
    show_objectives = {'Show mission objectives (drop-off points, valves, cranks)', 'Drop-off points, cargo containers, valves and cranks.'},
    range_objectives = {'Mission objectives distance (m)', 'Marked within this many metres of you. 0 shows none.'},
    show_hellbombs = {'Show hellbombs (the ones that blow up when shot)', 'Hellbombs lying about the map, which blow up when shot.'},
    range_hellbombs = {'Hellbombs distance (m)', 'Marked within this many metres of you. 0 shows none.'},
    show_vehicles = {'Show vehicles (exosuits, FRVs, tanks)', 'Exosuits, FRVs and tanks.'},
    range_vehicles = {'Vehicles distance (m)', 'Marked within this many metres of you. 0 shows none.'},
    distance = {'Show distance above vehicles and hellbombs', 'How far away each marked vehicle and hellbomb is.'},
    hide_near = {"Hide markers where the game shows its own icon", "Off: markers stay on up close too (for first-person camera mods)."},
    smallest_size = {'Marker size far away (%)', 'Full size up to 10 m, shrinking to this at the edge of the distance.'},
    opacity = {'Marker opacity (%)', '100 is solid.'},
}

local function register_settings()
    local host = rawget(_G, 'ModOptionsMenu')
    if type(host) ~= 'table' or type(host.register_option) ~= 'function' then
        log('settings: no Mod Options Menu host; the default ranges')
        return
    end
    for _, row in ipairs(ROWS) do
        local id, kind, field = 'pickup_dots.' .. row[1], row[2], row[3]
        local text = TEXTS[row[1]]
        local spec, set
        if kind == 'show' then
            spec = {type = 'toggle', default = true}
            set = function(value) if type(value) == 'boolean' then SHOW[field] = value end end
        elseif kind == 'range' then
            local most = row[4]
            spec = {type = 'slider', default = RANGE[field], min = 0, max = most, step = 5}
            set = function(value)
                value = tonumber(value)
                if value == nil or value ~= value then return end
                RANGE[field] = math.max(0, math.min(most, math.floor(value + 0.5)))
            end
        elseif kind == 'toggle' then
            spec = {type = 'toggle', default = LOOK[field]}
            set = function(value) if type(value) == 'boolean' then LOOK[field] = value end end
        else   -- 'percent': a slider in %, into 0..1
            local least = row[4]
            spec = {type = 'slider', default = row[5], min = least, max = 100, step = 5}
            set = function(value)
                value = tonumber(value)
                if value == nil or value ~= value then return end
                LOOK[field] = math.max(least, math.min(100, value)) / 100
            end
        end
        spec.mod, spec.label, spec.description = 'Extended Pickup Icons Range', text[1], text[2]
        local ok, registered, why = pcall(host.register_option, id, spec)
        if not ok or registered ~= true then   -- left at its default; the others still go in
            log('settings: register failed: ' .. tostring(ok and why or registered))
        end
        if type(host.get) == 'function' then
            local okg, value = pcall(host.get, id)
            if okg then set(value) end
        end
        if type(host.on_change) == 'function' then
            pcall(host.on_change, id, function(value)
                set(value)
                log('settings: ' .. row[1] .. ' ' .. tostring(value))
            end)
        end
    end
end

-- ----------------------------------------------------------------- install --
local function install()
    log('Pickup Dots ' .. VERSION .. ' loading')
    local missing = check_api()
    if missing then
        log('FATAL: ' .. missing)
        if logfile then pcall(function() logfile:close() end) end   -- off for good
        M.status = missing
        return M
    end
    log('Application.can_get: ' .. (can_get and 'present - only loaded resources are looked up'
        or 'MISSING - no target is looked up in this version (diagnostic only)'))
    build_keys()
    register_settings()
    started_at = os.clock()
    local previous = rawget(_G, 'update')
    if type(previous) ~= 'function' then
        log('FATAL: no global update function to hook')
        M.status = 'no update hook'
        return M
    end
    -- after the game's own update: the camera has moved for this frame (before it, the markers trailed
    -- a frame behind when turning, 0.1-0.16)
    local function after(...)
        if not M.disabled then
            local ok, problem = pcall(tick)
            if not ok then
                M.disabled = true
                log('disabled after error: ' .. tostring(problem))
            end
        end
        return ...
    end
    rawset(_G, 'update', function(...)
        return after(previous(...))
    end)
    local shutdown = rawget(_G, 'shutdown')
    if type(shutdown) == 'function' then
        rawset(_G, 'shutdown', function(...)
            log(string.format('shutdown: frames=%d sweeps=%d', stats.frames, stats.sweeps))
            if logfile then pcall(function() logfile:close() end) end
            return shutdown(...)
        end)
    end
    M.status = 'running'
    log('running: ranges samples=' .. RANGE.samples .. ' supplies=' .. RANGE.supplies
        .. ' mission=' .. RANGE.mission .. ' objectives=' .. RANGE.objectives .. ' hellbombs=' .. RANGE.hellbombs
        .. ' vehicles=' .. RANGE.vehicles)
    return M
end

return install()
