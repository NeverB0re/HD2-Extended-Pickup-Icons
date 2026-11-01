import unittest
from pathlib import Path
import lupa.lua51 as lua51

RESOURCE = 'content/fac_helldivers/hellpod/hellbomb/hellbomb'
BUILD = 'stingray:46805437a3d445f9df7662b60086ac8ae3c65b5c95da6'


class WarningTests(unittest.TestCase):
    def setUp(self):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.fake = self.lua.execute('''
            local f={build=...,reads=0,machines=0,top=1,base=2,bridge=1,machine=true,alive=true,logs={}}
            f.chef={unit_alive=function() return f.alive end,call_kind=function(name,kind,u)
                if name=='Application.build_identifier' then return f.build end
                if name=='Unit.has_animation_state_machine' then f.machines=f.machines+1; if f.die_at_machine then f.alive=false end; return f.machine end
                if name=='Unit.animation_get_state' then f.reads=f.reads+1; if f.die_at_state then f.alive=false end; if f.refused then return nil,'refused' end; return f.base,f.top,f.bridge end
            end}
            f.log=function(s) f.logs[#f.logs+1]=s end
            return f
        ''', BUILD)
        factory = self.lua.execute((Path(__file__).parents[1] / 'src/hellbomb_warning.lua').read_text())
        self.factory = factory
        self.warning = factory(self.fake.chef, self.fake.log)
        self.point = self.lua.table_from({'kind': RESOURCE, 'unit': self.lua.table()})

    def observe(self, now, visible=True):
        return self.warning.observe(self.point, now, visible)

    def activate(self):
        self.assertIsNone(self.observe(0))
        self.fake.top = 0
        return self.observe(0.21)

    def test_observed_transition_starts_ten_second_estimate(self):
        record = self.activate()
        self.assertAlmostEqual(record.deadline, 10.21)
        self.assertEqual(self.warning.visual(record, 0.21).label, '~10s')
        self.assertEqual(self.warning.visual(record, 5.22).label, '~5s')
        self.assertEqual(self.warning.visual(record, 10.22).label, '!')

    def test_already_activated_bomb_never_restarts_a_full_timer(self):
        self.fake.top = 0
        record = self.observe(0)
        self.assertTrue(record.unknown)
        self.assertEqual(self.warning.visual(record, 3).label, 'ARMED')

    def test_long_gap_is_unknown_instead_of_fresh_activation(self):
        self.observe(0)
        self.fake.top = 0
        self.assertTrue(self.observe(2).unknown)

    def test_missing_state_is_not_state_zero(self):
        self.observe(0)
        self.fake.refused = True
        self.assertIsNone(self.observe(0.21))
        self.fake.refused, self.fake.top = False, 0
        self.assertTrue(self.observe(1.3).unknown)

    def test_no_machine_means_no_state_read(self):
        self.fake.machine = False
        self.assertIsNone(self.observe(0))
        self.assertEqual(self.fake.reads, 0)

    def test_death_between_precondition_and_state_read_is_guarded(self):
        self.fake.die_at_machine = True
        self.assertIsNone(self.observe(0))
        self.assertEqual(self.fake.reads, 0)

    def test_death_during_state_read_discards_the_result(self):
        self.fake.die_at_state, self.fake.top = True, 0
        self.assertIsNone(self.observe(0))

    def test_hidden_models_and_other_resources_never_get_animation_queries(self):
        self.assertIsNone(self.observe(0, False))
        self.point.kind = 'content/fac_helldivers/hellpod/hellbomb_defunct/hellbomb_defunct'
        self.assertIsNone(self.observe(1))
        self.assertEqual(self.fake.machines, 0)

    def test_polling_is_bounded_and_stops_after_activation(self):
        for i in range(60):
            self.observe(i / 60)
        self.assertLessEqual(self.fake.reads, 5)
        self.fake.top = 0
        record = self.observe(1.1)
        before = self.fake.reads
        self.observe(30)
        self.assertEqual(self.fake.reads, before)
        self.assertIsNotNone(record)

    def test_reset_and_new_unit_do_not_inherit_activation(self):
        self.activate()
        self.warning.reset()
        self.fake.top = 1
        self.assertIsNone(self.observe(1))
        self.fake.top = 0
        self.point.unit = self.lua.table()
        self.assertTrue(self.observe(1.21).unknown)

    def test_unknown_build_is_not_queried(self):
        self.fake.build = 'new game build'
        self.warning = self.factory(self.fake.chef, self.fake.log)
        self.assertIsNone(self.observe(0))
        self.assertEqual(self.fake.machines, 0)

    def test_color_moves_toward_red_and_icon_pulses_without_disappearing(self):
        record = self.activate()
        early = self.warning.visual(record, 0.21)
        late = self.warning.visual(record, 9.21)
        self.assertGreater(early.rgb[2], late.rgb[2])
        styles = [self.warning.visual(record, 0.21 + i / 60) for i in range(600)]
        self.assertGreater(max(s.scale for s in styles) - min(s.scale for s in styles), 0.1)
        self.assertTrue(all(0.39 <= s.alpha <= 1 for s in styles))


if __name__ == '__main__':
    unittest.main()
