"""Regressions for missed upstream changes and false acknowledgments."""

import contextlib
import copy
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import sync_watch as watch


class SyncWatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'atendebem-test'
        self.repo.mkdir()
        self.run_git('init', '-b', 'main')
        (self.repo / 'contract.ts').write_text('type Patient = {id: string};')
        self.run_git('add', 'contract.ts')
        self.run_git('-c', 'user.email=test@example.invalid', '-c', 'user.name=Test', 'commit', '-m', 'fixture')
        self.config = {'schema': 1, 'source_root': '.', 'sources': [
            {'name': self.repo.name, 'remote': 'https://github.com/Oryum-Tech/atendebem-test.git',
             'ref': 'refs/heads/main', 'native_areas': ['Pacientes']}]}
        self.baseline = watch.snapshot(self.config, self.root)
        self.assertEqual(self.baseline['errors'], [])

    def run_git(self, *args):
        return subprocess.run(['git', '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
                               '-C', str(self.repo), *args], capture_output=True, text=True, check=True).stdout

    def test_configuration_rejects_unreviewed_remote_and_duplicate_sources(self):
        config_file = self.root / 'sources.json'
        bad = copy.deepcopy(self.config)
        bad['sources'][0]['remote'] = 'https://example.invalid/other.git'
        config_file.write_text(json.dumps(bad))
        with self.assertRaises(ValueError):
            watch.load_config(config_file)
        bad = copy.deepcopy(self.config)
        bad['sources'].append(bad['sources'][0])
        config_file.write_text(json.dumps(bad))
        with self.assertRaises(ValueError):
            watch.load_config(config_file)

    def test_successful_remote_query_is_read_only_and_records_exact_ref(self):
        real_git = watch.git
        head = self.baseline['sources'][self.repo.name]['head']
        def upstream(root, *args):
            if args[0] == 'ls-remote':
                self.assertEqual(args[-1], 'refs/heads/main')
                return head + '\trefs/heads/main'
            return real_git(root, *args)
        before = self.run_git('status', '--porcelain')
        with patch.object(watch, 'git', side_effect=upstream):
            current = watch.snapshot(self.config, self.root, remote=True)
        self.assertEqual(current['errors'], [])
        self.assertEqual(current['sources'][self.repo.name]['remote_head'], head)
        self.assertEqual(watch.make_report(self.baseline, current)['status'], 'unchanged')
        self.assertEqual(before, self.run_git('status', '--porcelain'))

    def test_detects_local_modification_addition_and_deletion_without_writing_upstream(self):
        (self.repo / 'contract.ts').write_text('type Patient = {id: number};')
        (self.repo / 'new.ts').write_text('export const feature = true;')
        before = self.run_git('status', '--porcelain')
        current = watch.snapshot(self.config, self.root)
        report = watch.make_report(self.baseline, current)
        self.assertEqual(report['status'], 'changes_detected')
        self.assertEqual({x['kind'] for x in report['changes'][0]['files']}, {'added', 'modified'})
        self.assertEqual(before, self.run_git('status', '--porcelain'))
        (self.repo / 'contract.ts').unlink()
        changes = watch.changes_between(self.baseline, watch.snapshot(self.config, self.root))
        self.assertIn({'path': 'contract.ts', 'kind': 'deleted'}, changes[0]['files'])

    def test_secrets_and_ignored_build_outputs_are_not_read(self):
        (self.repo / '.env').write_text('NEVER_COPY_THIS=private')
        (self.repo / '.gitignore').write_text('dist/\n')
        (self.repo / 'dist').mkdir()
        (self.repo / 'dist/generated.ts').write_text('generated')
        files = watch.local_files(self.repo)
        self.assertEqual(set(files), {'contract.ts'})
        self.assertNotIn('NEVER_COPY_THIS', json.dumps(files))

    def test_watched_symlink_is_a_blocker_instead_of_reading_external_content(self):
        secret = self.root / 'outside.json'
        secret.write_text('private data')
        (self.repo / 'linked.json').symlink_to(secret)
        current = watch.snapshot(self.config, self.root)
        self.assertEqual(watch.make_report(self.baseline, current)['status'], 'blocked')

    def test_remote_only_change_is_detected_without_changing_checkout(self):
        current = copy.deepcopy(self.baseline)
        current['remote_checked'] = True
        current['sources'][self.repo.name]['remote_head'] = 'a' * 40
        report = watch.make_report(self.baseline, current)
        self.assertEqual(report['status'], 'changes_detected')
        self.assertIn('remote_commit_changed', report['changes'][0]['reasons'])
        self.assertEqual(report['changes'][0]['files'], [])

    def test_network_failure_and_missing_repository_cannot_report_unchanged(self):
        real_git = watch.git
        def unavailable(root, *args):
            if args[0] == 'ls-remote':
                raise ValueError('network failure with sensitive stderr that must not leak')
            return real_git(root, *args)
        with patch.object(watch, 'git', side_effect=unavailable):
            current = watch.snapshot(self.config, self.root, remote=True)
        report = watch.make_report(self.baseline, current)
        self.assertEqual(report['status'], 'blocked')
        self.assertNotIn('sensitive', json.dumps(report))
        missing = watch.snapshot(self.config, self.root / 'missing')
        self.assertEqual(watch.make_report(self.baseline, missing)['status'], 'blocked')

    def test_unchanged_does_not_mean_native_parity_and_report_id_is_stable(self):
        a = watch.make_report(self.baseline, self.baseline)
        b = watch.make_report(self.baseline, self.baseline)
        self.assertEqual(a['status'], 'unchanged')
        self.assertFalse(a['parity_verified'])
        self.assertEqual(a['report_id'], b['report_id'])

    def review_fixture(self):
        current = copy.deepcopy(self.baseline)
        current['remote_checked'] = True
        current['sources'][self.repo.name]['remote_head'] = 'a' * 40
        report = watch.make_report(self.baseline, current)
        evidence = self.root / 'analysis.md'
        evidence.write_text('Observed source diff and corresponding native behavior.')
        review = {'report_id': report['report_id'], 'disposition': 'no_native_impact',
                  'rationale': 'Only a web layout adjustment; the native task is unchanged.',
                  'remote_heads': {self.repo.name: 'a' * 40}, 'evidence': {'analysis': 'analysis.md'}}
        return current, report, review

    def test_stale_review_and_missing_native_validation_are_refused(self):
        current, report, review = self.review_fixture()
        self.assertIn('analysis', watch.validate_review(review, report, current, self.root))
        stale = dict(review, report_id='stale')
        with self.assertRaises(ValueError):
            watch.validate_review(stale, report, current, self.root)
        review['disposition'] = 'native_updated'
        with self.assertRaises(ValueError):
            watch.validate_review(review, report, current, self.root)

    def test_review_requires_remote_heads_and_cannot_use_external_evidence(self):
        current, report, review = self.review_fixture()
        review['remote_heads'] = {}
        with self.assertRaises(ValueError):
            watch.validate_review(review, report, current, self.root)
        for relative in ('../elsewhere.md', str(self.root / 'analysis.md')):
            with self.assertRaises(ValueError):
                watch.evidence_path(self.root, relative)

    def test_disk_failure_preserves_previous_baseline(self):
        target = self.root / 'baseline.json'
        watch.atomic_json(target, self.baseline)
        with patch.object(Path, 'replace', side_effect=OSError('disk full')):
            with self.assertRaises(OSError):
                watch.atomic_json(target, {'unreviewed': True})
        self.assertEqual(watch.read_json(target), self.baseline)

    def test_initialize_cannot_overwrite_existing_baseline(self):
        config = self.root / 'sources.json'
        config.write_text(json.dumps(self.config))
        path = self.root / 'sync/baseline.json'
        watch.atomic_json(path, self.baseline)
        with patch.object(watch, 'PROJECT', self.root), patch('sys.argv', ['sync_watch.py', 'initialize', '--config', str(config)]), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(watch.main(), 2)
        self.assertEqual(watch.read_json(path), self.baseline)

    def test_accept_records_evidence_and_advances_only_the_reviewed_snapshot(self):
        current, report, review = self.review_fixture()
        config = self.root / 'sources.json'
        config.write_text(json.dumps(self.config))
        baseline_path = self.root / 'sync/baseline.json'
        watch.atomic_json(baseline_path, self.baseline)
        review_path = self.root / 'review.json'
        review_path.write_text(json.dumps(review))
        with patch.object(watch, 'PROJECT', self.root), patch.object(watch, 'snapshot', return_value=current), patch('sys.argv', ['sync_watch.py', 'accept', '--config', str(config), '--review', str(review_path)]), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(watch.main(), 0)
        self.assertEqual(watch.read_json(baseline_path), current)
        receipt = watch.read_json(self.root / 'sync/reviews' / (report['report_id'] + '.json'))
        self.assertEqual(receipt['evidence']['analysis']['sha256'], watch.file_hash(self.root / 'analysis.md'))


if __name__ == '__main__':
    unittest.main()
