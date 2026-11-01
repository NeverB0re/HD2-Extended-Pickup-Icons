"""Native Chef settings, persistence and actual marker integration on Lua 5.1."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
import build
from test_extended_pickup_icons_range import Case, AVATAR, SAMPLE, unit
import test_extended_pickup_icons_range as harness


BACKEND = r'''
local saved = ... or {}
local rows, callbacks, reads = {}, {}, 0
local chef = {}
function chef.has(name) return name == 'option_headings' or name == 'option_folds' end
function chef.option(id, spec)
    assert(not rows[id], 'duplicate option')
    assert(#id <= 60)
    local value = saved[id]
    if value == nil then value = spec.default end
    rows[id] = {spec=spec, value=value}
    return value
end
function chef.get(id) reads = reads + 1; return rows[id] and rows[id].value end
function chef.set(id, value)
    local r = rows[id]; assert(r, 'unknown option ' .. id)
    if r.value == value then return value end
    r.value = value
    if value == r.spec.default then saved[id] = nil else saved[id] = value end
    for _, fn in ipairs(callbacks[id] or {}) do fn(value) end
    return value
end
function chef.on_change(id, fn)
    callbacks[id] = callbacks[id] or {}
    table.insert(callbacks[id], fn)
    return true
end
return {chef=chef, rows=rows, saved=saved, reads=function() return reads end}
'''


class SettingsTests(unittest.TestCase):
    def make(self, saved=None, headings=True):
        lua = LuaRuntime(unpack_returned_tuples=True)
        backend = lua.execute(BACKEND, lua.table_from(saved or {}))
        if not headings:
            backend.chef.has = None
        targets = lua.execute(Path(build.TARGETS).read_text(encoding='utf-8'))
        ranges = lua.table_from(dict(samples=50, supplies=25, mission=50, objectives=50,
                                     hellbombs=100, vehicles=100, deaths=500))
        show = lua.table()
        look = lua.table_from(dict(fade_samples=False, fade=True, distance=True, hide_near=True, smallest=.7, opacity=1))
        factory = lua.execute((Path(build.HERE) / 'src/settings.lua').read_text(encoding='utf-8'))
        settings = factory(backend.chef, lambda _: None, ranges, show, look, targets)
        self.assertTrue(settings.install())
        return lua, backend, targets, settings, ranges, show, look

    def target(self, targets, group, icon=None, name=None):
        return next(t for t in targets.values() if t.group == group and
                    (icon is None or t.icon == icon) and (name is None or name in (t.name or '')))

    def test_all_drawn_resources_have_config_and_helpers_have_none(self):
        _, backend, targets, settings, *_ = self.make()
        for t in targets.values():
            config = settings.target_config(t)
            if t.group in ('arms', 'wrecks', 'loaders'):
                self.assertIsNone(config)
            else:
                self.assertIsNotNone(config, t.name or t.hex)
                self.assertGreater(config.range, 0)
        specs = [r.spec for r in backend.rows.values()]
        self.assertGreater(len(specs), 100)
        self.assertEqual(len([s.heading for s in specs if s.heading and not s.sub]), 7)
        self.assertEqual(sum(s.heading == 'Objective interactions' and s.sub is True for s in specs), 1)
        self.assertTrue(all(s.fold is None for s in specs))  # Chef folds large entries by default.

    def test_independent_sample_distances_and_master_preserve_choices(self):
        _, b, targets, s, *_ = self.make()
        common = s.target_config(self.target(targets, 'samples', 'common'))
        rare = s.target_config(self.target(targets, 'samples', 'rare'))
        b.chef.set('epir.samples.common.distance', 120)
        b.chef.set('epir.samples.rare.show', False)
        self.assertEqual(common.range, 120)
        self.assertEqual(rare.range, 0)
        b.chef.set('epir.show_samples', False)
        self.assertEqual(common.range, 0)
        b.chef.set('epir.show_samples', True)
        self.assertEqual(common.range, 120)
        self.assertEqual(rare.range, 0)

    def test_zero_range_and_disabled_type_are_not_overridden_by_group(self):
        _, b, targets, s, *_ = self.make()
        target = self.target(targets, 'supplies', 'ammo')
        b.chef.set('epir.supplies.ammo.distance', 0)
        self.assertEqual(s.target_config(target).range, 0)
        self.assertEqual(s.target_config(self.target(targets, 'supplies', 'stim')).range, 25)

    def test_bulk_distance_updates_only_its_group_without_enabling_types(self):
        _, b, targets, s, *_ = self.make()
        b.chef.set('epir.samples.rare.show', False)
        b.chef.set('epir.range_samples', 140)
        self.assertEqual(s.target_config(self.target(targets, 'samples', 'common')).range, 140)
        rare = s.target_config(self.target(targets, 'samples', 'rare'))
        self.assertEqual(rare.distance, 140)
        self.assertEqual(rare.range, 0)
        self.assertEqual(s.target_config(self.target(targets, 'supplies', 'ammo')).range, 25)

    def test_saved_bulk_value_does_not_overwrite_saved_or_default_child_distances(self):
        _, b, targets, s, *_ = self.make({'epir.range_samples': 140,
                                        'epir.samples.rare.distance': 105,
                                        'epir.samples.super.show': False})
        self.assertEqual(s.target_config(self.target(targets, 'samples', 'common')).range, 50)
        self.assertEqual(s.target_config(self.target(targets, 'samples', 'rare')).range, 105)
        self.assertEqual(s.target_config(self.target(targets, 'samples', 'super')).range, 0)
        self.assertEqual(b.reads(), 0)

    def test_mission_and_map_hellbomb_settings_are_independent(self):
        _, b, targets, s, _, _, look = self.make()
        mission = self.target(targets, 'hellbombs', name='/hellbomb/hellbomb')
        damaged = self.target(targets, 'hellbombs', name='hellbomb_defunct')
        b.chef.set('epir.hellbombs.mission_bomb.distance', 200)
        b.chef.set('epir.hellbombs.damaged_bomb.show', False)
        b.chef.set('epir.hellbomb_warning', False)
        self.assertEqual(s.target_config(mission).range, 200)
        self.assertEqual(s.target_config(damaged).range, 0)
        self.assertFalse(look.hellbomb_warning)

    def test_each_shell_type_and_vehicle_variant_has_its_own_settings(self):
        _, b, targets, s, *_ = self.make()
        for name in ('regular', 'high_yield', 'napalm', 'smoke', 'static_field', 'mini_nuke'):
            t = self.target(targets, 'carry', name='seaf_shell_' + name)
            self.assertEqual(s.target_config(t).id, name)
        b.chef.set('epir.vehicles.frv.distance', 250)
        self.assertEqual(s.target_config(self.target(targets, 'vehicles', name='/frv/frv')).range, 250)
        self.assertEqual(s.target_config(self.target(targets, 'vehicles', name='frv_supply')).range, 100)

    def test_flat_native_fallback_keeps_every_setting_without_headings(self):
        _, b, *_ = self.make(headings=False)
        self.assertTrue(all(r.spec.heading is None for r in b.rows.values()))
        self.assertGreater(len(list(b.rows.values())), 100)

    def test_master_off_and_appearance_values_restore_without_resetting_children(self):
        _, b, targets, s, ranges, show, look = self.make({'epir.show_samples': False,
            'epir.samples.common.distance': 110, 'epir.opacity': 55, 'epir.smallest_size': 40,
            'epir.fade_samples': True, 'epir.range_deaths': 900})
        self.assertFalse(show.samples)
        self.assertEqual(ranges.deaths, 900)
        self.assertEqual(look.opacity, .55)
        self.assertEqual(look.smallest, .4)
        self.assertTrue(look.fade_samples)
        c = s.target_config(self.target(targets, 'samples', 'common'))
        self.assertEqual(c.range, 0)
        b.chef.set('epir.show_samples', True)
        self.assertEqual(c.range, 110)

    def test_bulk_then_individual_changes_survive_a_fresh_launch(self):
        _, b, *_ = self.make()
        b.chef.set('epir.range_samples', 140)
        b.chef.set('epir.samples.common.distance', 50)  # Default values need not be stored by Chef.
        b.chef.set('epir.samples.rare.distance', 95)
        b.chef.set('epir.samples.super.show', False)
        _, _, targets, s, *_ = self.make(dict(b.saved.items()))
        self.assertEqual(s.target_config(self.target(targets, 'samples', 'common')).range, 50)
        self.assertEqual(s.target_config(self.target(targets, 'samples', 'rare')).range, 95)
        self.assertEqual(s.target_config(self.target(targets, 'samples', 'super')).range, 0)

    def test_invalid_option_values_do_not_poison_cached_ranges_or_appearance(self):
        _, b, targets, s, _, _, look = self.make()
        b.chef.set('epir.samples.common.distance', float('nan'))
        b.chef.set('epir.opacity', float('inf'))
        self.assertEqual(s.target_config(self.target(targets, 'samples', 'common')).range, 50)
        self.assertEqual(look.opacity, 1)


class NativeMarkerTests(Case):
    def test_type_distance_and_toggle_change_actual_markers_without_backend_polling(self):
        backend = self.lua.execute(BACKEND)
        for name in ('option', 'get', 'set', 'on_change', 'has'):
            self.fake.chef[name] = backend.chef[name]
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(SAMPLE, [unit(70)])
        self.load()
        self.settle()
        self.assertEqual(self.dots(), 0)
        self.fake.chef.set('epir.samples.common.distance', 120)
        self.frames(1, start=40)
        self.assertEqual(self.dots(), 1)
        dot = self.lua.globals().ExtendedPickupIconsRange.dots[1]
        self.assertEqual(dot.range, 120)
        self.fake.chef.set('epir.samples.common.show', False)
        self.frames(1, start=41)
        self.assertEqual(self.dots(), 0)
        self.assertEqual(backend.reads(), 0)
        self.assertEqual(len(list(self.fake.options.values())), 0)  # No duplicate legacy settings page.

    def test_disabled_hellbomb_warning_keeps_marker_without_animation_reads(self):
        backend = self.lua.execute(BACKEND, self.lua.table_from({'epir.hellbomb_warning': False}))
        for name in ('option', 'get', 'set', 'on_change', 'has'):
            self.fake.chef[name] = backend.chef[name]
        self.BOMB = harness.HellbombWarningIntegrationTests.BOMB
        harness.HellbombWarningIntegrationTests.prepare(self)
        self.assertEqual(self.dots(), 1)
        self.assertIsNone(self.mod.dots[1].warning)
        self.assertEqual(self.fake.animation_reads, 0)


if __name__ == '__main__':
    unittest.main()
