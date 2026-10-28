import re
import unittest
from pathlib import Path


SOURCE = Path(__file__).parents[1] / 'index.html'
WARM_THEME = re.search(
    r'<style id="warm-graphite-theme">([\s\S]*?)</style>',
    SOURCE.read_text(encoding='utf-8'),
).group(1)


def rule_for(selector):
    match = re.search(re.escape(selector) + r'[^{]*\{([^}]*)\}', WARM_THEME)
    return match.group(1) if match else None


class WarmThemeContractTest(unittest.TestCase):
    def test_warm_theme_exposes_semantic_interaction_tokens(self):
        for token in (
            'focus-ring', 'accent-hover', 'accent-strong', 'selection-surface',
            'selection-border', 'drop-surface', 'drop-border',
            'completed-surface', 'completed-border',
        ):
            self.assertIn(f'--{token}:', WARM_THEME, f'missing --{token}')

    def test_warm_active_and_drag_states_consume_semantic_tokens(self):
        for selector in (
            '.nav .active', '.days .active', '.home-calendar-day.selected',
            '.drop-marker.ready', '.column.drag-over', '.days button.drop-target',
        ):
            rule = rule_for(selector)
            self.assertIsNotNone(rule, f'missing {selector}')
            self.assertRegex(
                rule, r'var\(--(?:selection|drop)-',
                f'{selector} must use a semantic selection or drop token',
            )

    def test_warm_focus_and_completed_controls_use_semantic_tokens(self):
        self.assertRegex(
            WARM_THEME,
            r'button:focus-visible[^\{]*\{[^}]*var\(--focus-ring\)',
        )
        self.assertRegex(
            WARM_THEME,
            r'\.card\.done \.complete[^\{]*\{[^}]*var\(--completed-(?:surface|border)\)',
        )


if __name__ == '__main__':
    unittest.main()
