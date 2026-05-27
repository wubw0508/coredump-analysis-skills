import importlib.util
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / 'coredump-full-analysis' / 'scripts'
ENHANCED_PATH = SCRIPTS_DIR / 'enhanced_analysis.py'
REPORT_PATH = SCRIPTS_DIR / 'analyze_crash_per_version.py'

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


enhanced_analysis = load_module('enhanced_analysis', ENHANCED_PATH)
report_module = load_module('analyze_crash_per_version', REPORT_PATH)


class DeepDiveReasonTests(unittest.TestCase):
    def make_analyzer(self, workspace, package='dde-dock'):
        return enhanced_analysis.EnhancedAnalyzer(workspace=workspace, package=package, version='1.0.0')

    def test_uncertain_crash_triggers_uncertain_reason(self):
        with TemporaryDirectory() as tmp:
            analyzer = self.make_analyzer(tmp)
            reasons = analyzer._get_deep_dive_reasons({'fixable': 'uncertain', 'count': 1})
            self.assertIn('uncertain_fixability', reasons)

    def test_app_layer_symbol_triggers_app_layer_reason(self):
        with TemporaryDirectory() as tmp:
            analyzer = self.make_analyzer(tmp)
            reasons = analyzer._get_deep_dive_reasons({'fixable': True, 'app_layer_symbol': 'DockItem::paint', 'count': 1})
            self.assertIn('app_layer_signal', reasons)

    def test_package_owned_key_frame_symbol_triggers_app_layer_reason(self):
        with TemporaryDirectory() as tmp:
            analyzer = self.make_analyzer(tmp)
            reasons = analyzer._get_deep_dive_reasons({
                'fixable': True,
                'count': 1,
                'key_frame': {'symbol': 'dde-dock::MainWindow::show', 'library': 'libQt5Core.so.5'},
            })
            self.assertIn('app_layer_signal', reasons)

    def test_high_frequency_triggers_reason(self):
        with TemporaryDirectory() as tmp:
            analyzer = self.make_analyzer(tmp)
            reasons = analyzer._get_deep_dive_reasons({'fixable': True, 'count': 3})
            self.assertIn('high_frequency', reasons)

    def test_invalid_count_does_not_crash(self):
        with TemporaryDirectory() as tmp:
            analyzer = self.make_analyzer(tmp)
            reasons = analyzer._get_deep_dive_reasons({'fixable': True, 'count': 'unknown'})
            self.assertEqual([], reasons)


class MarkdownReportRenderingTests(unittest.TestCase):
    def test_markdown_uses_automatic_deep_dive_wording(self):
        analysis = {
            'package': 'dde-dock',
            'version': '1.2.3',
            'analysis_time': '2026-05-27 16:00:00',
            'summary': {
                'package': 'dde-dock',
                'version': '1.2.3',
                'unique_crashes': 1,
                'total_crash_records': 3,
                'fixable_count': 1,
                'non_fixable_count': 0,
                'uncertain_count': 0,
                'fix_rate': 100.0,
            },
            'by_signal': {'SIGSEGV': 1},
            'crashes': [{
                'id': 'crash-1',
                'count': 3,
                'signal': 'SIGSEGV',
                'signal_desc': '段错误',
                'app_layer_symbol': 'DockItem::paint',
                'fixable': True,
                'fix_reason': 'test reason',
                'fix_type': 'null-check',
                'fix_code': 'if (!ptr) return;',
                'key_frame': {'index': 0, 'symbol': 'DockItem::paint', 'library': 'dde-dock'},
                'exe': '/usr/bin/dde-dock',
                'buildid': 'ab12cd34',
                'stack': [],
                'enhanced': {
                    'addr2line': [],
                    'source_context': [],
                    'git_analysis': [],
                    'objdump': None,
                    'llm_analysis': None,
                    'debuginfod': None,
                    'deep_dive': {
                        'performed': True,
                        'frame_limit': 600,
                        'improved': False,
                        'reasons': ['app_layer_signal', 'high_frequency'],
                    },
                    'degradation_reasons': ['deep_dive_exhausted', 'deep_dive_no_gain'],
                },
            }],
            'recommendations': ['keep digging'],
            'enhanced_stats': {
                'addr2line_resolved': 0,
                'addr2line_partial': 0,
                'source_found': 0,
                'git_available': 0,
                'objdump_available': 0,
                'llm_analyzed': 0,
                'fixability_improved': 0,
            },
            'deep_dive_stats': {'performed': 1, 'improved': 0},
        }

        with TemporaryDirectory() as tmp:
            output = Path(tmp) / 'analysis_report.md'
            report_module.save_markdown_report(analysis, output)
            text = output.read_text(encoding='utf-8')
            self.assertIn('自动二次深挖', text)
            self.assertIn('frame_limit: 600', text)
            self.assertIn('deep_dive_exhausted', text)
            self.assertIn('deep_dive_no_gain', text)
            self.assertNotIn('uncertain 二次深挖', text)


if __name__ == '__main__':
    unittest.main()
