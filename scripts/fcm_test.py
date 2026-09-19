#!/usr/bin/env python3
"""Gui 1 push truc tiep qua FCM, bo qua Mattermost — de tach biet loi Firebase vs loi push proxy.

Can: service account JSON cua dung Firebase project (chat-701d9).
  Firebase Console > Project settings > Service accounts > Generate new private key

Dung:
  pip install google-auth requests
  python3 scripts/fcm_test.py <service-account.json> <fcm-token>

Lay <fcm-token> (bo tien to android_rn-v2:):
  adb exec-out run-as com.thaiduongco.chat cat files/databases/app.db > /tmp/app.db
  sqlite3 /tmp/app.db "select value from Global where id='deviceToken';" | tr -d '"' | cut -d: -f2-
"""
import json
import sys

try:
    import requests
    from google.oauth2 import service_account
    from google.auth.transport.requests import Request
except ImportError:
    sys.exit('Thieu thu vien: pip install google-auth requests')

if len(sys.argv) != 3:
    sys.exit(__doc__)

sa_path, token = sys.argv[1], sys.argv[2]
sa = json.load(open(sa_path))
project = sa['project_id']

creds = service_account.Credentials.from_service_account_file(
    sa_path, scopes=['https://www.googleapis.com/auth/firebase.messaging'])
creds.refresh(Request())

# Mattermost gui DATA message (khong phai notification) de native tu dung notification.
payload = {
    'message': {
        'token': token,
        'android': {'priority': 'high'},
        'data': {
            'type': 'message',
            'version': 'v2',
            'channel_id': 'test0000000000000000000000',
            'post_id': 'test0000000000000000000001',
            'message': 'fcm_test.py',
            'ack_id': 'fcm-test',
        },
    },
}

r = requests.post(
    f'https://fcm.googleapis.com/v1/projects/{project}/messages:send',
    headers={'Authorization': f'Bearer {creds.token}'},
    json=payload, timeout=30)

print(f'Firebase project : {project}')
print(f'HTTP {r.status_code}')
print(r.text)
print()
if r.status_code == 200:
    print('FCM da nhan. Xem log tren may:')
    print('  adb logcat -d | grep "CustomPushNotification: onReceived"')
    print('=> Neu THAY log: Firebase + thiet bi OK, loi nam o push proxy cua Mattermost.')
    print('=> Neu KHONG thay: van de o thiet bi (battery restriction / force-stop / khong co Play Services).')
elif 'UNREGISTERED' in r.text or 'SenderId' in r.text:
    print('=> Token khong thuoc project nay. Service account va google-services.json khac project.')
