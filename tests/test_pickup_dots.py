"""Pickup Dots on PUC Lua 5.1 (lupa) against a fake engine, plus the built archive as Boot Mod Loader reads it."""
import math
import re
import os
import struct
import sys
import tempfile
import unittest

import lupa.lua51 as lua51

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import build  # noqa: E402

AVATAR = "content/fac_helldivers/cha_avatar/avatar_helldiver"
SAMPLE = "content/env_super_earth/samples/research_tech_sample_01"
MARK = "content/objectives/obj_illuminate/il_sarcophagus/il_sarcophagus"   # drawn as a diamond (samples get icons, 0.20)

FAKE_ENGINE = r"""
local fake = { now = 0, lookups = {}, units = {}, loaded = {}, tris = {}, frame_tris = {}, assets = {} }
os.clock = function() return fake.now end
local real_getenv = os.getenv
fake.appdata = 'Z:\\no-such-folder'
os.getenv = function(k)
  if k == 'APPDATA' then return fake.appdata end
  return real_getenv(k)
end

local function vec(x, y, z) return { _x = x, _y = y, _z = z } end
local Vector3 = setmetatable({
  x = function(v) return v._x end, y = function(v) return v._y end, z = function(v) return v._z end,
}, { __call = function(_, x, y, z) return vec(x, y, z) end })

function fake.new_world(name)
  return setmetatable({ name = name }, { __tostring = function(w) return w.name end })
end
fake.world = fake.new_world('world-1')

local function is_vec(v) return type(v) == 'table' and v._x ~= nil end
local function is_color(c) return type(c) == 'table' and c.a ~= nil end

stingray = {
  Application = {
    main_world = function() return fake.world end,
    can_get = function(kind, name)
      if kind ~= 'unit' then return fake.assets[kind .. ':' .. tostring(name)] == true end
      if type(name) == 'table' then return fake.loaded['hex:' .. name.hex] == true end
      return fake.loaded[name] == true
    end,
  },
  World = {
    units_by_resource = function(world, key)
      if type(key) == 'table' then key = 'hex:' .. key.hex end
      if key ~= 'content/fac_helldivers/cha_avatar/avatar_helldiver' and not fake.loaded[key] then
        error('NATIVE CRASH: looked up a resource that is not loaded: ' .. tostring(key))
      end
      fake.lookups[key] = (fake.lookups[key] or 0) + 1
      return fake.units[key] or {}
    end,
  },
  Unit = {
    alive = function(u) return u.alive ~= false end,
    world_position = function(u, node) return vec(u.x, u.y, u.z) end,
  },
  Gui = { resolution = function() return 1920, 1200 end },
  Script = { temp_byte_count = function() return 7 end, set_temp_byte_count = function(n) fake.temp = n end },
  Vector3 = Vector3,
}

-- camera 10 m behind the origin, 0.6 m up, looking along +y: right +x, up +z; a 50 degree field of view
fake.cam = { pos = {0, -10, 0.6}, fwd = {0, 1, 0} }
fake.fov = math.rad(50)

-- Chef Shared Loader's helpers, handed to the mod as the chunk's argument
fake.texts = {}
fake.mission = true
fake.chef = {
  camera = function()
    if fake.chef_cam then return fake.chef_cam end
    if fake.no_camera then return nil end
    local c = fake.cam
    return { x = c.pos[1], y = c.pos[2], z = c.pos[3], fx = c.fwd[1], fy = c.fwd[2], fz = c.fwd[3], fov = fake.fov }
  end,
  in_mission = function() return fake.mission end,
  screen = function() return stingray.Gui.resolution() end,
  color = function(r, g, b, a) return {r = r, g = g, b = b, a = a} end,
  -- the shapes, recorded as triangles of points (x, 0, y) for this frame; a rect as two
  triangle = function(x1, y1, x2, y2, x3, y3, c, layer)
    fake.frame_tris[#fake.frame_tris + 1] = { a = vec(x1, 0, y1), b = vec(x2, 0, y2), c = vec(x3, 0, y3), color = c,
                                              layer = layer }
  end,
  rect = function(x, y, w, h, c, layer)
    fake.rects = (fake.rects or 0) + 1
    for _, t in ipairs({ { x, y, x + w, y, x + w, y + h }, { x, y, x + w, y + h, x, y + h } }) do
      fake.chef.triangle(t[1], t[2], t[3], t[4], t[5], t[6], c, layer)
    end
  end,
  text_width = function(s, px) return #s * px / 2 end,
  text = function(x, y, s, px, c) fake.texts[#fake.texts + 1] = {x = x, y = y, s = s, px = px, c = c} end,
  unit_alive = function(u) return u.alive ~= false end,
  unit_position = function(u, node)
    if node == 7 and u.ix then return u.ix, u.iy, u.iz end   -- its 'interact' node
    if node == 8 and u.mx then return u.mx, u.my, u.mz end   -- its 'gun_mount' node
    if node and node > 1 then return u.x, u.y + node, u.z + (u.blast or 0) * node end
    return u.x, u.y, u.z
  end,
  unit_node = function(u, name)
    if name == 'interact' and u.ix then return 7 end
    if name == 'gun_mount' and u.mx then return 8 end
    return nil
  end,
  call_kind = function(name, kind, ...)
    fake.kinds = fake.kinds or {}
    fake.kinds[name] = kind
    if name ~= 'World.units_by_resource' then return fake.chef.call(name, ...) end
    local ok, value = pcall(stingray.World.units_by_resource, ...)
    if not ok then return nil, value end
    return value
  end,
  call = function(name, ...)
    if name == 'Unit.num_meshes' then local u = ...; return u.meshes end
    if name == 'Unit.mesh' then local u, m = ...; return {unit = u, index = m} end
    if name == 'Mesh.visibility' then
      local mesh = ...
      return mesh.index <= mesh.unit.meshes - (mesh.unit.hidden or 0)
    end
    if name == 'Unit.box' then
      local u, visible = ...
      if visible and u.blown then return 'POSE', stingray.Vector3(0, 0, 0) end
      return 'POSE', stingray.Vector3(0.67, 0.67, 1.05)
    end
    return nil, 'not in the fake'
  end,
  bitmap = function(tex, x, y, w, h, c, layer)
    fake.bitmaps = fake.bitmaps or {}
    if fake.textures_loaded == true then
      fake.bitmaps[#fake.bitmaps + 1] = {tex = tex, x = x, y = y, w = w, h = h, c = c, layer = layer}
    end
    return fake.textures_loaded == true
  end,
}

fake.options = {}
ModOptionsMenu = {
  api = 1,
  register_option = function(id, spec) fake.options[id] = spec; return true end,
  get = function(id) end,
  on_change = function(id, fn) return true end,
}

fake.updates = 0
function update(dt)
  -- the loader draws what it was given this frame only: drawn after the game's update (0.17), so this frame's
  -- table is the one filled from here on
  fake.tris = {}
  fake.frame_tris = fake.tris
  fake.updates = fake.updates + 1
  if fake.on_update then fake.on_update() end   -- what the game itself does this frame (moves the camera...)
end
function shutdown() fake.shut = true end
return fake
"""


def unit(x, y=0.0, z=0.0, alive=True):
    return {"x": x, "y": y, "z": z, "alive": alive}


def xyz(v):
    return (v._x, v._y, v._z)


# The baked icons' table as build.py writes it, with made-up texture ids ('<icon>_<size>') and square sizes (2.4.0):
# baking the real ones takes seconds.
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "tools"))
import bake_icons
TEST_ICONS = "{\n" + "".join("    %s = {%s},\n" % (name, ", ".join("{%d, '%s_%d', %d, %d}" % (s, name, s, s, s)
                                                                 for s in bake_icons.SIZES))
                              for name in sorted(bake_icons.ICONS)) + "}"


class Case(unittest.TestCase):
    def setUp(self):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.fake = self.lua.execute(FAKE_ENGINE)
        self.folder = tempfile.TemporaryDirectory()          # the loader's folder: the log goes there
        self.addCleanup(self.folder.cleanup)
        self.addCleanup(lambda: self.mod is not None and self.lua.globals().shutdown())   # (closes the log)
        self.fake.chef.log_directory = self.folder.name
        build.ICON_TABLE = TEST_ICONS
        self.source = build.built_source()
        self.mod = None

    def set_units(self, key, units, loaded=True):
        self.fake.units[key] = self.lua.table(*[self.lua.table_from(u) for u in units])
        if loaded:
            self.fake.loaded[key] = True

    def load(self):
        self.mod = self.lua.execute(self.source, self.fake.chef)
        self.assertEqual(self.mod.status, "running", self.log_text())
        return self.mod

    def load_with_chef(self):
        return self.load()

    def log_text(self):
        path = os.path.join(self.folder.name, "PickupDots.log")
        if not os.path.exists(path):
            return ""
        with open(path, encoding="utf-8") as f:
            return f.read()

    def frames(self, count, start, step=1 / 60):
        update = self.lua.globals().update
        for i in range(count):
            self.fake.now = start + i * step
            update(0.016)

    def settle(self, count=40):
        """Past the start-up grace (10 s) and the world settle time (8 s)."""
        self.frames(1, start=11.0)          # world first seen at 11 s
        self.frames(count, start=20.0)      # 9 s later

    def points(self):
        """Where this frame's markers are, in the world (x, y, z), on screen or not."""
        dots = self.mod.dots if self.mod is not None else None
        if dots is None:
            return []
        return [(d[1], d[2], d[3]) for d in dots.values()]

    def dots(self):
        return len(self.points())

    def centre(self):
        pts = self.points()
        return tuple(sum(c) / len(pts) for c in zip(*pts))

    TRIS_PER_ICON = 9   # an outline (two triangles per side), then the filled lower half

    def screen_tris(self):
        return list(self.fake.frame_tris.values())

    def screen_points(self):
        tris = self.screen_tris()
        self.assertEqual(len(tris) % self.TRIS_PER_ICON, 0)
        out = []
        for i in range(0, len(tris), self.TRIS_PER_ICON):
            pts = [xyz(v) for t in tris[i:i + 8] for v in (t.a, t.b, t.c)]   # the outline: centred
            out.append((sum(q[0] for q in pts) / len(pts), sum(q[2] for q in pts) / len(pts)))
        return out


