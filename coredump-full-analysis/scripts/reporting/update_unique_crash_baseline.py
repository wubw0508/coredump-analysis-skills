#!/usr/bin/env python3
"""Update persistent unique-crash baseline from filtered package CSV."""
import argparse
import csv
import json
from datetime import datetime
from pathlib import Path

BASELINE_ROOT_DEFAULT = Path.home() / 'coredump-baseline'


def parse_args():
    parser = argparse.ArgumentParser(description='Update persistent unique crash baseline')
    parser.add_argument('--package', required=True)
    parser.add_argument('--filtered-csv', required=True)
    parser.add_argument('--workspace', required=True)
    parser.add_argument('--baseline-root', default=str(BASELINE_ROOT_DEFAULT))
    return parser.parse_args()


def read_csv_rows(path: Path):
    if not path.exists():
        return []
    with path.open('r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        return list(reader)


def write_csv_rows(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = []
    for row in rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)
    if 'UniqueKey' not in fieldnames:
        fieldnames.append('UniqueKey')
    with path.open('w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction='ignore')
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def load_json(path: Path, default):
    if not path.exists():
        return default
    with path.open('r', encoding='utf-8') as f:
        return json.load(f)


def write_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def normalize_row(row, package):
    normalized = dict(row)
    normalized['package'] = normalized.get('package') or package
    normalized['UniqueKey'] = (normalized.get('UniqueKey') or '').strip()
    normalized['Version'] = (normalized.get('Version') or '').strip()
    normalized['Sig'] = (normalized.get('Sig') or '').strip()
    normalized['Exe'] = (normalized.get('Exe') or '').strip()
    normalized['Count'] = str(normalized.get('Count') or '0')
    return normalized


def main():
    args = parse_args()
    now = datetime.now().isoformat(timespec='seconds')
    package = args.package
    workspace = Path(args.workspace)
    filtered_csv = Path(args.filtered_csv)
    baseline_root = Path(args.baseline_root).expanduser()
    current_dir = baseline_root / 'current'
    history_dir = baseline_root / 'history' / datetime.now().strftime('%Y%m%d-%H%M%S')
    reports_dir = baseline_root / 'reports'

    baseline_csv = current_dir / f'{package}_unique_crashes.csv'
    baseline_json = current_dir / f'{package}_unique_crashes.json'
    diff_json = workspace / '2.数据筛选' / f'{package}_crash_baseline_diff.json'
    new_csv = workspace / '2.数据筛选' / f'{package}_new_crashes.csv'
    report_md = reports_dir / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}_{package}_weekly_diff.md"

    current_rows = [normalize_row(row, package) for row in read_csv_rows(filtered_csv) if (row.get('UniqueKey') or '').strip()]
    current_map = {row['UniqueKey']: row for row in current_rows}

    previous_rows = [normalize_row(row, package) for row in read_csv_rows(baseline_csv) if (row.get('UniqueKey') or '').strip()]
    previous_map = {row['UniqueKey']: row for row in previous_rows}
    previous_meta = load_json(baseline_json, {
        'package': package,
        'generated_at': now,
        'source_workspace': '',
        'total_unique_crashes': 0,
        'unique_keys': [],
        'first_seen_map': {},
        'last_seen_map': {},
        'merged_from_runs': [],
    })

    current_keys = set(current_map)
    previous_keys = set(previous_map)
    new_keys = sorted(current_keys - previous_keys)
    known_keys = sorted(current_keys & previous_keys)
    baseline_only_keys = sorted(previous_keys - current_keys)

    first_seen_map = dict(previous_meta.get('first_seen_map', {}))
    last_seen_map = dict(previous_meta.get('last_seen_map', {}))
    for key in current_keys:
        first_seen_map.setdefault(key, now)
        last_seen_map[key] = now

    merged_rows = list(previous_map.values())
    for key in new_keys:
        merged_rows.append(current_map[key])
    merged_rows.sort(key=lambda row: ((row.get('Version') or ''), (row.get('Sig') or ''), (row.get('Exe') or ''), row['UniqueKey']))

    new_rows = [current_map[key] for key in new_keys]
    write_csv_rows(new_csv, new_rows)
    write_csv_rows(baseline_csv, merged_rows)
    write_csv_rows(history_dir / f'{package}_unique_crashes.csv', merged_rows)

    merged_meta = {
        'package': package,
        'generated_at': now,
        'source_workspace': str(workspace),
        'baseline_root': str(baseline_root),
        'total_unique_crashes': len(merged_rows),
        'current_unique_crashes': len(current_rows),
        'baseline_unique_before': len(previous_rows),
        'new_unique_crashes': len(new_keys),
        'known_unique_crashes': len(known_keys),
        'baseline_only_unique_crashes': len(baseline_only_keys),
        'unique_keys': [row['UniqueKey'] for row in merged_rows],
        'first_seen_map': first_seen_map,
        'last_seen_map': last_seen_map,
        'merged_from_runs': list(previous_meta.get('merged_from_runs', [])) + [str(workspace)],
    }
    write_json(baseline_json, merged_meta)
    write_json(history_dir / f'{package}_unique_crashes.json', merged_meta)

    diff_data = {
        'generated_at': now,
        'package': package,
        'workspace': str(workspace),
        'filtered_csv': str(filtered_csv),
        'baseline_root': str(baseline_root),
        'baseline_csv': str(baseline_csv),
        'current_unique_count': len(current_rows),
        'baseline_unique_count_before': len(previous_rows),
        'baseline_unique_count_after': len(merged_rows),
        'new_unique_count': len(new_keys),
        'known_unique_count': len(known_keys),
        'baseline_only_count': len(baseline_only_keys),
        'new_unique_keys': new_keys,
        'known_unique_keys': known_keys,
        'baseline_only_keys': baseline_only_keys,
        'new_crashes': new_rows,
    }
    write_json(diff_json, diff_data)

    report_lines = [
        f'# Weekly unique crash diff - {package}',
        '',
        f'generated_at: {now}',
        f'workspace: {workspace}',
        f'baseline_root: {baseline_root}',
        '',
        f'- current_unique_count: {len(current_rows)}',
        f'- baseline_unique_count_before: {len(previous_rows)}',
        f'- baseline_unique_count_after: {len(merged_rows)}',
        f'- new_unique_count: {len(new_keys)}',
        f'- known_unique_count: {len(known_keys)}',
        f'- baseline_only_count: {len(baseline_only_keys)}',
        '',
        '## New unique crashes',
        '',
    ]
    if new_rows:
        report_lines.append('| Version | Sig | Exe | Count | UniqueKey |')
        report_lines.append('|---------|-----|-----|-------|-----------|')
        for row in new_rows:
            report_lines.append(f"| {row.get('Version','')} | {row.get('Sig','')} | {row.get('Exe','')} | {row.get('Count','')} | {row.get('UniqueKey','')} |")
    else:
        report_lines.append('None')
    report_lines.append('')
    report_md.parent.mkdir(parents=True, exist_ok=True)
    report_md.write_text('\n'.join(report_lines), encoding='utf-8')

    print(f'baseline csv updated: {baseline_csv}')
    print(f'baseline json updated: {baseline_json}')
    print(f'new crashes csv: {new_csv}')
    print(f'baseline diff json: {diff_json}')
    print(f'new unique crashes: {len(new_keys)}')


if __name__ == '__main__':
    main()
