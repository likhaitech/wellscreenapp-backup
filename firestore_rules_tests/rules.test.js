// Real Firestore Security Rules tests, run against the actual Firestore
// emulator (not a mock) - loading the real firestore.rules file from the
// repo root and exercising it the way the app's own client code actually
// reads/writes each collection, per the per-collection comments in that
// file. This is the first time these rules have been checked against
// anything other than manual reasoning.
import { describe, it, beforeAll, afterAll, beforeEach } from 'vitest';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { doc, getDoc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';

const PROJECT_ID = 'wellscreen-rules-test';

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync('./firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ---------------------------------------------------------------------
// users/{uid}
// ---------------------------------------------------------------------
describe('users/{uid}', () => {
  it('a signed-in user can read their own user doc', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/parent1'), { role: 'parent' });
    });
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertSucceeds(getDoc(doc(parent1, 'users/parent1')));
  });

  it('a signed-in user CANNOT read a different user doc', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/parent1'), { role: 'parent' });
    });
    const parent2 = testEnv.authenticatedContext('parent2').firestore();
    await assertFails(getDoc(doc(parent2, 'users/parent1')));
  });

  it('an admin CAN read any user doc', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/admin1'), { role: 'admin' });
      await setDoc(doc(ctx.firestore(), 'users/parent1'), { role: 'parent' });
    });
    const admin1 = testEnv.authenticatedContext('admin1').firestore();
    await assertSucceeds(getDoc(doc(admin1, 'users/parent1')));
  });

  it('a user can create their own doc with role parent or child', async () => {
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertSucceeds(
      setDoc(doc(parent1, 'users/parent1'), { role: 'parent' })
    );
  });

  it('CANNOT create their own doc with role admin (the privilege-escalation fix)', async () => {
    // This is the exact bug the "FIX (see isAdmin() above)" comment in
    // firestore.rules describes: a client setting its own role straight
    // to 'admin' on create. The rule's create clause restricts
    // request.resource.data.role to ['parent', 'child'] specifically to
    // block this.
    const attacker = testEnv.authenticatedContext('attacker1').firestore();
    await assertFails(
      setDoc(doc(attacker, 'users/attacker1'), { role: 'admin' })
    );
  });

  it('CANNOT create a doc for a different uid', async () => {
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertFails(
      setDoc(doc(parent1, 'users/someoneElse'), { role: 'parent' })
    );
  });

  it('CANNOT update their own role from parent to admin after creation', async () => {
    // Same privilege-escalation family, but via update instead of create:
    // the update rule requires request.resource.data.role ==
    // resource.data.role, i.e. role is immutable from the client.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/parent1'), { role: 'parent' });
    });
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertFails(
      updateDoc(doc(parent1, 'users/parent1'), { role: 'admin' })
    );
  });

  it('CAN update other fields while leaving role untouched (e.g. FCM token save)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/parent1'), { role: 'parent' });
    });
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertSucceeds(
      updateDoc(doc(parent1, 'users/parent1'), {
        role: 'parent',
        fcmToken: 'abc123',
      })
    );
  });

  it('an unauthenticated (unsigned-in) request CANNOT read any user doc', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/parent1'), { role: 'parent' });
    });
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'users/parent1')));
  });
});