class DrawingTests(Case):
    def test_dots_only_within_range_and_only_loaded_resources_are_looked_up(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(10), unit(60)])  # mission items: 50 m
        self.load()
        self.settle()
        log = self.log_text()
        self.assertNotIn("failed", log, log)
        self.assertEqual(self.dots(), 1)
        cx, cy, cz = self.centre()
        self.assertAlmostEqual(cx, 10.0, places=6)  # the unit at 10 m, not the one at 60 m
        self.assertAlmostEqual(cz, 0.6, places=6)   # above the unit
        self.assertEqual(self.fake.temp, 7)
        self.assertGreater(self.fake.updates, 0)
        self.assertEqual(set(self.fake.lookups.keys()), {AVATAR, MARK})
        self.assertIn("can_get: present", log)
        self.assertIn("86 target resources: 80 named, 6 by id only (looked up if the id self-test passes)", log)
        self.frames(1, start=200.0)                   # the next status line, after a full sweep
        log = self.log_text()
        self.assertIn("found: il_sarcophagus=2", log)
        self.assertIn("mission drawn=1 worn=0 far=1", log)

    def test_supply_range_is_shorter(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        target = next(t for t in self.targets() if t["group"] == "supplies" and t.get("name"))
        self.set_units(target["name"], [unit(20), unit(30)])  # supplies: 25 m
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 1)

    def test_worn_or_held_items_get_no_dot(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(-0.3, 0, 1.3), unit(0.5, 0.2, 0.9), unit(6, 0, 0)])  # backpack, hands, ground
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 1)
        self.assertAlmostEqual(self.centre()[0], 6.0, places=6)

    def test_teammates_worn_items_are_hidden_too(self):
        self.set_units(AVATAR, [unit(0), unit(10)], loaded=False)
        self.set_units(MARK, [unit(10.2, 0, 1.3)])
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 0)

    def test_a_brief_empty_helldiver_read_keeps_the_dots(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(5)])
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 1)
        self.set_units(AVATAR, [], loaded=False)
        self.frames(40, start=21.0)            # within 2 s: still drawn
        self.assertEqual(self.dots(), 1)
        self.frames(40, start=24.0)            # longer: cleared
        self.assertEqual(self.dots(), 0)

    def test_dots_go_when_items_leave_range(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(5)])
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 1)
        self.set_units(MARK, [unit(60)])
        self.frames(40, start=21.0)
        self.assertEqual(self.dots(), 0)

    def test_only_the_nearest_dots_are_drawn(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(2 + i * 0.3) for i in range(100)])
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 40)
        self.assertLess(max(p[0] for p in self.points()), 2 + 40 * 0.3 + 1)

    def test_world_change_forgets_old_units_and_draws_in_the_new_world(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(5)])
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 1)
        self.fake.world = self.fake.new_world("world-2")
        self.set_units(MARK, [unit(6)])
        self.frames(1, start=30.0)
        self.frames(40, start=39.0)
        self.assertEqual(self.dots(), 1)
        self.assertAlmostEqual(self.centre()[0], 6.0, places=6)
        self.assertIn("world changed: world #2", self.log_text())

    def test_a_prone_teammates_backpack_is_hidden(self):
        self.set_units(AVATAR, [unit(0), unit(10)], loaded=False)
        self.set_units(MARK, [unit(10.3, 0, 0.3)])  # on the back of a teammate lying down
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 0)

    def test_your_own_items_stay_hidden_however_long_you_lie_still(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(0.3, 0, 0.3), unit(6)])  # your backpack while prone; an item 6 m off
        self.load()
        self.frames(1, start=11.0)
        self.frames(60, start=20.0, step=0.25)  # 15 s without moving
        self.assertEqual(self.dots(), 1)
        self.assertAlmostEqual(self.centre()[0], 6.0, places=6)

    def test_items_near_you_are_drawn_your_own_are_not(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(0.3, 0, 1.0), unit(2.0)])  # on your hip; on the ground 2 m off
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 1)
        self.assertAlmostEqual(self.centre()[0], 2.0, places=6)
        self.frames(1, start=200.0)
        self.assertIn("mission drawn=1 worn=1", self.log_text())

    def test_a_crawling_teammates_items_stay_hidden(self):
        self.set_units(AVATAR, [unit(0), unit(10)], loaded=False)
        self.set_units(MARK, [unit(10.3, 0, 0.2)])
        self.load()
        self.frames(1, start=11.0)
        update = self.lua.globals().update
        for i in range(720):           # crawling at 1 m/s for 12 s
            x = 10 + i / 60
            self.fake.units[AVATAR][2].x = x
            self.fake.units[MARK][1].x = x + 0.3
            self.fake.now = 20.0 + i / 60
            update(0.016)
            self.assertEqual(self.dots(), 0, i)

    def test_a_still_helldivers_items_stay_hidden_and_beside_it_shown(self):
        self.set_units(AVATAR, [unit(0), unit(10)], loaded=False)       # you; a helldiver (or body) that never moves
        self.set_units(MARK, [unit(10.3, 0, 0.2), unit(12)])          # on it; 2 m off
        self.load()
        self.settle(count=900)                                          # 15 s still
        self.assertEqual(self.dots(), 1)
        self.assertAlmostEqual(self.centre()[0], 12.0, places=6)

    def test_the_log_is_written_fresh_each_launch_in_the_loaders_folder(self):
        with open(os.path.join(self.folder.name, "PickupDots.log"), "w") as f:
            f.write("last launch" + chr(10))
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.load()
        self.lua.globals().shutdown()
        text = self.log_text()
        with open(os.path.join(self.folder.name, "PickupDots.previous.log")) as f:
            self.assertEqual(f.read(), "last launch" + chr(10))   # kept, not wiped
        self.assertRegex(text, r"Pickup Dots \S+ loading")
        self.assertIn("shutdown: frames=0", text)
        self.assertNotIn("last launch", text)

    def test_samples_and_supplies_near_you_get_no_marker_but_stims_do(self):
        stim = "content/fac_helldivers/discoverables/health_pack_discoverable_01/health_pack_discoverable_01"
        ammo = "content/fac_helldivers/discoverables/ammo_box_discoverable_01/ammo_box_discoverable_01"
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(SAMPLE, [unit(8.4), unit(8.6)])        # the game's icon from 9 m: ours stays to 8.5 m
        self.set_units(ammo, [unit(-3.4)])                     # supplies: from 4 m, ours to 3.5 m
        self.set_units(stim, [unit(-1.5)])                     # no icon of the game's: always ours
        self.set_units(MARK, [unit(0, 3, 0)])                  # a mission item 3 m off keeps its marker
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 3)
        xs = sorted(round(p[0], 1) for p in self.points())
        self.assertEqual(xs, [-1.5, 0.0, 8.6])

    def test_super_samples_are_left_to_the_game_further_off(self):
        egg = "content/env_bugs/assets/samples/bug_egg_super_sample_01"
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(egg, [unit(15)])                        # the game shows its icon out to 20 m
        self.set_units(SAMPLE, [unit(-15)])                    # a common sample's only to 9 m
        self.load()
        self.settle()
        xs = [round(p[0], 1) for p in self.points()]
        self.assertEqual(xs, [-15.0])

    def test_a_running_teammates_items_stay_hidden(self):
        self.set_units(AVATAR, [unit(0), unit(10)], loaded=False)
        self.set_units(MARK, [unit(10.3, 0, 1.0)])
        self.load()
        self.settle()
        update = self.lua.globals().update
        for i in range(60):            # running at 6 m/s: the item and the helldiver move together
            x = 10 + 0.1 * (i + 1)
            self.fake.units[AVATAR][2].x = x
            self.fake.units[MARK][1].x = x + 0.3
            self.fake.now = 21.0 + i / 60
            update(0.016)
            self.assertEqual(self.dots(), 0, i)

    def test_a_flying_item_near_you_moves_every_frame(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(8)])
        self.load()
        self.settle()
        for k in range(1, 6):            # thrown by an explosion: a new place every frame
            self.set_units(MARK, [unit(8 + k * 0.5, 0, k * 0.3)])
            self.frames(1, start=21.0 + k / 60)
            cx, cy, cz = self.centre()
            self.assertAlmostEqual(cx, 8 + k * 0.5, places=6)
            self.assertAlmostEqual(cz, k * 0.3 + 0.6, places=6)

    def test_far_items_are_not_read_every_frame(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(200)])  # far beyond range and margin
        self.load()
        self.settle()
        before = self.fake.lookups[MARK]
        self.frames(30, start=21.0)          # 30 frames: a sweep of 59 resources takes 5, so about 6 sweeps
        self.assertLessEqual(self.fake.lookups[MARK] - before, 7)   # once a sweep, not 30 times

    def test_dead_units_are_skipped(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(5, alive=False)])
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 0)

    def targets(self):
        with open(build.TARGETS, encoding="utf-8") as f:
            rows = self.lua.execute(f.read())
        return [dict(rows[i].items()) for i in range(1, len(rows) + 1)]


