"""Run the published Boot 0.13.4 classifier on our actual inlined addon."""
from pathlib import Path
import sys

from test_extended_pickup_icons_range import Case, AVATAR, SAMPLE, unit
from test_settings import BACKEND
import build

sys.path.insert(0, str(Path(build.HERE) / 'tools'))
from count_calls import source_from_zip


class LoaderContractTests(Case):
    def route(self, source):
        fixture = Path(__file__).parent / 'fixtures/boot_0_13_4_classifier.lua'
        classifier = self.lua.execute(fixture.read_text(encoding='utf-8-sig'))
        return classifier(source)

    def test_public_261_reproduces_boot_claim_and_failed_chef_helper_start(self):
        public = source_from_zip(Path(build.HERE) / 'release/Extended Pickup Icons Range v2.6.1.zip')
        self.assertFalse(self.route(public))
        self.mod = self.lua.execute(public, build.RESOURCE)  # Boot/require supplies the resource name.
        self.assertEqual(self.mod.status, 'no Chef Shared Loader')
        self.assertEqual(len(list(self.fake.options.values())), 0)

    def test_current_source_is_explicitly_delegated_before_boot_can_start_it(self):
        declaration = '-- HD2-Requires: chef-shared-loader >= 1.4.0'
        self.assertIn(declaration, self.source[:1200])
        self.assertTrue(self.route(self.source))

    def test_delegated_start_has_native_settings_and_keeps_saved_distances(self):
        self.assertTrue(self.route(self.source))
        backend = self.lua.execute(BACKEND, self.lua.table_from({'epir.samples.common.distance': 120}))
        for name in ('option', 'get', 'set', 'on_change', 'has'):
            self.fake.chef[name] = backend.chef[name]
        self.set_units(AVATAR, [unit(0)], loaded=False)
        self.set_units(SAMPLE, [unit(70)])
        self.load()  # Chef supplies its own helper table after the handoff.
        self.settle()
        self.assertGreater(len(list(backend.rows.values())), 100)
        self.assertEqual(len(list(self.fake.options.values())), 0)
        self.assertEqual(self.dots(), 1)
        self.assertEqual(self.mod.dots[1].range, 120)
