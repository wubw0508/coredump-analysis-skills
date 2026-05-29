import csv
import json
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

REPO_ROOT = Path(__file__).resolve().parents[2]
BASELINE_SCRIPT = REPO_ROOT / 'coredump-full-analysis' / 'scripts' / 'reporting' / 'update_unique_crash_baseline.py'


class UniqueCrashBaselineTests(unittest.TestCase):
    def write_filtered_csv(self, path: Path, rows):
        fieldnames = ['Exe', 'Sig', 'Version', 'StackInfo', 'Count', 'UniqueKey']
        with path.open('w', encoding='utf-8', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for row in rows:
                writer.writerow(row)

    def test_update_baseline_detects_new_crashes_and_merges(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / 'workspace'
            baseline_root = root / 'baseline'
            (workspace / '2.数据筛选').mkdir(parents=True)
            filtered_csv = workspace / '2.数据筛选' / 'filtered_dde-dock_crash_data.csv'
            self.write_filtered_csv(filtered_csv, [
                {
                    'Exe': 'dde-dock',
                    'Sig': 'SIGSEGV',
                    'Version': '5.9.0',
                    'StackInfo': '#0 old',
                    'Count': '2',
                    'UniqueKey': 'dde-dock|SIGSEGV|5.9.0|oldsig',
                },
                {
                    'Exe': 'dde-dock',
                    'Sig': 'SIGABRT',
                    'Version': '5.9.1',
                    'StackInfo': '#0 new',
                    'Count': '1',
                    'UniqueKey': 'dde-dock|SIGABRT|5.9.1|newsig',
                },
            ])

            current_dir = baseline_root / 'current'
            current_dir.mkdir(parents=True)
            self.write_filtered_csv(current_dir / 'dde-dock_unique_crashes.csv', [
                {
                    'Exe': 'dde-dock',
                    'Sig': 'SIGSEGV',
                    'Version': '5.9.0',
                    'StackInfo': '#0 old',
                    'Count': '2',
                    'UniqueKey': 'dde-dock|SIGSEGV|5.9.0|oldsig',
                },
            ])
            (current_dir / 'dde-dock_unique_crashes.json').write_text(json.dumps({
                'package': 'dde-dock',
                'first_seen_map': {'dde-dock|SIGSEGV|5.9.0|oldsig': '2026-05-01T00:00:00'},
                'last_seen_map': {'dde-dock|SIGSEGV|5.9.0|oldsig': '2026-05-01T00:00:00'},
                'merged_from_runs': [],
            }, ensure_ascii=False), encoding='utf-8')

            result = subprocess.run([
                'python3', str(BASELINE_SCRIPT),
                '--package', 'dde-dock',
                '--filtered-csv', str(filtered_csv),
                '--workspace', str(workspace),
                '--baseline-root', str(baseline_root),
            ], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)

            diff = json.loads((workspace / '2.数据筛选' / 'dde-dock_crash_baseline_diff.json').read_text(encoding='utf-8'))
            with (baseline_root / 'current' / 'dde-dock_unique_crashes.csv').open('r', encoding='utf-8') as f:
                merged = list(csv.DictReader(f))
            with (workspace / '2.数据筛选' / 'dde-dock_new_crashes.csv').open('r', encoding='utf-8') as f:
                new_rows = list(csv.DictReader(f))
            meta = json.loads((baseline_root / 'current' / 'dde-dock_unique_crashes.json').read_text(encoding='utf-8'))

        self.assertIn('new unique crashes: 1', result.stdout)
        self.assertEqual(1, diff['new_unique_count'])
        self.assertEqual(2, diff['baseline_unique_count_after'])
        self.assertEqual(2, len(merged))
        self.assertEqual(1, len(new_rows))
        self.assertEqual('dde-dock|SIGABRT|5.9.1|newsig', new_rows[0]['UniqueKey'])
        self.assertEqual(2, meta['total_unique_crashes'])
        self.assertIn('dde-dock|SIGABRT|5.9.1|newsig', meta['unique_keys'])


if __name__ == '__main__':
    unittest.main()