class ScreenTests(Case):
    def test_item_ahead_is_drawn_at_screen_centre(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        (pt,) = self.screen_points()
        self.assertAlmostEqual(pt[0], 960.0, places=4)
        self.assertAlmostEqual(pt[1], 600.0, places=4)   # dot height 0.6 = camera height: centre

    def test_field_of_view_comes_from_the_game_settings(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            folder = os.path.join(tmp, "Arrowhead", "Helldivers2")
            os.makedirs(folder)
            with open(os.path.join(folder, "user_settings.config"), "w", encoding="utf-8") as f:
                f.write("aspect_ratio = -1\nvertical_fov = 55\nupscaling_method = 0\n")
            self.fake.appdata = tmp
            self.fake.fov = None                   # the camera doesn't give it
            self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
            self.set_units(MARK, [unit(1, 0, 0)])  # 1 m right, 10 m ahead
            self.load()
            self.settle()
            (pt,) = self.screen_points()
            f55 = 600 / math.tan(math.radians(55) / 2)
            self.assertEqual(pt[0], math.floor(960 + f55 / 10 + 0.5))
            self.assertIn("field of view: 55 degrees from the game settings", self.log_text())

    def test_without_the_game_settings_50_degrees_is_used(self):
        self.fake.fov = None
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(1, 0, 0)])
        self.load()
        self.settle()
        (pt,) = self.screen_points()
        self.assertEqual(pt[0], math.floor(960 + 600 / math.tan(math.radians(50) / 2) / 10 + 0.5))

    def test_items_behind_the_camera_or_off_screen_are_skipped(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, -15, 0), unit(30, -9, 0), unit(0, 5, 0)])  # behind, far off to the side, ahead
        self.load()
        self.settle()
        self.assertEqual(len(self.screen_points()), 1)

    def test_diamond_is_smaller_with_its_lower_half_filled_on_the_loaders_layer(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        tris = self.screen_tris()
        self.assertEqual(len(tris), 9)
        fill = [xyz(v) for v in (tris[8].a, tris[8].b, tris[8].c)]
        self.assertEqual(sorted((round(x, 3), round(y, 3)) for x, _, y in fill),
                         [(952.08, 600.0), (960.0, 592.08), (967.92, 600.0)])   # left, bottom, right
        self.assertEqual({t.layer for t in tris}, {900})

    def test_on_a_bigger_screen_markers_grow_as_the_games_hud_does(self):
        self.lua.execute("stingray.Gui.resolution = function() return 2560, 1440 end")
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        fill = [xyz(v) for v in (self.screen_tris()[8].a, self.screen_tris()[8].b, self.screen_tris()[8].c)]
        self.assertEqual(sorted((round(x, 2), round(y, 2)) for x, _, y in fill),
                         [(1269.44, 720.0), (1280.0, 709.44), (1290.56, 720.0)])   # 7.92 px x 1440 / 1080

    VEHICLE = "content/fac_helldivers/vehicles/frv/frv"
    MECH = "content/fac_helldivers/vehicles/combat_walker/combat_walker"
    MECH_ARM = "content/fac_helldivers/vehicles/combat_walker_missile/combat_walker_missile"
    CONSOLE = "content/objectives/obj_common/dropoff/dropoff_01"

    def test_vehicles_get_a_chevron_within_100_m_one_per_vehicle(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.VEHICLE, [unit(0, 80, 0), unit(0, 200, 0)])   # 88 m: in; 208 m: out
        self.set_units(self.MECH, [unit(5, 20, 0)])
        self.set_units(self.MECH_ARM, [unit(6, 20, 1)])                    # on the mech
        self.load()
        self.settle()
        self.assertGreater(len(self.screen_tris()), 16)          # icons, not chevrons
        self.assertIn("vehicles drawn=2", self.log_text() + self.status_now())

    def test_an_exosuits_icon_sits_higher_than_a_cars(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.MECH, [unit(-2, 22, 0)])
        self.set_units(self.VEHICLE, [unit(2, 22, 0)])
        self.load()
        self.settle()
        tris = self.screen_tris()
        mech = [v._z for t in tris if t.a._x < 960 for v in (t.a, t.b, t.c)]
        car = [v._z for t in tris if t.a._x > 960 for v in (t.a, t.b, t.c)]
        f = 600 / math.tan(math.radians(50) / 2)
        self.assertGreater((min(mech) + max(mech)) / 2 - (min(car) + max(car)) / 2, 0.8 * (4.8 - 3.2) * f / 30)   # 1.6 m higher

    def test_a_vehicle_that_loses_its_weapons_is_taken_for_destroyed(self):
        gun = "content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg"
        tank = "content/fac_helldivers/vehicles/tank/tank"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.VEHICLE, [unit(-3, 20, 0)])
        self.set_units(gun, [unit(-3, 20, 1.5)])            # on the FRV
        self.set_units(tank, [unit(3, 20, 0)])               # a tank: no weapon units of its own
        self.load()
        self.settle()
        self.assertIn("vehicles drawn=2", self.status_now())
        self.fake.units[gun] = self.lua.table()             # destroyed: the gun is gone
        self.frames(60, start=201.0)
        self.assertIn("frv lost its weapons", self.log_text())
        self.assertTrue(all(t.a._x > 960 for t in self.screen_tris()))   # only the tank is left

    def test_a_vehicle_falling_from_orbit_is_not_taken_for_destroyed(self):
        gun = "content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.VEHICLE, [unit(0, 20, 60)])      # within 100 m of you
        self.set_units(gun, [unit(0, 20, 61.5)])
        self.load()
        self.settle()
        body, arm = self.fake.units[self.VEHICLE][1], self.fake.units[gun][1]
        for k in range(40):                                  # falling at 90 m/s, its gun on it
            body.z = 60 - 1.5 * k
            arm.z = body.z + 1.5
            self.frames(1, start=40.0 + k / 60)
        self.assertNotIn("lost its weapons", self.log_text())
        self.assertIn("vehicles drawn=1", self.status_now())

    def test_a_wreck_still_rolling_loses_its_marker_at_once(self):
        gun = "content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.VEHICLE, [unit(0, 20, 0)])
        self.set_units(gun, [unit(0, 20, 1.5)])
        self.load()
        self.settle()
        body = self.fake.units[self.VEHICLE][1]
        self.fake.units[gun] = self.lua.table()              # destroyed: the gun is gone ...
        for k in range(5):                                   # ... while it rolls on
            body.x = 0.1 * k
            self.frames(1, start=40.0 + k / 60)
        self.assertIn("frv lost its weapons", self.log_text())
        self.assertEqual(self.screen_tris(), [])

    def test_an_exosuit_swinging_its_arm_is_not_taken_for_destroyed(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.MECH, [unit(0, 20, 0)])
        self.set_units(self.MECH_ARM, [unit(1, 20, 3)])                # on its arm
        self.load()
        self.settle()
        self.frames(120, start=40.0)                                   # standing: where the arm is, kept
        arm = self.fake.units[self.MECH_ARM][1]
        arm.x, arm.z = 4, 0.5                                          # swung low: 0.9 m farther from its root
        self.frames(120, start=50.0)
        self.assertNotIn("came off", self.log_text())
        self.assertIn("vehicles drawn=1", self.status_now())

    def test_a_wreck_left_and_come_back_to_stays_unmarked(self):
        gun = "content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.VEHICLE, [unit(0, 20, 0)])
        self.set_units(gun, [unit(0, 20, 1.5)])
        self.load()
        self.settle()
        self.fake.units[gun] = self.lua.table()                        # destroyed
        self.frames(60, start=40.0)
        self.assertIn("frv lost its weapons", self.log_text())
        me = self.fake.units[AVATAR][1]
        me.y = 300                                                     # gone far off: no longer followed ...
        self.frames(60, start=50.0)
        me.y = -8                                                      # ... and back
        self.frames(60, start=60.0)
        self.assertIn("vehicles drawn=0", self.status_now())

    def test_an_exosuit_landing_by_an_old_wreck_is_marked_once_it_walks_off(self):
        wreck = "content/fac_helldivers/vehicles/combat_walker_wreck/combat_walker_wreck"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.MECH, [unit(0, 20, 0)])
        self.set_units(self.MECH_ARM, [unit(1, 20, 3)])
        self.set_units(wreck, [unit(0.5, 20, 0)])                      # the last one's wreck, where the new one lands
        self.load()
        self.settle()
        self.assertIn("vehicles drawn=0 worn=1", self.status_now())
        mech, arm = self.fake.units[self.MECH][1], self.fake.units[self.MECH_ARM][1]
        mech.x, arm.x = 10, 11                                         # walked off
        self.frames(60, start=210.0)
        self.frames(1, start=300.0)                                    # the next status line
        last = [l for l in self.log_text().splitlines() if "last frame:" in l][-1]
        self.assertIn("vehicles drawn=1 worn=0", last)

    def test_a_wrecks_unit_is_let_go_once_it_is_gone(self):
        gun = "content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.VEHICLE, [unit(0, 20, 0)])
        self.set_units(gun, [unit(0, 20, 1.5)])
        self.load()
        self.settle()
        body = self.fake.units[self.VEHICLE][1]
        self.fake.units[gun] = self.lua.table()                        # destroyed
        self.frames(60, start=40.0)
        self.assertIn("frv lost its weapons", self.log_text())
        self.fake.units[self.VEHICLE] = self.lua.table()               # despawned
        self.frames(60, start=50.0)
        self.fake.units[self.VEHICLE] = self.lua.table(body)           # the engine hands the same unit to a new FRV
        self.set_units(gun, [unit(0, 20, 1.5)])
        self.frames(60, start=60.0)
        self.assertIn("vehicles drawn=1", self.status_now())

    def test_vehicles_side_by_side_each_get_a_marker(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.MECH, [unit(-1, 20, 0), unit(1, 20, 0)])   # two exosuits 2 m apart
        self.load()
        self.settle()
        self.assertIn("vehicles drawn=2", self.status_now())

    def test_the_sample_container_counts_as_worn_further_off_than_other_items(self):
        self.lua.execute("stingray.IdString64 = { from_hex = function(hex) return { hex = hex } end }")
        self.fake.loaded["hex:4d1c334d294dfa97"] = True
        self.set_units(AVATAR, [unit(0, -8, 0), unit(10, 10, 0)], loaded=False)   # you; a teammate boarding
        self.set_units("hex:a9936cbe561e8180", [unit(12, 10, 1)])                  # its container, 2 m off
        self.set_units(SAMPLE, [unit(8, 10, 0)])                                  # a sample 2 m off: shown
        self.load()
        self.settle()
        self.assertIn("samples drawn=1 worn=1", self.status_now())

    def test_an_exosuit_beside_its_wreck_gets_no_marker(self):
        wreck = "content/fac_helldivers/vehicles/combat_walker_wreck/combat_walker_wreck"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.MECH, [unit(-3, 20, 0), unit(3, 20, 0)])
        self.set_units(wreck, [unit(3.5, 20, 0)])          # the right one is destroyed
        self.load()
        self.settle()
        self.assertTrue(all(t.a._x < 960 for t in self.screen_tris()))
        self.assertIn("vehicles drawn=1 worn=1", self.status_now())

    def test_a_vehicle_you_are_in_never_gets_a_chevron(self):
        self.set_units(AVATAR, [unit(30, 1, 1.5)], loaded=False)   # you, in it
        self.set_units(self.VEHICLE, [unit(30, 0, 0)])
        self.load()
        self.settle(count=600)                                        # parked for 10 s
        self.assertEqual(self.screen_tris(), [])
        self.assertIn("vehicles drawn=0 worn=1", self.status_now())

    def test_a_teammates_vehicle_is_hidden_while_it_moves_and_shown_once_parked(self):
        self.set_units(AVATAR, [unit(0, -8, 0), unit(2, 31, 1.5)], loaded=False)   # you, a teammate driving
        self.set_units(self.VEHICLE, [unit(2, 30, 0)])   # ahead of the camera
        self.load()
        update = self.lua.globals().update
        self.frames(1, start=11.0)
        for i in range(120):                                          # driving for 2 s
            self.fake.units[self.VEHICLE][1].y = 30 + i * 0.1
            self.fake.units[AVATAR][2].y = 31 + i * 0.1
            self.fake.now = 20.0 + i / 60
            update(0.016)
            self.assertEqual(self.screen_tris(), [], i)
        self.frames(100, start=23.0)                                  # stopped, the teammate still in it: under 3 s
        self.assertEqual(self.screen_tris(), [])
        self.frames(200, start=26.0)                                  # parked 3 s and more
        self.assertGreater(len(self.screen_tris()), 0)

    def test_a_slowly_driven_vehicle_is_not_taken_for_parked(self):
        self.set_units(AVATAR, [unit(0, -8, 0), unit(2, 31, 1.5)], loaded=False)
        self.set_units(self.VEHICLE, [unit(2, 30, 0)])
        self.load()
        self.frames(1, start=11.0)
        update = self.lua.globals().update
        for i in range(480):           # 1 m/s for 8 s
            self.fake.units[self.VEHICLE][1].y = 30 + i / 60
            self.fake.units[AVATAR][2].y = 31 + i / 60
            self.fake.now = 20.0 + i / 60
            update(0.016)
            self.assertEqual(self.screen_tris(), [], i)

    def test_a_console_shows_while_a_teammate_stands_at_it(self):
        self.set_units(AVATAR, [unit(0, -8, 0), unit(0.5, 20, 0)], loaded=False)
        self.set_units(self.CONSOLE, [unit(0, 20, 0), unit(0, 70, 0)])    # 28 m: in; 78 m: out
        self.load()
        self.settle()
        self.assertEqual(len(self.screen_points()), 1)
        self.assertIn("dropoffs drawn=1 worn=0 far=1", self.status_now())

    def status_now(self):
        self.frames(1, start=200.0)
        return self.log_text()

    def test_worlds_that_all_print_the_same_are_still_told_apart(self):
        # in the game every world prints as '[World]' (0.6.1 log); the engine compares them with ==
        self.lua.execute("""local fake = ...
            fake.world = setmetatable({}, { __tostring = function() return '[World]' end })""", self.fake)
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.assertEqual(len(self.screen_points()), 1)
        self.lua.execute("local fake = ...; fake.world = setmetatable({}, getmetatable(fake.world))", self.fake)
        self.frames(1, start=30.0)
        self.assertIn("world changed: world #2", self.log_text())

    def test_range_is_measured_from_the_helldiver_nearest_the_camera(self):
        # you at (0,-8), a teammate 40 m away; camera behind you at (0,-10)
        self.set_units(AVATAR, [unit(0, -8, 0), unit(40, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0), unit(40, 0, 0)])  # beside you / beside the teammate
        self.load()
        self.settle()
        pts = self.screen_points()
        self.assertEqual(len(pts), 1)
        self.assertAlmostEqual(pts[0][0], 960.0, places=4)  # the one beside you

    def test_a_teammates_worn_backpack_is_still_hidden(self):
        self.set_units(AVATAR, [unit(0, -8, 0), unit(3, 0, 0)], loaded=False)
        self.set_units(MARK, [unit(3.2, 0, 1.3)])  # on the teammate's back, in your range
        self.load()
        self.settle()
        self.assertEqual(self.screen_points(), [])

    def test_markers_use_the_camera_the_game_moved_this_frame(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.lua.execute("""local fake = ...
            fake.on_update = function() fake.cam.pos = {-1, -10, 0.6} end   -- the game moves the camera 1 m left""",
                         self.fake)
        self.frames(1, start=30.0)
        (pt,) = self.screen_points()
        f = 600 / math.tan(math.radians(50) / 2)
        self.assertEqual(pt[0], math.floor(960 + f / 10 + 0.5))   # this frame's camera, not the last one's

    def test_samples_and_supplies_get_icons_lower_than_diamonds(self):
        stim = "content/fac_helldivers/discoverables/health_pack_discoverable_01/health_pack_discoverable_01"
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.fake.textures_loaded = True
        self.set_units(AVATAR, [unit(0, -11, 0)], loaded=False)   # beyond the game's own sample icon
        self.set_units(SAMPLE, [unit(-1, 0, 0)])          # a common sample
        self.set_units(stim, [unit(1, -3, 0)])            # 8 m off: full size
        self.load_with_chef()
        self.settle()
        shown = {b.tex.split("_")[0]: b for b in self.bitmaps_now()}
        self.assertEqual(set(shown), {"common", "stim"})
        self.assertTrue(all((b.c.r, b.c.g, b.c.b) == (255, 255, 255) for b in shown.values()))   # all white
        f = 600 / math.tan(math.radians(50) / 2)
        top = max(b.y + b.h for b in shown.values())
        self.assertLess(top, 600 - 0.3 * f / 10 + 10)     # 0.3 m above the items: below a diamond's 0.6 m

    def test_the_supply_crate_is_its_pixel_icon_pixel_for_pixel(self):
        crate = "content/fac_helldivers/hellpod/ammo_rack/ammo_box"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(crate, [unit(0, 0, 0)])
        self.load()
        self.settle()
        tris = self.screen_tris()
        self.assertGreater(len(tris), 0)
        coords = {v._x for t in tris for v in (t.a, t.b, t.c)} | {v._z for t in tris for v in (t.a, t.b, t.c)}
        self.assertTrue(all(c == int(c) for c in coords))              # on whole pixels
        self.assertEqual({t.color.a for t in tris} - {63, 127, 191, 255}, set())   # see-through edges, in quarters
        self.assertEqual(max(v._x for t in tris for v in (t.a, t.b, t.c))
                         - min(v._x for t in tris for v in (t.a, t.b, t.c)), 21)   # 21 px across, as made

    def test_artillery_shells_get_diamonds_and_carried_packages_the_games_icon(self):
        shell = "content/objectives/obj_common/seaf_artillery/seaf_shell_regular"
        case = "content/objectives/obj_common/briefcase/briefcase"
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.fake.textures_loaded = True
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(shell, [unit(-1, 0, 0), unit(0, 50, 0)])   # 8 m: in; 58 m: past mission items' 50 m
        self.set_units(case, [unit(1, 0, 0)])
        self.load_with_chef()
        self.settle()
        self.assertEqual(len(self.screen_tris()), 9)          # the shell: a diamond
        (b,) = self.bitmaps_now()                             # the briefcase: the game's package icon, sky blue
        self.assertTrue(b.tex.startswith("package_"))
        self.assertEqual((b.c.r, b.c.g, b.c.b), (110, 205, 255))

    def test_ranges_are_settings_and_zero_shows_none(self):
        self.lua.execute("""
            local get = ModOptionsMenu.get
            ModOptionsMenu.get = function(id)
              if id == 'pickup_dots.range_mission' then return 15 end
              if id == 'pickup_dots.range_objectives' then return 0 end
              return get(id)
            end
        """)
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(-1, 0, 0), unit(0, 20, 0)])        # 8 m: in; 28 m: past the 15 m set
        self.set_units(self.CONSOLE, [unit(6, 0, 0)])                   # a drop-off, an objective: none shown at 0
        self.load()
        self.settle()
        self.assertEqual(len(self.screen_points()), 1)
        spec = self.fake.options["pickup_dots.range_objectives"]
        self.assertEqual((spec.min, spec.max, spec.default), (0, 150, 50))
        self.assertEqual(self.fake.options["pickup_dots.range_vehicles"].default, 100)

    def test_markers_shrink_with_distance_to_70_percent_at_the_edge_of_range(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])                 # 8 m: full size
        self.load()
        self.settle()
        tris = self.screen_tris()
        near = max(v._x for t in tris for v in (t.a, t.b, t.c)) - min(v._x for t in tris for v in (t.a, t.b, t.c))
        self.fake.units[MARK][1].y = 42                       # 50 m, the edge of the 50 m mission range
        self.frames(80, start=30.0)
        tris = self.screen_tris()
        far = max(v._x for t in tris for v in (t.a, t.b, t.c)) - min(v._x for t in tris for v in (t.a, t.b, t.c))
        self.assertAlmostEqual(near, 15.84, places=3)
        self.assertAlmostEqual(far, 15.84 * 0.7, places=3)     # 70 %

    def test_an_item_put_into_a_drop_off_gets_no_marker(self):
        sssd = "content/objectives/obj_common/carry_data/carry_data"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.CONSOLE, [unit(-4, 0, 0)])
        self.set_units(sssd, [unit(-4, 0, 1.0), unit(4, 0, 0)])        # one put in, one on the ground
        self.load()
        self.settle()
        self.assertIn("mission drawn=1 worn=1", self.status_now())
        self.assertIn("dropoffs drawn=1 worn=0", self.status_now())   # the drop-off keeps its marker: SSSDs are taken
                                                                         # out of drop-offs in some missions

    def test_a_drop_off_keeps_its_marker_while_an_sssd_is_only_carried_past(self):
        sssd = "content/objectives/obj_common/carry_data/carry_data"
        self.set_units(AVATAR, [unit(0, -8, 0), unit(-4, 1, 0)], loaded=False)   # you; a teammate at it
        self.set_units(self.CONSOLE, [unit(-4, 0, 0)])
        self.set_units(sssd, [unit(-4, 1, 1.0)])                         # in the teammate's hands
        self.load()
        self.settle()
        self.assertIn("dropoffs drawn=1 worn=0", self.status_now())

    def test_a_loaded_artillery_shell_gets_no_marker(self):
        shell = "content/objectives/obj_common/seaf_artillery/seaf_shell_regular"
        rack = "content/objectives/obj_common/fire_artillery/ready_rack"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(rack, [unit(-4, 0, 0)])
        self.set_units(shell, [unit(-4, 0, 0.5), unit(-2.5, 0, 0)])     # one in the rack; one left beside it
        self.load()
        self.settle()
        self.assertIn("carry drawn=1 worn=1", self.status_now())

    def test_launch_codes_a_helldiver_stands_at_keep_their_marker(self):
        codes = "content/objectives/obj_common/generic_intel/generic_intel"
        self.set_units(AVATAR, [unit(0, -8, 0), unit(10, 0, 0)], loaded=False)   # you; a teammate at them
        self.set_units(codes, [unit(10, 1.2, 0), unit(-6, 0, 0)])
        self.load()
        self.settle()                                                  # 9 s on: no guess from who stands where
        self.assertIn("mission drawn=2 worn=0", self.status_now())
        self.assertNotIn("taken: ", self.log_text())

    def test_markers_are_the_loaders_shapes_on_its_layer(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])                         # a diamond, straight ahead
        self.set_units("content/fac_helldivers/hellpod/ammo_rack/ammo_box", [unit(4, 0, 0)])   # a pixel icon
        self.load()
        self.settle()
        self.fake.rects = 0
        self.frames(1, start=40.0)
        tris = self.screen_tris()
        self.assertGreater(self.fake.rects, 0)                        # the supply crate's pixels
        self.assertEqual({t.layer for t in tris}, {900})
        centre = lambda t: ((t.a._x + t.b._x + t.c._x) / 3, (t.a._z + t.b._z + t.c._z) / 3)
        diamond = [t for t in tris if abs(centre(t)[0] - 960) < 12 and abs(centre(t)[1] - 600) < 12]
        self.assertEqual(len(diamond), 9)                             # outline and lower half, at the centre

    def test_with_chef_the_cameras_real_field_of_view_is_used(self):
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(25)})    # zoomed in: a scope
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(1, 0, 0)])                         # 1 m right, 10 m ahead
        self.load_with_chef()
        self.settle()
        (pt,) = self.screen_points()
        f25 = 600 / math.tan(math.radians(25) / 2)
        self.assertAlmostEqual(pt[0], 960 + f25 / 10, delta=1)
        self.assertIn("camera: the game's own (Chef Shared Loader)", self.log_text())

    def test_with_chef_a_sample_shot_off_its_stalk_is_marked_where_it_tumbled(self):
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        stalk = unit(0, 10, 0)
        stalk.update(ix=2, iy=10, iz=-0.3)                            # lying 2 m to the right of its root
        self.set_units("content/env_bugs/assets/samples/bug_sample_01", [stalk])
        self.load_with_chef()
        self.settle()
        pts = [xyz(p) for t in self.screen_tris() for p in (t.a, t.b, t.c)]
        f = 600 / math.tan(math.radians(25))
        cx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2
        cy = (min(p[2] for p in pts) + max(p[2] for p in pts)) / 2
        self.assertAlmostEqual(cx, 960 + f * 2 / 20 - 28, delta=3)    # at the node (and the game icon's offset)
        self.assertAlmostEqual(cy, 600 + f * (-0.3 + 0.3 - 0.6) / 20 - 35, delta=3)   # 0.3 above it, not 1.2

    def test_with_chef_the_distance_shows_above_vehicles_only(self):
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(-2, 0, 0)])                        # an item: no distance
        self.set_units(self.VEHICLE, [unit(0, 20, 0)])
        self.load_with_chef()
        self.settle()
        texts = list(self.fake.texts.values())
        self.assertEqual({t.s for t in texts}, {"28m"})
        self.assertEqual(len({(round(t.x, 3), round(t.y, 3)) for t in texts}), 4)   # bold: four, a pixel apart
        self.assertGreater(texts[-1].y, 600)                          # above the vehicle's icon
        self.assertAlmostEqual(texts[-1].px, 1200 / 1080 * 1.6, places=6)   # a fifth of test.5's size

    def test_with_chef_a_frv_whose_gun_comes_off_is_taken_for_destroyed(self):
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        frv = "content/fac_helldivers/vehicles/frv/frv"
        rack = "content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        body = unit(0, 20, 0)
        body.update(mx=0, my=20, mz=1.5)                    # its gun mount, on top
        self.set_units(frv, [body])
        self.set_units(rack, [unit(0, 20, 1.6)])             # on its mount
        self.load_with_chef()
        self.settle()
        self.frames(120, start=40.0)                         # it stands still: how far the gun sits is kept
        self.assertIn("vehicles drawn=1", self.status_now())
        lying = self.fake.units[rack][1]                    # destroyed: the gun lies beside it, still within 5 m
        lying.x, lying.z = 1.5, 0.2
        self.frames(120, start=50.0)
        self.assertIn("frv - its weapon came off", self.log_text())
        self.assertEqual(self.screen_tris(), [])

    def test_with_chef_a_hellbomb_that_blew_up_loses_its_marker(self):
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(ScreenTests.HELLBOMB, [unit(0, 30, 0)])
        self.load_with_chef()
        self.settle()
        self.assertTrue(self.screen_tris())
        self.fake.units[ScreenTests.HELLBOMB][1].blown = True          # its meshes gone: blown up, still alive
        self.frames(5, start=40.0)
        self.assertEqual(self.screen_tris(), [])
        self.assertIn("hellbomb: the one at 0.0 30.0 0.0 blew up", self.log_text())

    def test_with_chef_on_the_ship_mission_markers_are_off(self):
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.set_units(SAMPLE, [unit(5, 0, 0)])
        self.load_with_chef()
        self.fake.mission = False
        self.settle()
        status = self.status_now()
        self.assertNotIn("mission drawn=1", status)
        self.assertIn("samples drawn=1", status)

    def bitmaps_now(self, start=40.0):
        """The textures drawn in one frame from now."""
        self.fake.bitmaps = self.lua.table()
        self.frames(1, start=start)
        return list(self.fake.bitmaps.values())

    def test_with_chef_icons_are_the_mods_own_textures_of_the_games_icons(self):
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.fake.textures_loaded = True
        ammo = "content/fac_helldivers/discoverables/ammo_box_discoverable_01/ammo_box_discoverable_01"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(ammo, [unit(0, 0, 0)])
        self.load_with_chef()
        self.settle()
        (b,) = self.bitmaps_now()
        self.assertEqual(b.tex, "ammo_20")                             # the smallest baked size of at least 19 px
        self.assertAlmostEqual(b.h, 19, delta=0.01)                    # drawn 19 px, as the 2.3.0 pixel icon
        self.assertEqual(self.screen_tris(), [])                       # nothing else
        self.fake.textures_loaded = False                              # can't be drawn: a diamond instead
        self.frames(5, start=30.0)
        self.assertEqual(len(self.screen_tris()), 9)
        self.assertIn("icons: the texture ammo_20 could not be drawn", self.log_text())

    def test_with_chef_launch_codes_you_pick_up_leave_other_codes_marked(self):
        codes = "content/objectives/obj_common/generic_intel/generic_intel"
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        picked, other = unit(0, -6.5, 0), unit(5, 5, 0)
        picked.update(meshes=6)
        other.update(meshes=6)
        self.set_units(codes, [picked, other])                       # one at you, one farther on
        self.load_with_chef()
        self.settle()
        self.fake.e_key = True                                        # the interact key alone takes nothing
        self.frames(3, start=30.0)
        self.fake.e_key = False
        self.assertNotIn("taken: ", self.log_text())
        self.fake.units[codes][1].hidden = 3                           # picked up
        self.frames(80, start=40.0)
        self.assertEqual(self.log_text().count("taken: "), 1)
        self.assertEqual(len(self.screen_points()), 1)                 # the other codes keep their marker

    def test_with_chef_launch_codes_that_hide_some_meshes_are_taken_by_anyone(self):
        codes = "content/objectives/obj_common/generic_intel/generic_intel"
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        lying = unit(5, 5, 0)
        lying.update(meshes=6)
        self.set_units(codes, [lying])                                # far from you: no key, no teammate
        self.load_with_chef()
        self.settle()
        self.assertEqual(len(self.screen_points()), 1)
        self.fake.units[codes][1].hidden = 3                           # picked up somewhere: 3 of its 6 meshes hide
        self.frames(5, start=40.0)
        self.assertEqual(self.screen_tris(), [])
        self.assertIn("is taken for picked up (3 of its 6 meshes hidden)", self.log_text())

    def test_with_chef_launch_codes_a_teammate_only_passes_keep_their_marker(self):
        codes = "content/objectives/obj_common/generic_intel/generic_intel"
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.set_units(AVATAR, [unit(0, -8, 0), unit(5, 5, 0)], loaded=False)   # you, and a teammate at the codes
        lying = unit(5.5, 5, 0)
        lying.update(meshes=6)
        self.set_units(codes, [lying])
        self.load_with_chef()
        self.settle()
        self.frames(120, start=40.0)                                   # 2 s at it, all 6 meshes still shown
        self.assertNotIn("taken: ", self.log_text())

    def test_with_chef_a_crank_that_turned_keeps_its_marker(self):
        crank = "content/objectives/obj_common/colony_relay/colony_relay_01/objective_colony_relay_antenna_crank_01"
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(crank, [unit(3, 0, 0)])
        self.load_with_chef()
        self.settle()
        self.fake.units[crank][1].turn = 1.0
        self.frames(300, start=30.0)
        self.assertNotIn("control: ", self.log_text())
        self.assertEqual(len(self.screen_points()), 1)

    def test_you_stay_the_same_helldiver_while_a_teammate_passes_the_camera(self):
        self.set_units(AVATAR, [unit(0, -8, 0), unit(0, -12.5, 0)], loaded=False)   # the camera: 0 -10 0.6
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.fake.units[AVATAR][2].y = -11.2                           # nearer the camera than you, but not much
        self.frames(20, start=30.0)
        you = [l for l in self.log_text().splitlines() if "you: " in l]
        self.assertEqual(len(you), 1, you)
        self.assertIn("you: the helldiver at 0.0 -8.0 0.0", you[0])
        self.fake.units[AVATAR][2].y = -10.2                           # right at the camera: the camera's on them
        self.frames(20, start=40.0)
        you = [l for l in self.log_text().splitlines() if "you: " in l]
        self.assertEqual(len(you), 2, you)

    def test_settings_come_in_order_kinds_with_what_goes_with_them(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.lua.execute("""local fake = ...
            fake.order = {}
            local register = ModOptionsMenu.register_option
            ModOptionsMenu.register_option = function(id, spec) fake.order[#fake.order + 1] = id; return register(id, spec) end
        """, self.fake)
        self.load()
        order = [i[len("pickup_dots."):] for i in self.fake.order.values()]
        self.assertEqual(order, ["show_samples", "range_samples", "fade_samples", "show_supplies", "range_supplies", "fade",
                                 "show_mission", "range_mission", "show_objectives", "range_objectives",
                                 "show_hellbombs", "range_hellbombs", "show_vehicles", "range_vehicles",
                                 "show_deaths", "range_deaths", "distance", "hide_near", "smallest_size", "opacity"])

    def test_vehicles_get_their_kinds_framed_icon_sky_blue(self):
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.fake.textures_loaded = True
        tank = "content/fac_helldivers/vehicles/tank_storm/tank_storm"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.VEHICLE, [unit(-4, 20, 0)])
        self.set_units(tank, [unit(4, 20, 0)])
        self.load_with_chef()
        self.settle()
        shown = self.bitmaps_now()
        self.assertEqual(sorted(b.tex.rsplit("_", 1)[0] for b in shown), ["car", "tank"])   # an FRV, a Maelstrom
        self.assertEqual({(b.c.r, b.c.g, b.c.b) for b in shown}, {(110, 205, 255)})
        colours = {(t.color.r, t.color.g, t.color.b) for t in self.screen_tris()}
        self.assertEqual(colours, {(110, 205, 255)})                   # the Vs under them

    HELLBOMB = "content/fac_helldivers/hellpod/hellbomb_defunct/hellbomb_defunct"
    PACKAGE = "content/objectives/obj_common/carry_data/carry_data"

    def test_hellbombs_are_marked_out_to_100_m_their_distance_in_red(self):
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.fake.textures_loaded = True
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.HELLBOMB, [unit(0, 80, 0), unit(0, 120, 0)])   # 88 m: in; 128 m: past 100 m
        self.load_with_chef()
        self.settle()
        (b,) = self.bitmaps_now()
        self.assertTrue(b.tex.startswith("hellbomb_"))
        self.assertEqual((b.c.r, b.c.g, b.c.b), (255, 90, 70))             # framed, red
        texts = list(self.fake.texts.values())
        self.assertEqual({t.s for t in texts}, {"88m"})                    # its distance above it, in red
        self.assertEqual({(t.c.r, t.c.g, t.c.b) for t in texts}, {(255, 90, 70)})
        self.assertIn("hellbombs drawn=1 worn=0 far=1", self.status_now())

    def test_a_sample_on_a_stalk_is_marked_higher_where_the_game_shows_its_icon(self):
        def top(name):
            self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
            self.set_units(name, [unit(0, 10, 0)])   # 18 m from you: past where the game shows its own icon
            self.load()
            self.settle()
            ys = [xyz(p)[2] for t in self.screen_tris() for p in (t.a, t.b, t.c)]
            self.set_units(name, [])
            return max(ys)
        low = top(SAMPLE)
        self.tearDown(); self.setUp()
        high = top("content/env_bugs/assets/samples/bug_sample_01")
        f = 600 / math.tan(math.radians(50) / 2)
        self.assertAlmostEqual(high - low, f * 0.9 / 20, delta=2)   # 0.9 m higher, 20 m from the camera

    def test_backpack_items_are_sky_blue_like_vehicles(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.PACKAGE, [unit(0, 20, 0)])
        self.load()
        self.settle()
        colours = {(t.color.r, t.color.g, t.color.b) for t in self.screen_tris()}
        self.assertEqual(colours, {(110, 205, 255)})

    def test_a_vehicle_off_screen_shows_smaller_at_the_edge_with_an_arrow(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.VEHICLE, [unit(0, 20, 0)])                     # ahead: on screen
        self.load()
        self.settle()
        ahead = self.screen_tris()
        self.set_units(self.VEHICLE, [unit(60, -10, 0)])                   # 60 m to the right, level with the camera
        self.frames(5, start=40.0)
        side = self.screen_tris()
        self.assertTrue(side)
        xs = [xyz(v)[0] for t in side for v in (t.a, t.b, t.c)]
        self.assertLessEqual(max(xs), 1920)                                # on screen ...
        self.assertGreater(min(xs), 1920 / 2)                              # ... on its right side
        self.assertGreater(max(xs), 1920 - 40)                             # the arrow points past the margin
        width = lambda tris: max(xyz(v)[0] for t in tris for v in (t.a, t.b, t.c)) - min(
            xyz(v)[0] for t in tris for v in (t.a, t.b, t.c))
        self.assertNotEqual(len(side), len(ahead))                         # no V under it: an arrow instead
        self.assertLess(width(side), width(ahead) + 20)

    def test_other_kinds_off_screen_stay_hidden(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.HELLBOMB, [unit(60, -10, 0)])
        self.load()
        self.settle()
        self.assertEqual(self.screen_tris(), [])

    def set_options(self, values):
        self.fake.option_values = self.lua.table_from(values)
        self.lua.execute("""local fake = ...
            local get = ModOptionsMenu.get
            ModOptionsMenu.get = function(id)
              local v = fake.option_values[id]
              if v ~= nil then return v end
              return get(id)
            end""", self.fake)

    def xs(self):
        return [v._x for t in self.screen_tris() for v in (t.a, t.b, t.c)]

    def test_markers_can_stay_on_where_the_game_shows_its_own_icon(self):
        self.set_options({"pickup_dots.hide_near": False})
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(SAMPLE, [unit(8)])                     # inside the game's own 9 m
        self.load()
        self.settle()
        self.assertIn("samples drawn=1 worn=0", self.status_now())

    def test_the_size_at_the_edge_of_range_is_a_setting(self):
        self.set_options({"pickup_dots.smallest_size": 30})
        stim = "content/fac_helldivers/discoverables/health_pack_discoverable_01/health_pack_discoverable_01"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(-2, 41.95, 0)])            # 50 m, the edge of the 50 m mission range
        self.set_units(stim, [unit(2, 0, 0)])                 # 8 m: full size
        self.load()
        self.settle()
        def widths():
            tris = self.screen_tris()
            left = [v._x for t in tris if t.a._x < 960 for v in (t.a, t.b, t.c)]
            right = [v._x for t in tris if t.a._x > 960 for v in (t.a, t.b, t.c)]
            return max(left) - min(left), max(right) - min(right)
        diamond, full = widths()
        self.assertAlmostEqual(diamond, 15.84 * 0.3, delta=0.05)
        self.fake.units[stim][1].y = 16.9                     # 25 m, the edge of supplies: below its smallest pixels
        self.frames(80, start=30.0)
        self.assertAlmostEqual(widths()[1] / full, 0.3, delta=0.02)

    def test_opacity_is_a_setting_and_only_supplies_fade_with_distance(self):
        self.set_options({"pickup_dots.opacity": 50, "pickup_dots.fade": True})
        stim = "content/fac_helldivers/discoverables/health_pack_discoverable_01/health_pack_discoverable_01"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(-2, 41.95, 0)])            # a mission item at the edge of its range: no fading
        self.set_units(stim, [unit(2, 16.9, 0)])              # a stim at the edge of supplies' range
        self.load()
        self.settle()
        tris = self.screen_tris()
        self.assertEqual({t.color.a for t in tris if t.a._x < 960}, {127})
        self.assertEqual(max(t.color.a for t in tris if t.a._x > 960), 25)   # a fifth of that

    def test_a_stim_up_close_is_solid_whatever_the_opacity(self):
        self.set_options({"pickup_dots.opacity": 50})
        stim = "content/fac_helldivers/discoverables/health_pack_discoverable_01/health_pack_discoverable_01"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(stim, [unit(-1, -5, 0), unit(1, 0, 0)])      # 3 m off; 8 m off
        self.load()
        self.settle()
        tris = self.screen_tris()
        self.assertEqual({t.color.a for t in tris if t.a._x < 960}, {255})   # up close: solid, as the game's icons there
        self.assertEqual({t.color.a for t in tris if t.a._x > 960}, {127})   # farther: the opacity set

    def test_samples_can_fade_far_away_too(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(SAMPLE, [unit(-2, 41.95, 0)])                 # 50 m, the edge of the 50 m sample range
        self.load()
        self.settle()
        self.assertEqual({t.color.a for t in self.screen_tris()}, {255})     # off by default
        self.tearDown(); self.setUp()
        self.set_options({"pickup_dots.fade_samples": True})
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(SAMPLE, [unit(-2, 41.95, 0)])
        self.load()
        self.settle()
        self.assertEqual({t.color.a for t in self.screen_tris()}, {51})      # a fifth at the edge, as supplies

    def add_avatar(self, x, y, z=0.0):
        """A helldiver coming into the world (the ones there keep their units)."""
        avatars = self.fake.units[AVATAR]
        avatars[len(avatars) + 1] = self.lua.table_from(unit(x, y, z))
        return avatars[len(avatars)]

    def reinforce(self, x, y, start):
        """A helldiver dropped in a hellpod at (x, y): 490 m up, the camera following it down, 1 s later on the ground."""
        new = self.add_avatar(x, y, 490)
        self.lua.execute("local fake, x, y = ...; fake.cam.pos = {x, y - 2, 490.6}", self.fake, x, y)
        self.frames(30, start=start)
        new.z = 0
        self.look_at(x, y)
        self.frames(240, start=start + 1)
        return new

    def look_at(self, x, y):
        """The camera 2 m behind (x, y), looking along +y."""
        self.lua.execute("local fake, x, y = ...; fake.cam.pos = {x, y - 2, 0.6}", self.fake, x, y)

    def test_where_you_died_is_marked_till_you_get_there(self):
        self.set_units(AVATAR, [unit(0, -8, 0), unit(20, 0, 0)], loaded=False)   # you; a teammate
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        self.look_at(20, 0)                                            # you died: the camera on the teammate
        self.frames(300, start=61.0)
        self.assertNotIn("death: ", self.log_text())                   # a teammate there all along: not you
        you = self.reinforce(50, 0, start=70.0)                        # reinforced: a new helldiver, the camera on it
        self.assertIn("death: you died at 0.0 -8.0 0.0", self.log_text())
        marks = [p for p in self.points() if abs(p[2] - 1.2) < 1e-6]
        self.assertEqual(marks, [(0.0, -8.0, 1.2)])                    # the body's place, while it lies there
        self.fake.textures_loaded = True
        (b,) = [b for b in self.bitmaps_now(start=79.0) if b.tex.startswith("skull_")]   # the death screen's skull, red
        self.assertEqual((b.c.r, b.c.g, b.c.b), (235, 50, 40))
        you.x, you.y = 0, -12.5                                        # 4.5 m off: still there
        self.look_at(0, -12.5)
        self.frames(30, start=80.0)
        self.assertIn((0.0, -8.0, 1.2), self.points())
        you.y = -11.5                                                  # 3.5 m off: reached
        self.look_at(0, -11.5)
        self.frames(30, start=81.0)
        self.assertIn("death: the mark at 0.0 -8.0 0.0 reached - gone", self.log_text())
        self.assertNotIn((0.0, -8.0, 1.2), self.points())

    def test_a_body_flung_far_leaves_the_mark_where_your_sample_container_dropped(self):
        self.lua.execute("stingray.IdString64 = { from_hex = function(hex) return { hex = hex } end }")
        self.fake.loaded["hex:4d1c334d294dfa97"] = True                # the avatar, by id: the id self-test passes
        box = "hex:a9936cbe561e8180"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(box, [unit(0.3, -8.2, 1.2)])                    # on your back
        self.load()
        self.settle()
        self.frames(120, start=60.0)
        you, carried = self.fake.units[AVATAR][1], self.fake.units[box][1]
        carried.z = 0.2                                                # killed: it drops where you were ...
        you.x = 20                                                     # ... and a blast flings the body 20 m
        self.look_at(20, -8)
        self.frames(120, start=62.0)
        self.reinforce(50, 0, start=70.0)                              # reinforced
        self.assertIn("death: you died at 0.3 -8.2 0.2 (your sample container; the body at 20.0 -8.0 0.0", self.log_text())
        marks = [p for p in self.points() if abs(p[2] - 1.4) < 1e-6]
        self.assertEqual(marks, [(0.3, -8.2, 1.4)])

    def box_setup(self):
        self.lua.execute("stingray.IdString64 = { from_hex = function(hex) return { hex = hex } end }")
        self.fake.loaded["hex:4d1c334d294dfa97"] = True                # the avatar, by id: the id self-test passes
        return "hex:a9936cbe561e8180"

    def test_a_sample_container_you_dropped_and_walked_off_from_is_not_where_you_died(self):
        box = self.box_setup()
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(box, [unit(0.3, -8.2, 1.2)])                    # on your back
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        you, dropped = self.fake.units[AVATAR][1], self.fake.units[box][1]
        dropped.z = 0.2                                                # dropped on purpose ...
        for k in range(600):                                           # ... and 30 m on, for 10 s
            you.y = -8 + 30 * k / 599
            self.look_at(0, you.y)
            self.frames(1, start=61.0 + k / 60)
        self.frames(120, start=72.0)                                   # killed there
        self.reinforce(50, 0, start=80.0)
        self.assertIn("death: you died at 0.0 22.0 0.0 (your body: your sample container is not by it", self.log_text())

    def test_a_teammates_sample_container_you_stood_by_is_not_where_you_died(self):
        box = self.box_setup()
        self.set_units(AVATAR, [unit(0, -8, 0), unit(1.5, -8, 0)], loaded=False)   # you, by a teammate
        self.set_units(box, [unit(1.7, -8.3, 1.2)])                    # on the teammate's back, within 2.5 m of you
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        mate, theirs = self.fake.units[AVATAR][2], self.fake.units[box][1]
        self.frames(120, start=61.0)                                   # you are killed; they run on
        mate.x, theirs.x = 30, 30.2
        self.frames(60, start=64.0)
        self.reinforce(50, 0, start=70.0)
        self.assertIn("death: you died at 0.0 -8.0 0.0 (your body", self.log_text())

    def test_your_sample_container_picked_up_by_a_teammate(self):
        box = self.box_setup()
        self.set_units(AVATAR, [unit(0, -8, 0), unit(30, 0, 0)], loaded=False)   # you; a teammate
        self.set_units(box, [unit(0.3, -8.2, 1.2)])                    # on your back
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        you, mate, yours = self.fake.units[AVATAR][1], self.fake.units[AVATAR][2], self.fake.units[box][1]
        yours.z = 0.2                                                  # killed: it drops ...
        you.x = 12                                                     # ... the body flung 12 m
        self.look_at(30, 0)                                            # watching the teammate
        self.frames(120, start=61.0)
        mate.x, mate.y = 0.3, -8                                       # they come and take it up before you are back
        yours.x, yours.y, yours.z = 0.4, -8.3, 1.2
        self.frames(120, start=64.0)
        self.reinforce(50, 0, start=70.0)
        self.assertIn("death: you died at 12.0 -8.0 0.0 (your body: your sample container is not by it", self.log_text())
        yours.x, yours.y = 20, 20                                      # carried off: the mark stays
        mate.x, mate.y = 20, 20.2
        self.frames(60, start=80.0)
        marks = [p for p in self.points() if abs(p[2] - 1.2) < 1e-6]
        self.assertEqual(marks, [(12.0, -8.0, 1.2)])

    def test_a_new_death_moves_the_mark(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        second = self.reinforce(50, 0, start=70.0)                     # died at 0 -8; reinforced at 50 0
        second.x, second.y = 80, 10                                    # walked off, died there, never back at the first
        self.look_at(80, 10)
        self.frames(60, start=80.0)
        self.reinforce(120, 0, start=90.0)                             # reinforced again
        marks = [p for p in self.points() if abs(p[2] - 1.2) < 1e-6]
        self.assertEqual(marks, [(80.0, 10.0, 1.2)])                   # the last death's only

    def test_a_body_gone_before_you_are_reinforced_leaves_the_mark_where_it_lay(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        body = self.fake.units[AVATAR][1]
        body.x = 6                                                     # killed, flung 6 m ...
        self.frames(60, start=61.0)
        body.alive = False                                             # ... and gone minutes later, before you are back
        self.frames(60, start=200.0)
        self.reinforce(50, 0, start=210.0)
        self.assertIn("death: you died at 6.0 -8.0 0.0 (your body;", self.log_text())
        marks = [p for p in self.points() if abs(p[2] - 1.2) < 1e-6]
        self.assertEqual(marks, [(6.0, -8.0, 1.2)])

    def test_the_mark_shows_while_you_still_come_down(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        new = self.add_avatar(50, 0, 490)                              # your hellpod, the camera on it
        for k in range(90):                                            # coming down at 150 m/s
            new.z = 490 - 150 * k / 60
            self.lua.execute("local fake, z = ...; fake.cam.pos = {50, -2, z + 0.6}", self.fake, new.z)
            self.frames(1, start=70.0 + k / 60)
        self.assertGreater(new.z, 250)                                 # still well up
        self.assertIn("death: you died at 0.0 -8.0 0.0", self.log_text())
        (mark,) = [d for d in self.mod.dots.values() if d[6] == "deaths"]
        self.assertAlmostEqual(mark[4], math.hypot(50, 8), places=3)   # the walk to it, across the ground

    def test_a_teammate_you_watch_reinforced_first_is_not_taken_for_you(self):
        self.set_units(AVATAR, [unit(0, -8, 0), unit(30, 0, 0)], loaded=False)   # you; a teammate
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        self.look_at(30, 0)                                            # you died: watching the teammate
        self.frames(120, start=61.0)
        mate = self.reinforce(60, 0, start=70.0)                       # they died too, and came back first: followed
        self.assertIn("death: you died at 0.0 -8.0 0.0", self.log_text())   # the mark is yours all the same
        for k in range(120):                                           # they run over to your gear ...
            mate.x, mate.y = 60 - 60 * k / 119, -8 * k / 119
            self.look_at(mate.x, mate.y)
            self.frames(1, start=80.0 + k / 60)
        self.assertIn("reached - gone", self.log_text())
        self.reinforce(100, 0, start=83.0)                             # ... as you come back
        self.assertIn("taken for you was moving (a teammate you watched)", self.log_text())
        self.assertIn("death: the mark at 0.0 -8.0 0.0 is back", self.log_text())
        marks = [p for p in self.points() if abs(p[2] - 1.2) < 1e-6]
        self.assertEqual(marks, [(0.0, -8.0, 1.2)])                    # one mark, yours, not at the teammate

    def test_leaving_a_mission_the_ships_helldiver_is_not_taken_for_your_death(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        self.add_avatar(0, 2.5, 20)                                    # 20 m up, and stays there (test.3 log)
        self.lua.execute("local fake = ...; fake.cam.pos = {0, 0.5, 20.6}", self.fake)   # the camera on it
        self.frames(300, start=70.0)
        self.assertIn("you: the helldiver at 0.0 2.5 20.0", self.log_text())
        self.assertNotIn("death: ", self.log_text())

    def test_a_teammate_reinforced_is_not_taken_for_your_death(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.load()
        self.settle()
        self.frames(60, start=60.0)
        self.add_avatar(30, 0)                                         # a teammate drops in, far from the camera
        self.frames(300, start=70.0)
        self.look_at(30, 0)                                            # the camera passes it for a moment
        self.frames(60, start=80.0)
        self.look_at(0, -8)
        self.frames(300, start=82.0)
        self.assertNotIn("death: ", self.log_text())

    def test_sample_and_supply_markers_sit_where_the_games_icons_do(self):
        self.set_units(AVATAR, [unit(0, -11, 0)], loaded=False)
        self.set_units(SAMPLE, [unit(0, 0, 0)])               # straight ahead: it would be centred at 960
        self.load()
        self.settle()
        xs = self.xs()
        self.assertAlmostEqual((max(xs) + min(xs)) / 2, 960 - 28, places=3)

    def test_kinds_can_be_switched_off_and_the_settings_are_ranges_switches_and_look(self):
        self.lua.execute("""
            local get = ModOptionsMenu.get
            ModOptionsMenu.get = function(id) if id == 'pickup_dots.show_mission' then return false end return get(id) end
        """)
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.assertEqual(self.screen_tris(), [])
        ids = sorted(self.fake.options.keys())
        look = ["pickup_dots." + n for n in ("distance", "fade", "fade_samples", "hide_near", "opacity", "smallest_size")]
        self.assertEqual([i for i in ids if not i.startswith(("pickup_dots.range_", "pickup_dots.show_"))], look)
        self.assertEqual(len(ids), 14 + 6)
        kinds = sorted(i[len("pickup_dots.show_"):] for i in ids if i.startswith("pickup_dots.show_"))
        self.assertEqual(kinds, ["deaths", "hellbombs", "mission", "objectives", "samples", "supplies", "vehicles"])
        self.assertTrue(self.fake.options["pickup_dots.fade"].default)
        self.assertEqual(self.fake.options["pickup_dots.show_vehicles"].type, "toggle")

    def test_a_passing_drawing_failure_skips_only_that_frame(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.lua.execute("""local fake = ...
            local triangle = fake.chef.triangle
            fake.fail_left = 2
            fake.chef.triangle = function(...)
              if fake.fail_left > 0 then fake.fail_left = fake.fail_left - 1; error('native: a passing failure') end
              return triangle(...)
            end""", self.fake)
        self.frames(10, start=30.0)
        self.assertEqual(len(self.screen_points()), 1)        # drawn again
        self.assertIn("drawing: failed (", self.log_text())

    def test_settings_are_in_english(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.load()
        labels = [self.fake.options[k].label for k in self.fake.options.keys()]
        self.assertIn("Show mission items (SSSDs, launch codes, shells)", labels)
        self.assertIn("Vehicles distance (m)", labels)
        self.assertTrue(all(ord(ch) < 128 for l in labels for ch in l))

    def test_markers_hide_while_the_cursor_shows(self):
        self.lua.execute("local fake = ...; stingray.Window = { show_cursor = function() return fake.cursor == true end }",
                         self.fake)
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.assertEqual(len(self.screen_points()), 1)
        self.fake.cursor = True                   # Esc: the menu opens
        self.frames(5, start=30.0)
        self.assertEqual(self.screen_points(), [])
        self.fake.cursor = False
        self.frames(5, start=31.0)
        self.assertEqual(len(self.screen_points()), 1)
        log = self.log_text()
        self.assertIn("menus: cursor shown - markers hidden", log)
        self.assertIn("menus: cursor hidden", log)

    def test_no_camera_yet_draws_nothing(self):
        self.fake.no_camera = True
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.assertEqual(self.screen_tris(), [])
        self.assertEqual(self.dots(), 1)   # found, drawn once there is a camera
        self.fake.no_camera = False
        self.frames(1, start=30.0)
        self.assertEqual(len(self.screen_points()), 1)
        self.assertNotIn("failed", self.log_text())

class LifecycleTests(Case):
    def test_without_can_get_no_target_is_looked_up(self):
        self.lua.execute("stingray.Application.can_get = nil")
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(5)])
        self.load()
        self.settle()
        self.assertEqual(set(self.fake.lookups.keys()), {AVATAR})
        self.assertIn("can_get: MISSING", self.log_text())

    def test_waits_for_the_world_to_settle(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.load()
        self.frames(1, start=11.0)
        self.frames(200, start=11.1)
        self.assertEqual(len(self.fake.lookups), 0)

    def test_waits_for_startup_grace(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.load()
        self.frames(30, start=0.0)
        self.assertEqual(len(self.fake.lookups), 0)

    def test_no_helldiver_no_lookups_and_no_world_is_quiet(self):
        self.set_units(MARK, [unit(1)])
        self.load()
        self.settle()
        self.assertEqual(set(self.fake.lookups.keys()), {AVATAR})
        self.fake.world = None
        self.frames(10, start=30.0)
        self.assertNotIn("failed", self.log_text())

    def test_avatar_hex_matches_its_name(self):
        with open(build.SOURCE, encoding="utf-8") as f:
            self.assertIn("local AVATAR_HEX = '%016x'" % build.murmur64(AVATAR.encode()), f.read())

    def test_id_only_mission_items_are_looked_up_once_the_self_test_passes(self):
        self.lua.execute("""
            stingray.IdString64 = { from_hex = function(hex) return { hex = hex } end }
        """)
        self.fake.loaded["hex:4d1c334d294dfa97"] = True      # the avatar, by id
        mission = next(t for t in self.targets() if t["group"] == "mission" and t.get("hex"))
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units("hex:" + mission["hex"], [unit(8)])   # a briefcase, say, 8 m off
        self.load()
        self.settle()
        log = self.log_text()
        self.assertIn("id self-test IdString64: avatar=true made-up=false", log)
        self.assertIn("unnamed targets: id form IdString64 works - looked up by id", log)
        self.assertEqual(self.dots(), 1)
        self.frames(1, start=200.0)
        self.assertIn("mission drawn=1", self.log_text())

    def test_equipment_and_weapons_are_not_targets(self):
        with open(build.TARGETS, encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("/equipment/", text)
        self.assertNotIn("hellpod_equipment", text)
        self.assertIn("briefcase", text)

    def targets(self):
        with open(build.TARGETS, encoding="utf-8") as f:
            rows = self.lua.execute(f.read())
        return [dict(rows[i].items()) for i in range(1, len(rows) + 1)]

    def test_without_chef_shared_loader_it_stays_off_and_says_why(self):
        mod = self.lua.execute(self.source)
        self.assertEqual(mod.status, "no Chef Shared Loader")
        self.lua.execute("local fake = ...; fake.chef.bitmap = nil", self.fake)
        self.lua.execute("CodexPickupDots = nil")
        mod = self.lua.execute(self.source, self.fake.chef)
        self.assertEqual(mod.status, "Chef Shared Loader without bitmap (too old?)")
        self.assertIn("FATAL: Chef Shared Loader without bitmap", self.log_text())

    def test_it_stays_on_after_a_crash_and_the_mesh_calls_have_a_crash_key_per_unit_kind(self):
        head = build.built_source()[:400]
        self.assertIn("\n-- HD2-Keep-On-Crash: yes", head)             # Chef Shared Loader keeps it on, skipping only the call
        codes = "content/objectives/obj_common/generic_intel/generic_intel"
        bomb = ScreenTests.HELLBOMB
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        picked = unit(0, -6.5, 0)
        picked.update(meshes=6)
        self.set_units(codes, [picked])
        self.set_units(bomb, [unit(0, 30, 0)])
        self.load()
        self.settle()
        self.frames(5, start=40.0)
        kinds = {k: v for k, v in self.fake.kinds.items()}
        for call in ("Unit.box", "Unit.num_meshes", "Unit.mesh", "Mesh.visibility"):
            self.assertIn(call, kinds)
        self.assertEqual(kinds["Unit.box"], bomb)                      # its own key: a crash on one kind skips that kind
        self.assertEqual(kinds["Mesh.visibility"], codes)

    def test_loads_once(self):
        first = self.load()
        second = self.lua.execute(self.source, self.fake.chef)
        self.assertTrue(self.lua.globals().rawequal(first, second))


class ArchiveTests(unittest.TestCase):
    def test_boot_mod_loader_finds_the_mod(self):
        """Read the archive the way boot_mod_loader.lua's declared_in() does."""
        with tempfile.TemporaryDirectory() as tmp:
            path = build.write_module(tmp, build.RESOURCE, build.built_source())
            with open(path, "rb") as f:
                data = f.read()
        magic, types, count = struct.unpack_from("<3I", data, 0)
        self.assertEqual((magic, types, count), (0xF0000011, 1, 1))
        row = 0x48 + types * 32
        name_id, type_id, at = struct.unpack_from("<3Q", data, row)
        size = struct.unpack_from("<I", data, row + 56)[0]
        self.assertEqual(type_id, build.murmur64(b"lua"))
        self.assertEqual(name_id, build.murmur64(build.RESOURCE.encode()))
        length, flag = struct.unpack_from("<2I", data, at)
        self.assertEqual(flag, 2)
        self.assertEqual(size, length + 8)
        text = data[at + 8:at + 8 + length].decode("utf-8")
        self.assertTrue(text.startswith("-- HD2-Addon: mods/codex/pickup_dots\n"))

    def test_compiles_on_lua51(self):
        lua = lua51.LuaRuntime()
        compiled = lua.eval("function(src) local f, err = loadstring(src, 'pickup_dots'); return f ~= nil, err end")
        ok, err = compiled(build.built_source())
        self.assertTrue(ok, err)


if __name__ == "__main__":
    unittest.main()
