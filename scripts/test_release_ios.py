import plistlib
import json
from datetime import datetime, timedelta
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import release_ios as release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = release.configuration()

    def test_archive_and_app_versions_must_match(self):
        info = release.identity(self.config)
        info['CFBundleVersion'] = '9999'
        with self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
            release.check_identity(info, self.config)

    def test_release_rejects_bundle_without_matching_store_record(self):
        record = self.root / 'app-store-connect.json'
        record.write_text(json.dumps({'bundle_id': 'io.atendebem.profissionais'}))
        with self.assertRaisesRegex(ValueError, 'cadastro verificado'):
            release.check_store_identity(self.config, record)
        record.write_text(json.dumps({'bundle_id': self.config['PRODUCT_BUNDLE_IDENTIFIER']}))
        release.check_store_identity(self.config, record)

    def test_bundle_display_name_is_checked(self):
        info = release.identity(self.config)
        info['CFBundleDisplayName'] = 'Nome antigo'
        with self.assertRaisesRegex(ValueError, 'CFBundleDisplayName'):
            release.check_identity(info, self.config)

    def test_ipa_rejects_wrong_identity(self):
        path = self.root / 'wrong.ipa'
        info = release.identity(self.config)
        info['CFBundleIdentifier'] = 'com.other.app'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Payload/AtendeBem.app/Info.plist', plistlib.dumps(info))
            archive.writestr('Payload/AtendeBem.app/embedded.mobileprovision', b'fixture')
        with self.assertRaisesRegex(ValueError, 'CFBundleIdentifier'):
            release.ipa_info(path, self.config)

    def test_ipa_rejects_unsigned_payload(self):
        path = self.root / 'unsigned.ipa'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Payload/AtendeBem.app/Info.plist', plistlib.dumps(release.identity(self.config)))
        with self.assertRaisesRegex(ValueError, 'perfil'):
            release.ipa_info(path, self.config)

    def test_ipa_rejects_path_traversal_before_extraction(self):
        path = self.root / 'unsafe.ipa'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('../outside', b'fixture')
        with self.assertRaisesRegex(ValueError, 'caminho'):
            release.ipa_info(path, self.config)

    def test_build_scan_ignores_other_apps(self):
        for name, bundle, build in [('a', self.config['PRODUCT_BUNDLE_IDENTIFIER'], '43'), ('b', 'com.other.app', '999')]:
            path = self.root / f'{name}.xcarchive'
            path.mkdir()
            (path / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {'CFBundleIdentifier': bundle, 'CFBundleVersion': build}}))
        self.assertEqual(release.existing_builds(self.config['PRODUCT_BUNDLE_IDENTIFIER'], [self.root]), [43])

    def test_prepare_increments_past_archives_and_preserves_bundle(self):
        config_path = self.root / 'App.xcconfig'
        config_path.write_text(release.CONFIG.read_text())
        with patch.object(release, 'CONFIG', config_path), patch.object(release, 'configuration', side_effect=lambda: release_configuration(config_path)), patch.object(release, 'existing_builds', return_value=[89]):
            result = release.prepare('1.2.3')
        self.assertEqual(result['CURRENT_PROJECT_VERSION'], '90')
        self.assertEqual(result['MARKETING_VERSION'], '1.2.3')
        self.assertEqual(result['PRODUCT_BUNDLE_IDENTIFIER'], self.config['PRODUCT_BUNDLE_IDENTIFIER'])

    def test_prepare_increments_past_build_observed_in_testflight(self):
        config_path = self.root / 'App.xcconfig'
        config_path.write_text(release.CONFIG.read_text())
        record = {'bundle_id': self.config['PRODUCT_BUNDLE_IDENTIFIER'], 'last_observed_build': 188}
        with patch.object(release, 'CONFIG', config_path), patch.object(release, 'configuration', side_effect=lambda: release_configuration(config_path)), patch.object(release, 'existing_builds', return_value=[]), patch.object(release, 'check_store_identity', return_value=record):
            result = release.prepare('1.3.0')
        self.assertEqual(result['CURRENT_PROJECT_VERSION'], '189')
        self.assertEqual(result['MARKETING_VERSION'], '1.3.0')

    def test_low_disk_stops_before_running_build(self):
        with patch.object(release.shutil, 'disk_usage') as usage, patch.object(release, 'run') as run:
            usage.return_value.free = 1024**3
            with self.assertRaisesRegex(ValueError, 'GiB'):
                release.archive(self.config)
            run.assert_not_called()

    def test_upload_is_never_implicit(self):
        with patch.object(release, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'não autorizado'):
                release.deliver(self.root / 'app.ipa', self.config, False)
            run.assert_not_called()

    def test_existing_archive_is_never_overwritten(self):
        directory = self.root / f"AtendeBem-{self.config['MARKETING_VERSION']}-{self.config['CURRENT_PROJECT_VERSION']}"
        (directory / 'AtendeBem.xcarchive').mkdir(parents=True)
        with patch.object(release, 'OUTPUT', self.root), patch.object(release, 'require_space', return_value=10), patch.object(release, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'já existe'):
                release.archive(self.config)
            run.assert_not_called()

    def profile(self):
        return {'TeamIdentifier': [self.config['DEVELOPMENT_TEAM']],
                'ExpirationDate': datetime.now() + timedelta(days=30),
                'Entitlements': {'get-task-allow': False, 'application-identifier': self.config['DEVELOPMENT_TEAM'] + '.' + self.config['PRODUCT_BUNDLE_IDENTIFIER']}}

    def test_distribution_profile_accepts_store_and_rejects_development(self):
        profile = self.profile()
        release.check_distribution_profile(profile, self.config)
        profile['Entitlements']['get-task-allow'] = True
        with self.assertRaisesRegex(ValueError, 'App Store'):
            release.check_distribution_profile(profile, self.config)

    def test_distribution_profile_rejects_ad_hoc_and_enterprise(self):
        for field, value in [('ProvisionedDevices', ['test-device']), ('ProvisionsAllDevices', True)]:
            profile = self.profile()
            profile[field] = value
            with self.assertRaisesRegex(ValueError, 'App Store'):
                release.check_distribution_profile(profile, self.config)

    def test_distribution_profile_rejects_expired_or_other_team(self):
        profile = self.profile()
        profile['ExpirationDate'] = datetime.now() - timedelta(days=1)
        with self.assertRaisesRegex(ValueError, 'vencido'):
            release.check_distribution_profile(profile, self.config)
        profile = self.profile()
        profile['TeamIdentifier'] = ['OTHERTEAM00']
        with self.assertRaisesRegex(ValueError, 'Equipe'):
            release.check_distribution_profile(profile, self.config)


release_configuration = release.configuration

if __name__ == '__main__':
    unittest.main()
