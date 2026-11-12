"""Mocked FastAPI router contract test; no Firebase network or Render calls.

Requires fastapi/httpx installed. Does NOT test production authentication,
Firestore approval transactions, or FCM delivery.
"""
import sys
import types
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'backend'))

# Import the ACTUAL route module while stubbing only its Firebase service layer.
stub = types.ModuleType('app.services.chat_access_service')
class ChatAccessError(ValueError):
    pass

def authenticated_uid(authorization):
    if authorization != 'Bearer test-token':
        raise ChatAccessError('Unauthorized')
    return 'parent-uid'

def respond_to_request(**kwargs):
    return {'status': 'approved_pending_activation' if kwargs['approve'] else 'declined',
            'approvedMinutes': kwargs['approved_minutes']}

def activate_grant(**kwargs):
    return {'status': 'active'}

def sweep_chat_notifications():
    return {'sent': 0}

def chat_push_status(**kwargs):
    return {'registered': True, 'tokenSource': 'chatFcmToken', 'notificationPermission': 'authorized'}

def dispatch_chat_event(**kwargs):
    return {'status': 'submitted'}

for name in ('ChatAccessError','authenticated_uid','respond_to_request',
             'activate_grant','sweep_chat_notifications','dispatch_chat_event', 'chat_push_status'):
    setattr(stub, name, globals()[name])
sys.modules[stub.__name__] = stub

from fastapi import FastAPI
from fastapi.testclient import TestClient
from app.routes.parent_child_chat import router

app = FastAPI()
app.include_router(router)
client = TestClient(app)
assert client.get('/chat/health').json() == {
    'status':'ok', 'feature':'parent_child_chat','apiVersion':2}
path = '/chat/requests/child-profile/request-42/decision'
resp = client.post(path, json={'approve':True,'approvedMinutes':30},
                   headers={'Authorization':'Bearer test-token'})
assert resp.status_code == 200, resp.text
assert resp.json() == {'status':'approved_pending_activation','approvedMinutes':30}
resp = client.post(path, json={'approve':False},
                   headers={'Authorization':'Bearer test-token'})
assert resp.status_code == 200 and resp.json()['status'] == 'declined'
assert client.post(path, json={'approve':True,'approvedMinutes':300},
                   headers={'Authorization':'Bearer test-token'}).status_code == 422
assert client.post(path, json={'approve':True,'approvedMinutes':30}).status_code == 403
assert client.post('/chat/events/child-profile/message/msg-1/dispatch',
                   headers={'Authorization':'Bearer test-token'}).status_code == 200
assert client.get('/chat/push/status', headers={'Authorization':'Bearer test-token'}).json()['registered']
assert client.get('/chat/push/status').status_code == 403
print('Mocked FastAPI router contract passed (decision, dispatch, self token status).')
