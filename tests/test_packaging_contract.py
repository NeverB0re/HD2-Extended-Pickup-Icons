"""Manifest/path checks independent of matching the builder's own constants."""
import json
from pathlib import Path
import unittest
import zipfile

import build
from tools.verify_release import validate_manager_manifest


class ManagerManifestTests(unittest.TestCase):
    def setUp(self):
        with zipfile.ZipFile(Path(build.HERE) / 'release/Extended Pickup Icons Range v2.6.1.zip') as z:
            self.manifest = json.loads(z.read('manifest.json'))
            self.files = z.namelist()

    def test_published_package_matches_arsenal_v1_contract_without_directory_entries(self):
        validate_manager_manifest(self.manifest, self.files)
        self.assertFalse(any(name.endswith('/') for name in self.files))

    def test_missing_or_wrong_case_include_folder_is_rejected(self):
        for include in ('Missing', 'addon'):
            with self.subTest(include=include):
                self.manifest['Options'][0]['Include'] = [include]
                with self.assertRaisesRegex(AssertionError, 'Include folder missing'):
                    validate_manager_manifest(self.manifest, self.files)

    def test_missing_icon_is_rejected(self):
        self.manifest['IconPath'] = 'absent.png'
        with self.assertRaisesRegex(AssertionError, 'Missing manager image'):
            validate_manager_manifest(self.manifest, self.files)

    def test_manifest_uuid_and_relative_paths_are_validated(self):
        self.manifest['Guid'] = 'not-a-uuid'
        with self.assertRaises(ValueError):
            validate_manager_manifest(self.manifest, self.files)
        self.manifest['Guid'] = build.MANIFEST['Guid']
        for include in ('../Addon', 'C:/Addon', '/Addon', 'Addon\\child'):
            with self.subTest(include=include):
                self.manifest['Options'][0]['Include'] = [include]
                with self.assertRaises(AssertionError):
                    validate_manager_manifest(self.manifest, self.files)
