import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / 'coredump-full-analysis' / 'scripts'
sys.path.insert(0, str(SCRIPTS_DIR))

import auto_fix_submit  # noqa: E402
from auto_fix_types import CrashCluster, FixPlan, FixResult  # noqa: E402


class AutoFixSubmitPolicyTests(unittest.TestCase):
    def test_cluster_analysis_only_does_not_submit_report_commit(self):
        with TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            code_dir = workspace / '3.代码管理' / 'dde-dock'
            analysis_dir = workspace / '5.崩溃分析' / 'dde-dock' / 'version_1_2_3'
            (code_dir / '.git').mkdir(parents=True)
            (code_dir / 'src').mkdir(parents=True)
            (code_dir / 'src' / 'dock.cpp').write_text('int main() { return 0; }\n', encoding='utf-8')
            analysis_dir.mkdir(parents=True)
            (analysis_dir / 'analysis.json').write_text(json.dumps({
                'crashes': [
                    {
                        'id': 'c1',
                        'count': 2,
                        'version': '1.2.3',
                        'frames': [{'symbol': 'DockItem::paint', 'library': 'dde-dock'}],
                    }
                ]
            }, ensure_ascii=False), encoding='utf-8')

            cluster = CrashCluster(
                cluster_id='cluster-1',
                package='dde-dock',
                key='dock-item-paint',
                title='Dock paint crash',
                category='null-check',
                confidence='high',
                representative_crash={
                    'frames': [{'symbol': 'DockItem::paint', 'library': 'dde-dock'}],
                },
                crashes=[{'count': 2, 'version': '1.2.3'}],
            )
            plan = FixPlan(
                cluster_id='cluster-1',
                action='analysis_only',
                confidence='high',
                target_files=['src/dock.cpp'],
                commit_subject='[coredump-analysis] test',
                root_cause='root cause',
                fix_description='fix description',
                influence='influence',
            )
            fix_result = FixResult(
                cluster_id='cluster-1',
                action='analysis_only',
                changed=False,
                detail='no safe code change',
                files_changed=[],
            )

            with patch.object(auto_fix_submit, 'cluster_crashes', return_value=[cluster]), \
                 patch.object(auto_fix_submit, 'get_package_fix_plan_builder', return_value=lambda _: plan), \
                 patch.object(auto_fix_submit, 'get_package_fix_applier', return_value=lambda *_: fix_result):
                result = auto_fix_submit.run_cluster_auto_fix(
                    package='dde-dock',
                    version='1.2.3',
                    workspace=workspace,
                    target_branch='origin/develop/eagle',
                    reviewers=[],
                    dry_run=True,
                )

        self.assertFalse(result['submitted'])
        self.assertEqual('auto-submit skipped: no code changes', result['reason'])
        self.assertEqual(1, len(result['analysis_only']))
        self.assertNotIn('analysis_report', result)

    def test_manual_required_fixable_crash_does_not_submit_report_commit(self):
        with TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            code_dir = workspace / '3.代码管理' / 'dde-launcher'
            analysis_dir = workspace / '5.崩溃分析' / 'dde-launcher' / 'version_5_7_25_1'
            (code_dir / '.git').mkdir(parents=True)
            analysis_dir.mkdir(parents=True)
            (analysis_dir / 'analysis.json').write_text(json.dumps({
                'crashes': [
                    {
                        'id': 'c1',
                        'fixable': True,
                        'pattern_name': 'unknown',
                        'count': 1,
                        'app_layer_symbol': 'LauncherItem::paint',
                    }
                ]
            }, ensure_ascii=False), encoding='utf-8')

            argv = [
                'auto_fix_submit.py',
                '--package', 'dde-launcher',
                '--version', '5.7.25.1',
                '--workspace', str(workspace),
            ]

            with patch.object(auto_fix_submit, 'get_package_fix_plan_builder', return_value=None), \
                 patch.object(auto_fix_submit, 'get_package_fix_applier', return_value=None), \
                 patch.object(auto_fix_submit, 'get_fix_specs', return_value={'unknown': {'description': 'manual only'}}), \
                 patch.object(sys, 'argv', argv):
                exit_code = auto_fix_submit.main()

            result = json.loads((analysis_dir / 'auto_fix_result.json').read_text(encoding='utf-8'))

        self.assertEqual(0, exit_code)
        self.assertFalse(result['submitted'])
        self.assertEqual('auto-submit skipped: no code changes', result['reason'])
        self.assertEqual(1, len(result['manual_required']))
        self.assertNotIn('analysis_report', result)


if __name__ == '__main__':
    unittest.main()
