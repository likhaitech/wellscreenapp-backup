'use strict';

const { createHash } = require('node:crypto');

// Missing rules (e.g. a document created for websites) means no app rules.
// Malformed rules are unknown, not an empty restriction list.
function restrictedApps(data) {
  const rules = data?.rules;
  if (rules === undefined) return new Map();
  if (!Array.isArray(rules)) return null;
  const apps = new Map();
  for (const rule of rules) {
    if (!rule || typeof rule.packageName !== 'string' ||
        !rule.packageName.trim() || typeof rule.restrictEnabled !== 'boolean') {
      return null;
    }
    if (rule.restrictEnabled) {
      const pkg = rule.packageName;
      const label = typeof rule.appName === 'string' ? rule.appName.trim() : '';
      apps.set(pkg, (label || pkg).slice(0, 150));
    }
  }
  return apps;
}

function newlyBlocked(before, after) {
  if (!after) return [];
  const oldApps = restrictedApps(before);
  const newApps = restrictedApps(after);
  if (!oldApps || !newApps) return [];
  return [...newApps].filter(([pkg]) => !oldApps.has(pkg))
    .map(([packageName, appName]) => ({ packageName, appName }));
}

function notificationId(parentId, profileId, eventId) {
  return 'app_restriction_' + createHash('sha256')
    .update(JSON.stringify([parentId, profileId, eventId])).digest('hex');
}

function content(apps) {
  const title = apps.length === 1 ? 'New App Restriction' : 'New App Restrictions';
  const names = apps.map(app => app.appName).join(', ');
  const body = apps.length === 1
    ? `Your parent has blocked ${names}. You can request temporary access if needed.`
    : `Your parent has blocked ${apps.length} applications: ${names}. You can request temporary access if needed.`;
  return { title, body };
}

// Called by the trusted Firestore trigger only. Persist the inbox before FCM.
async function handleRuleChange(event, db, messaging, log = console) {
  const parentId = event.params?.parentId;
  const eventId = event.id;
  const after = event.data?.after?.data();
  const apps = newlyBlocked(event.data?.before?.data(), after);
  if (!parentId || !eventId || !after || after.parentId !== parentId || !apps.length) return;
  const createdAt = event.data.after.updateTime || new Date(event.time);
  const { title, body } = content(apps);
  const profiles = await db.collection('child_profiles').where('parentId', '==', parentId).get();
  for (const profile of profiles.docs) {
    const id = notificationId(parentId, profile.id, eventId);
    // Re-read pairing and inbox transactionally. Duplicate trigger deliveries
    // cannot reset readAt or claim a second push.
    const claimed = await db.runTransaction(async tx => {
      const current = (await tx.get(profile.ref)).data();
      const childUid = current?.childAccountId;
      if (!current || current.parentId !== parentId || current.pairingStatus !== 'connected' ||
          typeof childUid !== 'string' || !childUid || childUid === parentId || childUid.includes('/')) return null;
      const pairedAt = current.pairedAt;
      if (pairedAt?.toMillis && createdAt?.toMillis && pairedAt.toMillis() > createdAt.toMillis()) return null;
      const childRef = db.collection('users').doc(childUid);
      const child = (await tx.get(childRef)).data();
      if (!child || child.role !== 'child' || child.pairedChildProfileId !== profile.id ||
          child.pairedParentId !== parentId || child.pairingStatus !== 'connected') return null;
      const ref = childRef.collection('notifications').doc(id);
      if ((await tx.get(ref)).exists) return null;
      const token = [child.fcmToken, child.limitNotificationToken]
        .find(value => typeof value === 'string' && value.trim());
      tx.create(ref, {
        type: 'app_restrictions_changed', childProfileId: profile.id,
        recipientUid: childUid, title, body, createdAt, readAt: null,
        apps, pushStatus: token ? 'claimed' : 'no_token',
      });
      return { ref, childUid, token };
    });
    if (!claimed?.token) continue;
    // Keep full names in the inbox; keep the Android payload compact.
    const chars = Array.from(body);
    const pushBody = chars.length > 350 ? chars.slice(0, 347).join('') + '...' : body;
    let pushStatus = 'sent';
    try {
      await messaging.send({
        token: claimed.token, notification: { title, body: pushBody },
        data: { type: 'app_restrictions_changed', childProfileId: profile.id,
          recipientUid: claimed.childUid, eventId, notificationId: id },
        android: { priority: 'high', ttl: 15 * 60 * 1000,
          notification: { channelId: 'wellscreen_restrictions', tag: id } },
      });
    } catch (error) {
      pushStatus = 'failed';
      log.warn('Blocked app push failed:', error.code || error.name || 'unknown');
    }
    // Never blindly retry an attempted push; the inbox is already durable.
    await claimed.ref.update({ pushStatus });
  }
}

module.exports = { newlyBlocked, notificationId, content, handleRuleChange };