// ---------------------------------------------------------------------
// child_profiles/{childProfileId}
// ---------------------------------------------------------------------
describe('child_profiles/{childProfileId}', () => {
  it('the owning parent can create a child profile with their own parentId', async () => {
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertSucceeds(
      setDoc(doc(parent1, 'child_profiles/cp1'), { parentId: 'parent1' })
    );
  });

  it('CANNOT create a child profile claiming a different parentId', async () => {
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertFails(
      setDoc(doc(parent1, 'child_profiles/cp1'), { parentId: 'someoneElse' })
    );
  });

  it('the owning parent can read their own child profile', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'child_profiles/cp1'), {
        parentId: 'parent1',
      });
    });
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertSucceeds(getDoc(doc(parent1, 'child_profiles/cp1')));
  });

  it('a different (non-owning, non-claiming) signed-in user CANNOT read the profile', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'child_profiles/cp1'), {
        parentId: 'parent1',
      });
    });
    const stranger = testEnv.authenticatedContext('stranger1').firestore();
    await assertFails(getDoc(doc(stranger, 'child_profiles/cp1')));
  });

  it('an unclaimed profile can be claimed by a child setting childAccountId to themselves', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'child_profiles/cp1'), {
        parentId: 'parent1',
      });
    });
    const child1 = testEnv.authenticatedContext('child1').firestore();
    await assertSucceeds(
      updateDoc(doc(child1, 'child_profiles/cp1'), {
        parentId: 'parent1',
        childAccountId: 'child1',
      })
    );
  });

  it('CANNOT claim an unclaimed profile as someone other than yourself', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'child_profiles/cp1'), {
        parentId: 'parent1',
      });
    });
    const child1 = testEnv.authenticatedContext('child1').firestore();
    await assertFails(
      updateDoc(doc(child1, 'child_profiles/cp1'), {
        parentId: 'parent1',
        childAccountId: 'someoneElse',
      })
    );
  });

  it('an already-claimed profile CANNOT be re-claimed by a different child', async () => {
    // This is the "isUnclaimed() || isClaimedByCaller()" branch: once
    // childAccountId is set, only that same child (or the owning parent)
    // may write to it again.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'child_profiles/cp1'), {
        parentId: 'parent1',
        childAccountId: 'child1',
      });
    });
    const child2 = testEnv.authenticatedContext('child2').firestore();
    await assertFails(
      updateDoc(doc(child2, 'child_profiles/cp1'), {
        parentId: 'parent1',
        childAccountId: 'child2',
      })
    );
  });

  it('the already-claimed child CAN sync usage/location merge updates', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'child_profiles/cp1'), {
        parentId: 'parent1',
        childAccountId: 'child1',
      });
    });
    const child1 = testEnv.authenticatedContext('child1').firestore();
    await assertSucceeds(
      updateDoc(doc(child1, 'child_profiles/cp1'), {
        parentId: 'parent1',
        childAccountId: 'child1',
        lastLocation: { lat: 1, lng: 2 },
      })
    );
  });

  it('CANNOT reassign a claimed profile to a different parentId', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'child_profiles/cp1'), {
        parentId: 'parent1',
        childAccountId: 'child1',
      });
    });
    const child1 = testEnv.authenticatedContext('child1').firestore();
    await assertFails(
      updateDoc(doc(child1, 'child_profiles/cp1'), {
        parentId: 'parentAttacker',
        childAccountId: 'child1',
      })
    );
  });

  it('deletes are always denied, even for the owning parent', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'child_profiles/cp1'), {
        parentId: 'parent1',
      });
    });
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    const { deleteDoc } = await import('firebase/firestore');
    await assertFails(deleteDoc(doc(parent1, 'child_profiles/cp1')));
  });
});

// ---------------------------------------------------------------------
// pairing_codes/{code}
// ---------------------------------------------------------------------
describe('pairing_codes/{code}', () => {
  it('the owning parent can create a pairing code', async () => {
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertSucceeds(
      setDoc(doc(parent1, 'pairing_codes/123456'), {
        parentId: 'parent1',
        childId: 'cp1',
        status: 'active',
      })
    );
  });

  it('any signed-in user can read a pairing code (unpaired-child lookup case)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'pairing_codes/123456'), {
        parentId: 'parent1',
        childId: 'cp1',
        status: 'active',
      });
    });
    const child1 = testEnv.authenticatedContext('child1').firestore();
    await assertSucceeds(getDoc(doc(child1, 'pairing_codes/123456')));
  });

  it('a child can claim an active code, flipping it to connected as themselves', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'pairing_codes/123456'), {
        parentId: 'parent1',
        childId: 'cp1',
        status: 'active',
      });
    });
    const child1 = testEnv.authenticatedContext('child1').firestore();
    await assertSucceeds(
      updateDoc(doc(child1, 'pairing_codes/123456'), {
        parentId: 'parent1',
        childId: 'cp1',
        status: 'connected',
        childAccountId: 'child1',
      })
    );
  });

  it('CANNOT claim a code that is already connected (no reuse)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'pairing_codes/123456'), {
        parentId: 'parent1',
        childId: 'cp1',
        status: 'connected',
        childAccountId: 'child1',
      });
    });
    const child2 = testEnv.authenticatedContext('child2').firestore();
    await assertFails(
      updateDoc(doc(child2, 'pairing_codes/123456'), {
        parentId: 'parent1',
        childId: 'cp1',
        status: 'connected',
        childAccountId: 'child2',
      })
    );
  });

  it('CANNOT change parentId or childId while claiming', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'pairing_codes/123456'), {
        parentId: 'parent1',
        childId: 'cp1',
        status: 'active',
      });
    });
    const child1 = testEnv.authenticatedContext('child1').firestore();
    await assertFails(
      updateDoc(doc(child1, 'pairing_codes/123456'), {
        parentId: 'parentAttacker',
        childId: 'cp1',
        status: 'connected',
        childAccountId: 'child1',
      })
    );
  });

  it('deletes are always denied', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'pairing_codes/123456'), {
        parentId: 'parent1',
        childId: 'cp1',
        status: 'active',
      });
    });
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    const { deleteDoc } = await import('firebase/firestore');
    await assertFails(deleteDoc(doc(parent1, 'pairing_codes/123456')));
  });
});

