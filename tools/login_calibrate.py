"""Record the live login profile in design coordinates using Accessibility only.

Run the app (or tools/login_calibration_main.dart), then:
  python3 tools/login_calibrate.py snapshot home
  python3 tools/login_calibrate.py record open-login 'Log in' --tap
  python3 tools/login_calibrate.py record phone-email 'Use phone or email' --tap
  python3 tools/login_calibrate.py record use-email 'Email / Username' --tap
  python3 tools/login_calibrate.py record focus-email --editor email
  python3 tools/login_calibrate.py record focus-password --editor password
  python3 tools/login_calibrate.py record submit-password 'Log in'

No credentials, DOM, JavaScript, or ADB input gestures are used by this tool.
Credential input and later OTP steps must use the app's Accessibility runner.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'outputs/login-calibration'
ASSET = ROOT / 'assets/login-coordinate-profile.json'
ADB = [os.environ.get('ADB', str(pathlib.Path.home() / 'Library/Android/sdk/platform-tools/adb')),
       '-s', os.environ.get('ANDROID_SERIAL', 'emulator-5554')]
PACKAGE = 'com.stalliondz.tool.tiktok'

def command(action, point=None, input_value=None):
    nonce = uuid.uuid4().hex
    args = ['shell', 'am', 'broadcast', '-a', PACKAGE + '.SIGNUP_CALIBRATE', '-p', PACKAGE,
            '--es', 'signupCalibration', action, '--es', 'requestId', nonce]
    if point is not None:
        args += ['--es', 'x', str(point[0]), '--es', 'y', str(point[1])]
    if input_value is not None:
        # Existing debug bridge input slot; never log or save its value.
        args += ['--es', 'userOtp', input_value]
    subprocess.run(ADB + args, check=True, capture_output=True)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        result = subprocess.run(ADB + ['exec-out', 'run-as', PACKAGE, 'cat',
            'files/signup-calibration-' + nonce + '.json'], capture_output=True)
        try:
            value = json.loads(result.stdout)
            if value.get('requestId') == nonce:
                if value.get('ok') is False: raise RuntimeError(value.get('reason', 'Bridge rejected action'))
                return value
        except (ValueError, UnicodeDecodeError):
            pass
        time.sleep(0.2)
    raise RuntimeError('Calibration bridge timed out; open the TikTok page in the debug app.')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['snapshot', 'record', 'export'])
    parser.add_argument('name', nargs='?', default='current')
    parser.add_argument('label', nargs='?')
    parser.add_argument('--editor', choices=['email', 'password', 'otp'])
    parser.add_argument('--tap', action='store_true')
    parser.add_argument('--id', help='Exact Accessibility node ID when a label is duplicated')
    parser.add_argument('--allow-disabled', action='store_true', help='Record geometry only; never tap a disabled control')
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    profile = json.loads(ASSET.read_text())
    if args.action == 'export':
        profile['points'].update(command('login-profile')['points'])
        ASSET.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + '\n')
        print('Exported', len(profile['points']), 'saved login coordinates.')
        return
    snapshot = command('snapshot')
    if not snapshot.get('ready'): raise RuntimeError('WebView is not ready.')
    left, top, right, bottom = snapshot['webBounds']
    width, height = right-left, bottom-top
    if abs(width/height - 0.5) >= 0.003: raise RuntimeError('Expected fixed 400x800 WebView.')
    nodes = snapshot['nodes']
    dialogs = [n['id'] for n in nodes if n.get('className') == 'android.app.AlertDialog']
    if dialogs:
        nodes = [n for n in nodes if n['id'] == dialogs[-1] or n['id'].startswith(dialogs[-1] + '.')]
    def point(n):
        a,b,c,d = n['bounds']
        return [round(((a+c)/2-left)*400/width, 2), round(((b+d)/2-top)*800/height, 2)]
    if args.action == 'record':
        def matches(n):
            if not n.get('enabled') and not args.allow_disabled: return False
            if args.editor:
                if not n.get('editable'): return False
                if args.editor == 'password': return n.get('password')
                return not n.get('password') and re.search('email|username' if args.editor == 'email' else 'code|otp', n.get('hint', ''), re.I)
            return not n.get('editable') and args.label and any(
                str(n.get(key, '')).strip().lower() == args.label.lower()
                for key in ['text', 'description', 'hint'])
        targets = [n for n in nodes if matches(n)]
        if args.id: targets = [n for n in targets if n['id'] == args.id]
        if not targets: raise RuntimeError('Expected control is not exposed by Accessibility.')
        if args.name.startswith('submit-'):
            targets = [n for n in targets if n.get('clickable')]
        if len(targets) != 1: raise RuntimeError('Ambiguous control; inspect snapshot before recording.')
        if args.tap and not targets[0].get('enabled'): raise RuntimeError('Cannot tap a disabled control.')
        p = point(targets[0])
        profile['points'][args.name] = p
        profile['calibrationDevice'] = 'Pixel_9 / Android / 1080x2424 / density420'
        profile['evidence'] = 'outputs/login-calibration/actions.jsonl'
        ASSET.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + '\n')
        result = command('tap', p) if args.tap else {'ok': True}
        with (OUTPUT/'actions.jsonl').open('a') as file:
            file.write(json.dumps({'action': args.name, 'point': p, 'tapped': args.tap, 'ok': result.get('ok')}) + '\n')
        print(args.name, p, 'tapped' if args.tap else 'recorded')
    else:
        for n in nodes:
            label = ' '.join(str(n.get(k, '')) for k in ['text', 'description', 'hint']).strip()
            if label or n.get('editable'):
                print(json.dumps({'id': n['id'], 'label': label, 'point': point(n), 'editable': n.get('editable'),
                                  'password': n.get('password'), 'enabled': n.get('enabled'), 'clickable': n.get('clickable')}))
    (OUTPUT/(args.name+'.json')).write_text(json.dumps(snapshot, ensure_ascii=False, indent=2)+'\n')

if __name__ == '__main__':
    main()
