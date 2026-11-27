'use strict';

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { handleRuleChange } = require('./blocked_app_notification_logic');

if (!getApps().length) initializeApp();

exports.notifyChildBlockedApps = onDocumentWritten(
  { document: 'app_rules/{parentId}', retry: true },
  event => handleRuleChange(event, getFirestore(), getMessaging()),
);