// ---------------------------------------------------------------------
// app_rules/{parentId}
// ---------------------------------------------------------------------
describe('app_rules/{parentId}', () => {
  it('the owning parent can write their own rules doc', async () => {
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertSucceeds(
      setDoc(doc(parent1, 'app_rules/parent1'), { bedtime: '21:00' })
    );
  });

  it('CANNOT write to a different parent\'s rules doc', async () => {
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertFails(
      setDoc(doc(parent1, 'app_rules/parent2'), { bedtime: '21:00' })
    );
  });

  it('the paired child CAN read the parent\'s rules doc (cross-account by design)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'app_rules/parent1'), {
        bedtime: '21:00',
      });
    });
    const child1 = testEnv.authenticatedContext('child1').firestore();
    await assertSucceeds(getDoc(doc(child1, 'app_rules/parent1')));
  });
});

// ---------------------------------------------------------------------
// system_logs/{id}
// ---------------------------------------------------------------------
describe('system_logs/{logId}', () => {
  it('an admin can read system logs', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/admin1'), { role: 'admin' });
      await setDoc(doc(ctx.firestore(), 'system_logs/log1'), { msg: 'hi' });
    });
    const admin1 = testEnv.authenticatedContext('admin1').firestore();
    await assertSucceeds(getDoc(doc(admin1, 'system_logs/log1')));
  });

  it('a non-admin (even signed-in) CANNOT read system logs', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/parent1'), { role: 'parent' });
      await setDoc(doc(ctx.firestore(), 'system_logs/log1'), { msg: 'hi' });
    });
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertFails(getDoc(doc(parent1, 'system_logs/log1')));
  });

  it('no client, including admin, can write system logs', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/admin1'), { role: 'admin' });
    });
    const admin1 = testEnv.authenticatedContext('admin1').firestore();
    await assertFails(setDoc(doc(admin1, 'system_logs/log2'), { msg: 'x' }));
  });
});

// ---------------------------------------------------------------------
// Deny-by-default fallback, including the dead camelCase pairingCodes
// collection flagged in the rules file's own comments.
// ---------------------------------------------------------------------
describe('deny-by-default fallback', () => {
  it('an unmodeled collection denies all reads/writes, even signed-in', async () => {
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertFails(
      setDoc(doc(parent1, 'some_future_collection/doc1'), { x: 1 })
    );
  });

  it('the flagged-dead camelCase pairingCodes collection is also denied (not silently open)', async () => {
    const parent1 = testEnv.authenticatedContext('parent1').firestore();
    await assertFails(
      setDoc(doc(parent1, 'pairingCodes/123456'), { parentId: 'parent1' })
    );
  });
});

// ---------------------------------------------------------------------
// Access requests are created only by the trusted backend; normal chat
// messages retain their original client-side create permissions.
// ---------------------------------------------------------------------
describe('app access request rate-limit protection', () => {
  async function seedFamily() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'child_profiles/cp1'), {
        parentId: 'parent1', childAccountId: 'child1', pairingStatus: 'connected',
      });
      await setDoc(doc(db, 'child_profiles/cp1/access_requests/existing'), {
        childUid: 'child1', packageName: 'com.example.app', status: 'pending',
      });
      await setDoc(doc(db, 'child_profiles/cp1/request_limits/app_access'), {
        updatedAt: serverTimestamp(),
      });
    });
  }

  it('rejects direct app access creation even by the paired child', async () => {
    await seedFamily();
    const child = testEnv.authenticatedContext('child1').firestore();
    await assertFails(setDoc(doc(child, 'child_profiles/cp1/access_requests/new'), {
      childUid: 'child1',
      packageName: 'com.example.app',
      appName: 'Example',
      requestedMinutes: 30,
      status: 'pending',
      createdAt: serverTimestamp(),
      notificationState: 'pending',
    }));
  });

  it('allows both family members to read backend-created access requests', async () => {
    await seedFamily();
    for (const uid of ['parent1', 'child1']) {
      const db = testEnv.authenticatedContext(uid).firestore();
      await assertSucceeds(getDoc(doc(db, 'child_profiles/cp1/access_requests/existing')));
    }
    const stranger = testEnv.authenticatedContext('stranger').firestore();
    await assertFails(getDoc(doc(stranger, 'child_profiles/cp1/access_requests/existing')));
  });

  it('prevents children and guardians from altering the request-limit metadata', async () => {
    await seedFamily();
    for (const uid of ['child1', 'parent1']) {
      const db = testEnv.authenticatedContext(uid).firestore();
      const lock = doc(db, 'child_profiles/cp1/request_limits/app_access');
      await assertFails(getDoc(lock));
      await assertFails(setDoc(lock, { updatedAt: serverTimestamp() }));
    }
  });

  it('continues to allow normal chat messages without a cooldown', async () => {
    await seedFamily();
    const child = testEnv.authenticatedContext('child1').firestore();
    for (const id of ['message1', 'message2']) {
      await assertSucceeds(setDoc(doc(child, 'child_profiles/cp1/chat_messages/' + id), {
        senderId: 'child1',
        body: 'Hello!',
        createdAt: serverTimestamp(),
        notificationState: 'pending',
      }));
    }
  });
});
