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
local fake = { now = 0, lines = {}, dispatched = 0, created = 0, lookups = {}, units = {}, loaded = {},
               logs = {}, gui_mode = 'immediate', layered = true, guis = 0, tris = {}, frame_tris = {},
               live = {}, next_id = 0, assets = {} }
os.clock = function() return fake.now end
local real_getenv = os.getenv
fake.appdata = 'Z:\\no-such-folder'
os.getenv = function(k)
  if k == 'APPDATA' then return fake.appdata end
  if k == 'LOCALAPPDATA' then return fake.localappdata end   -- nil: the mod falls back to open_log
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
    create_line_object = function(world, no_depth)
      fake.created = fake.created + 1
      return { world = world, no_depth = no_depth }
    end,
    create_world_gui = function(world, pose, w, h, flag)
      assert(pose == 'IDENTITY' and w == 1 and h == 1)
      if fake.gui_mode == 'retained' and flag ~= nil then error('unknown flag ' .. tostring(flag)) end
      fake.guis = fake.guis + 1
      return { immediate = flag == 'immediate', world = world }
    end,
    destroy_line_object = function() error('must not be called') end,
    destroy_gui = function(world, gui) fake.destroyed_gui = { world = world, gui = gui } end,
  },
  Unit = {
    alive = function(u) return u.alive ~= false end,
    world_position = function(u, node) return vec(u.x, u.y, u.z) end,
  },
  LineObject = {
    reset = function(lo) fake.lines = {} end,
    add_line = function(lo, color, a, b) fake.lines[#fake.lines + 1] = { color = color, a = a, b = b } end,
    dispatch = function(world, lo)
      assert(#fake.lines > 0, 'dispatched an empty line object')
      fake.dispatched = fake.dispatched + 1
    end,
  },
  Gui = {
    triangle = function(g, a, b, c, layer, color)
      if fake.layered then
        assert(type(layer) == 'number' and is_color(color), 'native: bad arguments')
      else
        assert(is_color(layer) and color == nil, 'native: bad arguments')
        color = layer
      end
      assert(is_vec(a) and is_vec(b) and is_vec(c))
      fake.next_id = fake.next_id + 1
      local tri = { a = a, b = b, c = c, color = color, id = fake.next_id, wname = tostring(g.world), layer = layer }
      tri.screen = g.screen
      if g.immediate then fake.tris[#fake.tris + 1] = tri else fake.live[#fake.live + 1] = tri end
      return fake.next_id
    end,
    destroy_triangle = function(g, id)
      for i, tri in ipairs(fake.live) do
        if tri.id == id then table.remove(fake.live, i); return end
      end
      error('destroyed an unknown triangle')
    end,
  },
  Matrix4x4 = { identity = function() return 'IDENTITY' end },
  Script = { temp_byte_count = function() return 7 end, set_temp_byte_count = function(n) fake.temp = n end },
  Vector3 = Vector3,
  Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end,
}

CowboyBingusModLoader = {
  open_log = function(name)
    fake.logs[name] = fake.logs[name] or {}
    local sink = fake.logs[name]
    return {
      write = function(self, ...) for _, part in ipairs({ ... }) do sink[#sink + 1] = tostring(part) end end,
      flush = function() end, close = function() end,
    }
  end,
}

fake.updates = 0
function update(dt)
  -- an immediate GUI shows what it was given this frame only: drawn after the game's update (0.17), so
  -- this frame's table is the one filled from here on
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


class Case(unittest.TestCase):
    def setUp(self):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.fake = self.lua.execute(FAKE_ENGINE)
        self.source = build.built_source()

    def set_units(self, key, units, loaded=True):
        self.fake.units[key] = self.lua.table(*[self.lua.table_from(u) for u in units])
        if loaded:
            self.fake.loaded[key] = True

    def load(self):
        mod = self.lua.execute(self.source)
        self.assertEqual(mod.status, "running", self.log_text())
        return mod

    def log_text(self, name="PickupDots.log"):
        sink = self.fake.logs[name]
        return "".join(sink.values()) if sink else ""

    def frames(self, count, start, step=1 / 60):
        update = self.lua.globals().update
        for i in range(count):
            self.fake.now = start + i * step
            update(0.016)

    def settle(self, count=40):
        """Past the start-up grace (10 s) and the world settle time (8 s)."""
        self.frames(1, start=11.0)          # world first seen at 11 s
        self.frames(count, start=20.0)      # 9 s later

    def shapes(self):
        """The diamonds drawn in the 3D scene now (line outlines), each as its corners (top, right, bottom, left)."""
        lines = [l for l in self.fake.lines.values() if l.color.a > 0]
        self.assertEqual(len(lines) % 4, 0)
        for l in lines:
            self.assertEqual((l.color.a, l.color.r, l.color.g, l.color.b), (255, 255, 255, 255))
        return [[xyz(lines[i + k].a) for k in range(4)] for i in range(0, len(lines), 4)]

    def dots(self):
        return len(self.shapes())

    def centre(self):
        pts = [p for shape in self.shapes() for p in shape]
        return tuple(sum(c) / len(pts) for c in zip(*pts))


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
        self.assertIn("81 target resources: 78 named, 3 by id only (looked up if the id self-test passes)", log)
        self.frames(1, start=200.0)                   # the next status line, after a full sweep
        log = self.log_text()
        self.assertIn("found: il_sarcophagus=2", log)
        self.assertIn("mission drawn=1 worn=0 far=1", log)

    def test_diamond_faces_the_helldiver_point_up_and_scales_with_distance(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(20, 5, 0)])
        self.load()
        self.settle()
        (shape,) = self.shapes()
        top, right, bottom, left = shape
        c = (20.0, 5.0, 0.6)
        view = (c[0] - 0.0, c[1] - 0.0, c[2] - 1.6)
        vl = math.sqrt(sum(v * v for v in view))
        for p in shape:  # every corner lies across the line of sight
            d = tuple(a - b for a, b in zip(p, c))
            self.assertAlmostEqual(sum(a * b for a, b in zip(d, view)) / vl, 0.0, places=6)
        h = min(0.4, max(0.05, math.sqrt(20 ** 2 + 5 ** 2) * 0.008))
        self.assertAlmostEqual(math.dist(top, c), h, places=6)
        self.assertAlmostEqual(math.dist(bottom, c), h, places=6)
        self.assertAlmostEqual(math.dist(left, c), h, places=6)   # a square on its corner
        self.assertAlmostEqual(math.dist(right, c), h, places=6)
        self.assertGreater(top[2], c[2])     # the top corner points up
        self.assertAlmostEqual(left[2], c[2], places=6)   # the side corners are level

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
        self.assertLess(max(p[0] for s in self.shapes() for p in s), 2 + 40 * 0.3 + 1)

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

    def test_the_log_is_written_fresh_each_launch_and_the_last_one_kept(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            folder = os.path.join(tmp, "CowboyBingus", "Helldivers2", "Logs")
            os.makedirs(folder)
            with open(os.path.join(folder, "PickupDots.log"), "w") as f:
                f.write("last launch" + chr(10))
            self.fake.localappdata = tmp
            self.set_units(AVATAR, [unit(0)], loaded=False)
            self.load()
            self.lua.globals().shutdown()
            with open(os.path.join(folder, "PickupDots.previous.log")) as f:
                self.assertEqual(f.read(), "last launch" + chr(10))
            with open(os.path.join(folder, "PickupDots.log")) as f:
                text = f.read()
            self.assertIn("Pickup Dots 2.2.0 loading", text)
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
        xs = sorted(round(sum(p[0] for p in s) / 4, 1) for s in self.shapes())
        self.assertEqual(xs, [-1.5, 0.0, 8.6])

    def test_super_samples_are_left_to_the_game_further_off(self):
        egg = "content/env_bugs/assets/samples/bug_egg_super_sample_01"
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(egg, [unit(15)])                        # the game shows its icon out to 20 m
        self.set_units(SAMPLE, [unit(-15)])                    # a common sample's only to 9 m
        self.load()
        self.settle()
        xs = [round(sum(p[0] for p in s) / 4, 1) for s in self.shapes()]
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


SCREEN_ENGINE = r"""
fake.ui = fake.new_world('ui-world')
stingray.Application.worlds = function() return { fake.world, fake.ui } end
-- camera 10 m behind the origin, 0.6 m up, looking along +y: right +x, up +z
fake.cam = { pos = {0, -10, 0.6}, right = {1, 0, 0}, fwd = {0, 1, 0}, up = {0, 0, 1} }
stingray.World.debug_camera_pose = function(w) return 'POSE' end
local function v(t) return stingray.Vector3(t[1], t[2], t[3]) end
stingray.Matrix4x4.translation = function(m) return v(fake.cam.pos) end
stingray.Matrix4x4.right = function(m) return v(fake.cam.right) end
stingray.Matrix4x4.forward = function(m) return v(fake.cam.fwd) end
stingray.Matrix4x4.up = function(m) return v(fake.cam.up) end
stingray.Gui.resolution = function() return 1920, 1200 end
fake.screen_guis = 0
stingray.World.create_screen_gui = function(world, flag, ...)
  assert(tostring(world) == (fake.screen_world or 'ui-world'), 'screen GUI on the wrong world: ' .. tostring(world))
  if fake.screen_mode == 'retained' and flag == 'immediate' then error('unknown flag') end
  fake.screen_guis = fake.screen_guis + 1
  return { immediate = flag == 'immediate', screen = true, world = world }
end
fake.options = {}
ModOptionsMenu = {
  api = 1,
  register_option = function(id, spec) fake.options[id] = spec; return true end,
  get = function(id) if id == 'pickup_dots.fov_override' then return fake.option_value end end,
  on_change = function(id, fn) if id == 'pickup_dots.fov_override' then fake.option_changed = fn end; return true end,
}
"""


class ScreenTests(Case):
    def setUp(self):
        super().setUp()
        self.lua.execute("local fake = ...; " + SCREEN_ENGINE.replace("\n", "\n"), self.fake)

    TRIS_PER_ICON = 9   # an outline (two triangles per side), then the filled lower half

    def screen_tris(self, live=False):
        source = self.fake.live if live else self.fake.frame_tris
        return [t for t in source.values() if t.screen]

    def screen_points(self, live=False):
        tris = self.screen_tris(live)
        self.assertEqual(len(tris) % self.TRIS_PER_ICON, 0)
        out = []
        for i in range(0, len(tris), self.TRIS_PER_ICON):
            pts = [xyz(v) for t in tris[i:i + 8] for v in (t.a, t.b, t.c)]   # the outline: centred
            out.append((sum(q[0] for q in pts) / len(pts), sum(q[2] for q in pts) / len(pts)))
        return out

    def test_item_ahead_is_drawn_at_screen_centre_and_nothing_in_3d(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        (pt,) = self.screen_points()
        self.assertAlmostEqual(pt[0], 960.0, places=4)
        self.assertAlmostEqual(pt[1], 600.0, places=4)   # dot height 0.6 = camera height: centre
        self.assertEqual(self.fake.created, 0)  # nothing in the 3D scene
        self.assertIn("drawing: 2 world(s), 1 besides the main one, setting 1; screen GUI goes on other world #1", self.log_text())
        self.assertIn("drawing: immediate screen GUI", self.log_text())

    def test_field_of_view_comes_from_the_game_settings(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            folder = os.path.join(tmp, "Arrowhead", "Helldivers2")
            os.makedirs(folder)
            with open(os.path.join(folder, "user_settings.config"), "w", encoding="utf-8") as f:
                f.write("aspect_ratio = -1\nvertical_fov = 55\nupscaling_method = 0\n")
            self.fake.appdata = tmp
            self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
            self.set_units(MARK, [unit(1, 0, 0)])  # 1 m right, 10 m ahead
            self.load()
            self.settle()
            (pt,) = self.screen_points()
            f55 = 600 / math.tan(math.radians(55) / 2)
            self.assertEqual(pt[0], math.floor(960 + f55 / 10 + 0.5))
            self.assertIn("field of view: 55 degrees from the game settings", self.log_text())

    def test_without_the_game_settings_50_degrees_is_used(self):
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

    def test_the_screen_gui_is_destroyed_at_shutdown(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.lua.globals().shutdown()
        self.assertEqual(str(self.fake.destroyed_gui.world), "ui-world")
        self.assertIn("shutdown: screen GUI destroyed", self.log_text())

    def test_diamond_is_smaller_with_its_lower_half_filled_on_a_low_layer(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        tris = self.screen_tris()
        self.assertEqual(len(tris), 9)
        fill = [xyz(v) for v in (tris[8].a, tris[8].b, tris[8].c)]
        self.assertEqual(sorted((round(x, 3), round(y, 3)) for x, _, y in fill),
                         [(952.08, 600.0), (960.0, 592.08), (967.92, 600.0)])   # left, bottom, right
        self.assertEqual({t.layer for t in tris}, {1})

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

    def test_retained_screen_gui_removes_last_frames_triangles(self):
        self.fake.screen_mode = "retained"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.assertEqual(len(self.screen_tris(live=True)), 9)
        self.assertIn("retained screen GUI", self.log_text())
        self.set_units(MARK, [unit(0, 60, 0)])  # out of range: cleared
        self.frames(40, start=21.0)
        self.assertEqual(len([t for t in self.fake.live.values() if t.screen]), 0)

    def test_without_a_ui_world_the_screen_gui_goes_on_the_main_world(self):
        self.lua.execute("""local fake = ...
            stingray.Application.worlds = function() return { fake.world } end
            fake.screen_world = 'world-1'""", self.fake)
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.assertEqual(len(self.screen_points()), 1)
        log = self.log_text()
        self.assertIn("drawing: 1 world(s), 0 besides the main one, setting 1; screen GUI goes on the main world", log)

    def test_says_why_when_there_is_no_camera_pose(self):
        self.lua.execute("local fake = ...; fake.cam.pos = {0, 0, 0}", self.fake)
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle(count=700)
        self.assertIn("screen GUI not used here (no camera pose for 600 frames)", self.log_text())

    def test_worlds_that_all_print_the_same_are_still_told_apart(self):
        # in the game every world prints as '[World]' (0.6.1 log); the engine compares them with ==
        self.lua.execute("""local fake = ...
            local mt = { __tostring = function() return '[World]' end }
            fake.world = setmetatable({}, mt)
            fake.ui = setmetatable({}, mt)
            stingray.Application.worlds = function() return { fake.world, fake.ui } end
            fake.screen_world = '[World]'
            local create = stingray.World.create_screen_gui
            stingray.World.create_screen_gui = function(world, ...)
              assert(rawequal(world, fake.ui), 'screen GUI must go on the other world')
              return create(world, ...)
            end""", self.fake)
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

    def test_the_screen_gui_is_kept_across_missions_and_replaced_with_its_world(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.assertEqual(self.fake.screen_guis, 1)
        self.fake.world = self.fake.new_world("world-2")             # the next mission, same UI world
        self.frames(1, start=30.0)
        self.frames(40, start=39.0)
        self.assertEqual(len(self.screen_points()), 1)
        self.assertEqual(self.fake.screen_guis, 1)
        self.assertIsNone(self.fake.destroyed_gui)
        self.lua.execute("local fake = ...; fake.ui = fake.new_world('ui-world')", self.fake)  # a new UI world
        self.frames(40, start=50.0)
        self.assertEqual(self.fake.screen_guis, 2)
        self.assertIsNone(self.fake.destroyed_gui)                     # the old one went with its world

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
        self.set_units(AVATAR, [unit(0, -11, 0)], loaded=False)   # beyond the game's own sample icon
        self.set_units(SAMPLE, [unit(-1, 0, 0)])          # a common sample
        self.set_units(stim, [unit(1, -3, 0)])            # 8 m off: full size
        self.load()
        self.settle()
        tris = self.screen_tris()
        self.assertTrue(all((t.color.r, t.color.g, t.color.b) == (255, 255, 255) for t in tris))   # all white
        right = [t for t in tris if t.a._x > 960]
        self.assertEqual(len(right), 2 * 27)               # the stim: the game's syringe, 27 rectangles
        self.assertEqual(len(tris) - len(right), 22)       # the sample: two halves of a circle, 11 triangles each
        ys = [v._z for t in tris for v in (t.a, t.b, t.c)]
        f = 600 / math.tan(math.radians(50) / 2)
        self.assertLess(max(ys), 600 - 0.3 * f / 10 + 10)  # 0.3 m above the items: below a diamond's 0.6 m

    def test_ammo_grenade_and_supply_are_the_games_icons_pixel_for_pixel(self):
        ammo = "content/fac_helldivers/discoverables/ammo_box_discoverable_01/ammo_box_discoverable_01"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(ammo, [unit(0, 0, 0)])
        self.load()
        self.settle()
        tris = self.screen_tris()
        self.assertGreater(len(tris), 0)
        coords = {v._x for t in tris for v in (t.a, t.b, t.c)} | {v._z for t in tris for v in (t.a, t.b, t.c)}
        self.assertTrue(all(c == int(c) for c in coords))              # on whole pixels
        self.assertEqual({t.color.a for t in tris} - {63, 127, 191, 255}, set())   # see-through edges, in quarters
        self.assertEqual(max(v._x for t in tris for v in (t.a, t.b, t.c))
                         - min(v._x for t in tris for v in (t.a, t.b, t.c)), 19)   # 19 px across, as made

    def test_artillery_shells_get_diamonds_and_carried_packages_the_games_icon(self):
        shell = "content/objectives/obj_common/seaf_artillery/seaf_shell_regular"
        case = "content/objectives/obj_common/briefcase/briefcase"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(shell, [unit(-1, 0, 0), unit(0, 50, 0)])   # 8 m: in; 58 m: past mission items' 50 m
        self.set_units(case, [unit(1, 0, 0)])
        self.load()
        self.settle()
        tris = self.screen_tris()
        left = [t for t in tris if t.a._x < 960]
        self.assertEqual(len(left), 9)                       # the shell: a diamond
        self.assertGreater(len(tris) - len(left), 9)         # the briefcase: the game's package icon
        self.assertTrue(all(t.color.a in (63, 127, 191, 255) for t in tris if t.a._x > 960))

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

    def test_launch_codes_a_helldiver_stood_at_are_taken_for_picked_up(self):
        codes = "content/objectives/obj_common/generic_intel/generic_intel"
        self.set_units(AVATAR, [unit(0, -8, 0), unit(10, 0, 0)], loaded=False)   # you; a teammate at them
        self.set_units(codes, [unit(10, 1.2, 0), unit(-6, 0, 0)])
        self.load()
        self.settle()                                                  # 9 s on: long enough
        self.assertIn("mission drawn=1 worn=1", self.status_now())
        self.assertIn("taken: the item at 10.0 1.2 0.0 is taken for picked up (a helldiver standing at it)",
                      self.log_text())
        self.fake.units[AVATAR][2].x = 30                              # the teammate goes: they stay taken
        self.frames(10, start=30.0)
        self.assertIn("mission drawn=1 worn=1", self.status_now())

    # Chef Shared Loader hands the mod its helpers as the chunk's argument.
    FAKE_CHEF = """
        local fake = ...
        fake.texts = {}
        fake.mission = true
        return {
          api = 3,
          camera = function() return fake.chef_cam end,
          in_mission = function() return fake.mission end,
          screen = function() return 1920, 1200 end,
          color = function(r, g, b, a) return {r = r, g = g, b = b, a = a} end,
          text_width = function(s, px) return #s * px / 2 end,
          text = function(x, y, s, px, c) fake.texts[#fake.texts + 1] = {x = x, y = y, s = s, px = px, c = c} end,
          unit_alive = function(u) return true end,
          mouse_down = function(name) return name == 'right' and fake.rmb == true end,
          key_down = function(name) return name == 'e' and fake.e_key == true end,
          unit_position = function(u, node)
            if node and node > 1 then return u.x, u.y + node, u.z + (u.blast or 0) * node end
            return u.x, u.y, u.z
          end,
          unit_rotation = function(u, node)
            if node == 3 and u.turn then return math.sin(u.turn), math.cos(u.turn), 0, 0 end
            return 0, 1, 0, 0
          end,
          unit_node = function(u, name) return nil end,
          call = function(name, ...)
            if name == 'Unit.num_scene_graph_items' then return 3 end
            return nil, 'not in the fake'
          end,
          bitmap = function(tex, x, y, w, h, c)
            fake.bitmaps = fake.bitmaps or {}
            fake.bitmaps[#fake.bitmaps + 1] = {tex = tex, x = x, y = y, w = w, h = h}
            return fake.textures_loaded == true
          end,
        }
    """

    def load_with_chef(self):
        chef = self.lua.execute(self.FAKE_CHEF, self.fake)
        mod = self.lua.execute(self.source, chef)
        self.assertEqual(mod.status, "running", self.log_text())
        return mod

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

    def test_with_chef_icons_can_come_from_the_games_textures(self):
        self.set_options({"pickup_dots.game_textures": True})
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.fake.textures_loaded = True
        ammo = "content/fac_helldivers/discoverables/ammo_box_discoverable_01/ammo_box_discoverable_01"
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(ammo, [unit(0, 0, 0)])
        self.load_with_chef()
        self.settle()
        last = list(self.fake.bitmaps.values())[-1]
        self.assertEqual(last.tex, "7615d6a35c657087")
        self.assertAlmostEqual(last.h * 144 / 192, 19, delta=1)       # the icon in it: as tall as the pixel one
        self.assertEqual(self.screen_tris(), [])                       # no pixel icon besides
        self.fake.textures_loaded = False                              # not loaded: the pixel icon after all
        self.frames(5, start=30.0)
        self.assertGreater(len(self.screen_tris()), 0)

    def test_with_chef_launch_codes_you_pick_up_leave_other_codes_marked(self):
        codes = "content/objectives/obj_common/generic_intel/generic_intel"
        self.fake.chef_cam = self.lua.table_from({"x": 0, "y": -10, "z": 0.6, "fx": 0, "fy": 1, "fz": 0,
                                                  "fov": math.radians(50)})
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(codes, [unit(0, -6.5, 0), unit(5, 5, 0)])      # one at you, one farther on
        self.load_with_chef()
        self.settle()
        self.fake.e_key = True
        self.frames(3, start=30.0)
        self.fake.e_key = False
        self.frames(80, start=40.0)
        self.assertEqual(self.log_text().count("taken: "), 1)
        self.assertEqual(len(self.screen_points()), 1)                 # the other codes keep their marker

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
        self.assertEqual(order, ["show_samples", "range_samples", "show_supplies", "range_supplies", "fade",
                                 "show_mission", "range_mission", "show_objectives", "range_objectives",
                                 "show_vehicles", "range_vehicles", "distance", "hide_near", "smallest_size", "opacity"])

    def test_vehicles_are_sky_blue(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(self.VEHICLE, [unit(0, 20, 0)])
        self.load()
        self.settle()
        colours = {(t.color.r, t.color.g, t.color.b) for t in self.screen_tris()}
        self.assertEqual(colours, {(110, 205, 255)})

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
        look = ["pickup_dots." + n for n in ("distance", "fade", "hide_near", "opacity", "smallest_size")]
        self.assertEqual([i for i in ids if not i.startswith(("pickup_dots.range_", "pickup_dots.show_"))], look)
        self.assertEqual(len(ids), 10 + 5)
        kinds = sorted(i[len("pickup_dots.show_"):] for i in ids if i.startswith("pickup_dots.show_"))
        self.assertEqual(kinds, ["mission", "objectives", "samples", "supplies", "vehicles"])
        self.assertTrue(self.fake.options["pickup_dots.fade"].default)
        self.assertEqual(self.fake.options["pickup_dots.show_vehicles"].type, "toggle")

    def test_a_passing_screen_failure_does_not_turn_the_screen_off(self):
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.lua.execute("""local fake = ...
            local triangle = stingray.Gui.triangle
            fake.fail_left = 2
            stingray.Gui.triangle = function(...)
              if fake.fail_left > 0 then fake.fail_left = fake.fail_left - 1; error('native: a passing failure') end
              return triangle(...)
            end""", self.fake)
        self.frames(10, start=30.0)
        self.assertEqual(len(self.screen_points()), 1)        # back on the screen
        self.assertEqual(self.fake.created, 0)                 # never fell back to the 3D scene for good
        self.assertNotIn("back to drawing in the 3D scene", self.log_text())

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
        self.assertEqual(str(self.fake.destroyed_gui.world), "ui-world")   # the screen GUI itself is gone
        self.assertEqual(self.fake.screen_guis, 1)
        self.fake.cursor = False
        self.frames(5, start=31.0)
        self.assertEqual(len(self.screen_points()), 1)
        self.assertEqual(self.fake.screen_guis, 2)                          # made again
        log = self.log_text()
        self.assertIn("menus: cursor shown - markers hidden", log)
        self.assertIn("menus: cursor hidden", log)

    def test_no_camera_yet_falls_back_to_the_3d_scene(self):
        self.lua.execute("local fake = ...; fake.cam.pos = {0, 0, 0}", self.fake)  # pose not set yet
        self.set_units(AVATAR, [unit(0, -8, 0)], loaded=False)
        self.set_units(MARK, [unit(0, 0, 0)])
        self.load()
        self.settle()
        self.assertEqual(self.screen_points(), [])
        self.assertEqual(self.dots(), 1)  # drawn in the 3D scene instead


class LifecycleTests(Case):
    def test_a_line_object_only_when_there_is_something_to_draw(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(60)])  # out of range
        self.load()
        self.settle()
        self.assertEqual(self.fake.created, 0)
        self.set_units(MARK, [unit(5)])
        self.frames(80, start=21.0)
        self.assertEqual(self.fake.created, 1)

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

    def test_trace_names_each_native_call_after_a_world_change(self):
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(MARK, [unit(5)])
        self.load()
        self.settle()
        trace = self.log_text("PickupDots.trace.log")
        self.assertIn("--- world changed: world #1", trace)
        self.assertIn("units_by_resource avatar", trace)
        self.assertIn("create_line_object", trace)
        self.assertLess(trace.index("can_get unit " + MARK), trace.index("units_by_resource " + MARK))

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

    def test_api_inventory_is_logged(self):
        self.load()
        log = self.log_text()
        self.assertIn("api World (", log)
        self.assertIn("api Gui (", log)

    def test_loads_once(self):
        first = self.load()
        second = self.lua.execute(self.source)
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
