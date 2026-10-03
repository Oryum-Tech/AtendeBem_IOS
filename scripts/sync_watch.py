#!/usr/bin/env python3
"""Read-only upstream change detection; acknowledging a change requires evidence."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
EXTENSIONS = {'.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.json', '.prisma',
              '.sql', '.graphql', '.gql', '.yml', '.yaml', '.css', '.scss',
              '.html', '.svg', '.md', '.sh', '.swift'}
IGNORED_PARTS = {'.git', 'node_modules', '.next', 'dist', 'build', 'coverage',
                 'secrets', 'credentials', 'fixtures', '__fixtures__', 'recordings'}


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def file_hash(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix='.' + path.name, delete=False) as target:
            temporary = Path(target.name)
            json.dump(data, target, ensure_ascii=False, indent=2, sort_keys=True)
            target.write('\n')
            target.flush()
            os.fsync(target.fileno())
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def git(root, *args):
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GIT_OPTIONAL_LOCKS='0')
    # No source scripts, hooks, diffs, fetches or checkouts are executed.
    result = subprocess.run(['git', '-C', str(root), *args], env=env,
                            capture_output=True, timeout=25, check=False)
    if result.returncode:
        raise ValueError('Git operation unavailable')  # Do not expose credentials in stderr.
    return result.stdout.decode('utf-8', errors='strict').strip()


def watched(relative):
    path = Path(relative)
    return (not path.is_absolute() and '..' not in path.parts
            and not IGNORED_PARTS.intersection(path.parts)
            and not path.name.startswith('.env')
            and (path.suffix.lower() in EXTENSIONS or path.name == 'Dockerfile'))


def local_files(root):
    files = {}
    names = git(root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard')
    for relative in sorted(set(names.split('\0')) - {''}):
        if not watched(relative):
            continue
        path = root / relative
        # Never follow links into other projects, credentials, or personal files.
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('Source contains a watched symlink')
        if not path.exists():  # Tracked deletion must disappear from the snapshot.
            continue
        if not path.is_file() or path.stat().st_size > 64 * 1024 * 1024:
            raise ValueError('Source file cannot be inspected safely')
        files[relative] = file_hash(path)
    return files


def inspect_source(source, source_root, remote):
    name = source['name']
    root = source_root / name
    state = {'native_areas': source['native_areas']}
    errors = []
    try:
        if Path(git(root, 'rev-parse', '--show-toplevel')).resolve() != root.resolve():
            raise ValueError('Not an independent source repository')
        start_head = git(root, 'rev-parse', 'HEAD')
        state.update(head=start_head, branch=git(root, 'rev-parse', '--abbrev-ref', 'HEAD'),
                     files=local_files(root))
        if git(root, 'rev-parse', 'HEAD') != start_head:
            raise ValueError('Source changed during snapshot')
    except (OSError, ValueError, subprocess.SubprocessError):
        errors.append({'source': name, 'code': 'LOCAL_SOURCE_UNAVAILABLE_OR_UNSTABLE'})
    if remote:
        try:
            output = git(source_root, 'ls-remote', '--exit-code', '--refs', source['remote'], source['ref'])
            matches = [line.split() for line in output.splitlines()]
            sha = next(parts[0] for parts in matches if len(parts) == 2 and parts[1] == source['ref'])
            if not re.fullmatch(r'[0-9a-f]{40,64}', sha):
                raise ValueError('Invalid remote revision')
            state['remote_head'] = sha
        except (OSError, ValueError, StopIteration, subprocess.SubprocessError):
            errors.append({'source': name, 'code': 'REMOTE_UNAVAILABLE'})
    return name, state, errors


def load_config(path):
    config = read_json(path)
    names = set()
    if config.get('schema') != 1 or not config.get('sources'):
        raise ValueError('Invalid source manifest')
    for source in config['sources']:
        name = source['name']
        if not re.fullmatch(r'atendebem-[a-z0-9-]+', name) or name in names:
            raise ValueError('Invalid or duplicated source name')
        names.add(name)
        if source['remote'] != f'https://github.com/Oryum-Tech/{name}.git':
            raise ValueError('Remote must match the reviewed source allowlist')
        if not re.fullmatch(r'refs/heads/[A-Za-z0-9._/-]+', source['ref']):
            raise ValueError('Invalid source branch')
        if not source.get('native_areas'):
            raise ValueError('Missing native impact mapping')
    return config


def snapshot(config, source_root, remote=False):
    sources, errors = {}, []
    with ThreadPoolExecutor(max_workers=4) as pool:
        tasks = [pool.submit(inspect_source, source, source_root, remote) for source in config['sources']]
        for task in tasks:
            name, state, failures = task.result()
            sources[name] = state
            errors.extend(failures)
    return {'schema': 1, 'manifest': fingerprint(config), 'remote_checked': remote,
            'sources': sources, 'errors': errors}


def changes_between(before, after):
    changes = []
    for name in sorted(before['sources'].keys() | after['sources'].keys()):
        old, new = before['sources'].get(name, {}), after['sources'].get(name, {})
        a, b = old.get('files', {}), new.get('files', {})
        files = [{'path': path, 'kind': 'added' if path not in a else 'deleted' if path not in b else 'modified'}
                 for path in sorted(a.keys() | b.keys()) if a.get(path) != b.get(path)]
        reasons = []
        if old.get('head') != new.get('head'):
            reasons.append('local_commit_changed')
        if old.get('branch') != new.get('branch'):
            reasons.append('local_branch_changed')
        if after['remote_checked'] and new.get('remote_head'):
            if new['remote_head'] != (old.get('remote_head') or old.get('head')):
                reasons.append('remote_commit_changed')
        if files or reasons or not old or not new:
            changes.append({'source': name, 'reasons': reasons, 'files': files,
                            'native_areas': new.get('native_areas', old.get('native_areas', [])),
                            'local_head': new.get('head'), 'remote_head': new.get('remote_head')})
    if before['manifest'] != after['manifest']:
        changes.append({'source': 'manifest', 'reasons': ['source_manifest_changed'], 'files': [], 'native_areas': ['Revisão da cobertura']})
    return changes


def make_report(baseline, current):
    changes = changes_between(baseline, current)
    status = 'blocked' if current['errors'] else 'changes_detected' if changes else 'unchanged'
    return {'schema': 1, 'checked_at': datetime.now(timezone.utc).isoformat(),
            'report_id': fingerprint({'baseline': baseline, 'current': current}),
            'status': status, 'parity_verified': False,
            'remote_checked': current['remote_checked'], 'changes': changes,
            'errors': current['errors'],
            'note': 'Ausência de mudanças não comprova paridade, sincronismo clínico ou versão implantada.'}


def evidence_path(project, relative):
    path = project / relative
    if (Path(relative).is_absolute() or path.is_symlink()
            or not path.resolve().is_relative_to(project.resolve())
            or not path.is_file() or path.stat().st_size == 0):
        raise ValueError('Evidence must be a nonempty file inside the iOS project')
    return path


def validate_review(review, report, current, project):
    if report['status'] != 'changes_detected' or report['errors']:
        raise ValueError('Only a complete change report can be acknowledged')
    if review.get('report_id') != report['report_id']:
        raise ValueError('Stale review: upstream changed; inspect the new report')
    if review.get('disposition') not in {'native_updated', 'no_native_impact'}:
        raise ValueError('Specify native_updated or no_native_impact')
    if len(review.get('rationale', '').strip()) < 20:
        raise ValueError('A concrete impact explanation is required')
    required = {'analysis'}
    if review['disposition'] == 'native_updated':
        required |= {'core_tests', 'ios_build', 'ui_or_contract_checks'}
    evidence = review.get('evidence', {})
    if not required.issubset(evidence):
        raise ValueError('Missing required validation evidence')
    if not current['remote_checked']:
        raise ValueError('Acknowledgment requires a fresh remote check')
    heads = {name: state['remote_head'] for name, state in current['sources'].items()}
    if review.get('remote_heads') != heads:
        raise ValueError('Review must explicitly cover every observed remote revision')
    return {key: {'path': relative, 'sha256': file_hash(evidence_path(project, relative))}
            for key, relative in evidence.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['initialize', 'check', 'accept'])
    parser.add_argument('--config', type=Path, default=PROJECT / 'sync/sources.json')
    parser.add_argument('--source-root', type=Path)
    parser.add_argument('--remote', action='store_true')
    parser.add_argument('--review', type=Path)
    args = parser.parse_args()
    try:
        config = load_config(args.config)
        source_root = (args.source_root or Path(os.environ.get('ATENDEBEM_SOURCE_ROOT', str(PROJECT / config['source_root'])))).resolve()
        baseline_path = PROJECT / 'sync/baseline.json'
        if args.command == 'initialize' and baseline_path.exists():
            raise ValueError('Baseline already exists; initialization cannot erase pending changes')
        current = snapshot(config, source_root, args.remote or args.command == 'accept')
        if args.command == 'initialize':
            if current['errors']:
                raise ValueError('Cannot initialize: one or more sources are unavailable')
            atomic_json(baseline_path, current)
            print('Ponto inicial registrado. Isso não declara paridade nem validação de funcionalidades.')
            return 0
        baseline = read_json(baseline_path)
        report = make_report(baseline, current)
        atomic_json(PROJECT / 'sync/state/latest-snapshot.json', current)
        atomic_json(PROJECT / 'sync/state/latest-report.json', report)
        if args.command == 'accept':
            if args.review is None:
                raise ValueError('--review is required')
            review = read_json(args.review)
            evidence = validate_review(review, report, current, PROJECT)
            receipt = {'report': report, 'review': review, 'evidence': evidence}
            atomic_json(PROJECT / 'sync/reviews' / (report['report_id'] + '.json'), receipt)
            atomic_json(baseline_path, current)
            print('Revisão registrada com evidências; ponto de comparação atualizado.')
            return 0
        summary = {key: report[key] for key in ('status', 'report_id', 'remote_checked', 'errors')}
        summary['changed_sources'] = len(report['changes'])
        summary['changed_files'] = sum(len(item['files']) for item in report['changes'])
        summary['report'] = 'sync/state/latest-report.json'
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return {'unchanged': 0, 'changes_detected': 1, 'blocked': 2}[report['status']]
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        # An unavailable source, corrupt state or disk failure must never become "unchanged".
        detail = str(error) if isinstance(error, ValueError) else type(error).__name__
        print(f'Verificação não concluída: {detail}. Conferir fontes, configuração, evidências e espaço em disco.', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
