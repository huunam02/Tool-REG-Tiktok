#!/usr/bin/env python3
"""Record orientation-specific Accessibility points from the debug WebView."""
import argparse
import json
from pathlib import Path

from login_calibrate import command

ROOT = Path(__file__).resolve().parent.parent
ASSET = ROOT / 'assets/nurture-coordinate-profile.json'
OUTPUT = ROOT / 'outputs/nurture-calibration'


def export():
    profile = json.loads(ASSET.read_text())
    profile['points'].update(command('nurture-profile')['points'])
    ASSET.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + '\n')
    return profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['record', 'snapshot', 'export', 'open', 'next'])
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if args.action == 'export':
        print('Saved', len(export()['points']), 'points.')
        return
    if args.action in ['open', 'next']:
        layout = command('nurture-layout')
        if layout.get('panelOpen'):
            raise RuntimeError('Close the comment panel first.')
        key = (layout['layout'] + '/open-comments' if args.action == 'open'
               else layout['orientation'] + '/feed/next-video')
        point = layout['points'].get(key)
        if point is None:
            raise RuntimeError('Expected feed control unavailable; close the comment panel first.')
        command('tap', point)  # Exactly one gesture. Never publishes a comment.
        print(args.action, layout['orientation'], point)
        return
    if args.action == 'record':
        layout = command('nurture-layout')
        export()
        print(layout['orientation'], layout['layout'])
        for key, point in layout['points'].items():
            if key.startswith(layout['orientation'] + '/'):
                print(key, point)
    snapshot = command('snapshot')
    if not snapshot.get('ready'):
        raise RuntimeError('Accessibility WebView unavailable.')
    (OUTPUT / 'current.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
