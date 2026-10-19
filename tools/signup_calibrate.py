"""ADB calibration for the debug-only signup bridge. Never reads credentials.

python3 tools/signup_calibrate.py snapshot home
python3 tools/signup_calibrate.py tap 200 300 open-login
python3 tools/signup_calibrate.py paste-email
"""
import json
import pathlib
import subprocess
import sys
import time
import uuid
import getpass
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'outputs/signup-calibration'
ADB = ['adb', '-s', 'emulator-5554']
PACKAGE = 'com.stalliondz.tool.tiktok'

def adb(*args):
    result = subprocess.run(ADB + list(args), capture_output=True)
    if result.returncode:
        raise RuntimeError('ADB command failed')
    return result.stdout

def command(action, x=None, y=None, user_otp=None):
    nonce = uuid.uuid4().hex
    args = ['shell', 'am', 'broadcast', '-a', PACKAGE + '.SIGNUP_CALIBRATE', '-p', PACKAGE,
            '--es', 'signupCalibration', action, '--es', 'requestId', nonce]
    if x is not None:
        # am uses --ef (float), which Intent exposes as float rather than double.
        args += ['--es', 'x', str(x), '--es', 'y', str(y)]
    if user_otp is not None:
        args += ['--es', 'userOtp', user_otp]
    adb(*args)
    deadline = time.monotonic() + (210 if action == 'paste-otp' else 90 if action == 'select-birthday' else 15)
    while time.monotonic() < deadline:
        result = subprocess.run(ADB + ['exec-out', 'run-as', PACKAGE, 'cat',
            'files/signup-calibration-' + nonce + '.json'], capture_output=True)
        raw = result.stdout
        try:
            value = json.loads(raw)
            if value.get('requestId') == nonce:
                return value
        except (json.JSONDecodeError, UnicodeDecodeError):
            pass
        time.sleep(0.2)
    raise RuntimeError('Calibration bridge timed out')

def store(action, result, label=''):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entry = {'time': time.strftime('%Y-%m-%dT%H:%M:%S%z'), 'action': action, 'label': label, 'result': result}
    with (OUTPUT / 'actions.jsonl').open('a') as file:
        file.write(json.dumps(entry, ensure_ascii=False) + '\n')

def main():
    action = sys.argv[1]
    if action == 'prepare':
        profile = json.loads((ROOT / 'assets/signup-coordinate-profile.json').read_text())
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            snapshot = command('snapshot')
            if any(n.get('text') == 'Log in' for n in snapshot.get('nodes', [])):
                break
            time.sleep(0.5)
        else:
            raise RuntimeError('Home did not expose Log in')
        sequence = [
            ('open-login', 'Log in to TikTok'), ('open-signup', 'Sign up for TikTok'),
            ('signup-phone-email', 'Use email'), ('use-email', 'Enter your email'),
            ('open-month', None), ('select-month', 'February'),
            ('open-day', None), ('select-day', '3'), ('open-year', None),
        ]
        for label, expected in sequence:
            x, y = profile['points'][label]
            result = command('tap', x, y)
            store('tap', {'point':[x,y], **result}, label)
            if not result.get('ok'):
                raise RuntimeError('Gesture did not complete: ' + label)
            time.sleep(0.8)
            if expected:
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    snapshot = command('snapshot')
                    if any(expected in str(n.get('text', '')) for n in snapshot.get('nodes', [])):
                        break
                    time.sleep(0.5)
                else:
                    raise RuntimeError('Expected screen not found after: ' + label)
        scroll = profile['yearScroll']
        snapshot = command('snapshot')
        left, top, right, bottom = snapshot['webBounds']
        def point(p):
            return [str(round(left+p[0]*(right-left)/400)), str(round(top+p[1]*(bottom-top)/800))]
        for _ in range(scroll['count']):
            adb('shell', 'input', 'swipe', *point(scroll['from']), *point(scroll['to']), str(scroll['durationMs']))
            time.sleep(0.8)
        result = command('tap', *profile['points']['select-year'])
        store('tap', result, 'select-year')
        time.sleep(0.8)
        snapshot = command('snapshot')
        for expected in ['February', '2001']:
            if not any(expected == n.get('text') for n in snapshot.get('nodes', [])):
                raise RuntimeError('Birthday selection did not match: ' + expected)
        print('Birthday 2001-02-03 prepared and read back; no email/OTP sent.')
    elif action == 'paste-user-otp':
        code = getpass.getpass('OTP (hidden): ')
        if not re.fullmatch(r'\d{6}', code):
            raise RuntimeError('Expected six digits')
        result = command(action, user_otp=code)
        print(json.dumps(result))
        store(action, result)
    elif action == 'snapshot':
        result = command(action)
        label = sys.argv[2] if len(sys.argv) > 2 else 'current'
        OUTPUT.mkdir(parents=True, exist_ok=True)
        (OUTPUT / (label + '.json')).write_text(json.dumps(result, ensure_ascii=False, indent=2))
        print('Ready:', result.get('ready'), 'WebView:', result.get('webBounds'))
        if result.get('ready'):
            left, top, right, bottom = result['webBounds']
            dialogs = [n['id'] for n in result.get('nodes', []) if n.get('className') == 'android.app.AlertDialog']
            for node in result.get('nodes', []):
                if dialogs and not any(node['id'] == d or node['id'].startswith(d + '.') for d in dialogs):
                    continue
                bounds = node['bounds']
                text = ' '.join(str(node.get(k, '')) for k in ['text', 'description', 'hint']).strip()
                if text or node.get('editable'):
                    x = ((bounds[0] + bounds[2]) / 2 - left) * 400 / (right-left)
                    y = ((bounds[1] + bounds[3]) / 2 - top) * 800 / (bottom-top)
                    print(json.dumps({'id':node['id'], 'label':text[:130], 'point':[round(x,2),round(y,2)],
                        'enabled':node['enabled'], 'editable':node['editable'], 'password':node['password'],
                        'length':node['length'], 'class':node['className']}, ensure_ascii=False))
        store(action, {'ready':result.get('ready'), 'webBounds':result.get('webBounds')}, label)
    elif action == 'swipe':
        x, y, x2, y2 = map(float, sys.argv[2:6])
        snapshot = command('snapshot')
        left, top, right, bottom = snapshot['webBounds']
        def point(a, b):
            return [str(round(left+a*(right-left)/400)), str(round(top+b*(bottom-top)/800))]
        adb('shell', 'input', 'swipe', *point(x,y), *point(x2,y2), '450')
        result = {'from':[x,y], 'to':[x2,y2], 'durationMs':450}
        print(json.dumps(result))
        store(action, result, sys.argv[6] if len(sys.argv)>6 else '')
    elif action == 'tap':
        x, y = float(sys.argv[2]), float(sys.argv[3])
        result = command('tap', x, y)
        print(json.dumps(result))
        store(action, {'point':[x,y], **result}, sys.argv[4] if len(sys.argv)>4 else '')
    else:
        result = command(action)
        print(json.dumps(result))
        store(action, result)

try:
    main()
except Exception as error:
    print('Calibration failed:', type(error).__name__, str(error) if isinstance(error, RuntimeError) else '(details omitted)')
    sys.exit(1)
