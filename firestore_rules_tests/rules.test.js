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


// ---------------------------------------------------------------------
// pairing_codes/{code}
// ---------------------------------------------------------------------


// ---------------------------------------------------------------------
// app_rules/{parentId}
// ---------------------------------------------------------------------


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


describe('Task 5 - Secure pairing and family access', () => {
  function client(uid) {
    return uid === null
      ? testEnv.unauthenticatedContext().firestore()
      : testEnv.authenticatedContext(uid).firestore();
  }

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();

      await Promise.all([
        setDoc(doc(db, 'users/parent1'), {
          uid: 'parent1',
          role: 'parent',
        }),

        setDoc(doc(db, 'users/parent2'), {
          uid: 'parent2',
          role: 'parent',
        }),

        setDoc(doc(db, 'users/child1'), {
          uid: 'child1',
          role: 'child',
          pairedParentId: 'parent1',
          pairedChildProfileId: 'profile1',
          pairingStatus: 'connected',
        }),

        setDoc(doc(db, 'users/child2'), {
          uid: 'child2',
          role: 'child',
          pairingStatus: 'not_paired',
          pairedParentId: null,
          pairedChildProfileId: null,
        }),

        setDoc(doc(db, 'child_profiles/profile1'), {
          id: 'profile1',
          parentId: 'parent1',
          childAccountId: 'child1',
          pairingStatus: 'connected',
          name: 'Test Child',
        }),

        setDoc(doc(db, 'child_profiles/waiting1'), {
          id: 'waiting1',
          parentId: 'parent1',
          pairingStatus: 'waiting',
        }),

        setDoc(doc(db, 'pairing_codes/123456'), {
          code: '123456',
          parentId: 'parent1',
          childId: 'waiting1',
          status: 'active',
        }),

        setDoc(doc(db, 'pairing_attempt_limits/child1'), {
          count: 1,
        }),

        setDoc(doc(db, 'app_rules/parent1'), {
          parentId: 'parent1',
          rules: [],
        }),

        setDoc(doc(db, 'restriction_settings/settings1'), {
          parentId: 'parent1',
          enabled: true,
        }),
      ]);
    });
  });

  // Pairing codes are accessible only through FastAPI.

  it.each(['parent1', 'child1', 'child2', null])(
    'denies direct pairing code reads for %s',
    async (uid) => {
      await assertFails(
        getDoc(doc(client(uid), 'pairing_codes/123456'))
      );
    }
  );

  it('denies parent creating pairing codes directly', async () => {
    await assertFails(
      setDoc(doc(client('parent1'), 'pairing_codes/654321'), {
        parentId: 'parent1',
        childId: 'waiting1',
        status: 'active',
      })
    );
  });

  it('denies child redeeming pairing codes directly', async () => {
    await assertFails(
      updateDoc(doc(client('child2'), 'pairing_codes/123456'), {
        status: 'connected',
        childAccountId: 'child2',
      })
    );
  });

  it('denies reading pairing attempt counters', async () => {
    await assertFails(
      getDoc(doc(client('child1'), 'pairing_attempt_limits/child1'))
    );
  });

  it('denies resetting pairing attempt counters', async () => {
    await assertFails(
      updateDoc(
        doc(client('child1'), 'pairing_attempt_limits/child1'),
        { count: 0 }
      )
    );
  });

  // User account security.

  it('allows normal child registration', async () => {
    await assertSucceeds(
      setDoc(doc(client('newChild'), 'users/newChild'), {
        uid: 'newChild',
        role: 'child',
        pairingStatus: 'not_paired',
        pairedParentId: null,
        pairedChildProfileId: null,
      })
    );
  });

  it('denies registration with forged pairing fields', async () => {
    await assertFails(
      setDoc(doc(client('newChild'), 'users/newChild'), {
        uid: 'newChild',
        role: 'child',
        pairingStatus: 'connected',
        pairedParentId: 'parent1',
        pairedChildProfileId: 'profile1',
      })
    );
  });

  it('denies child changing paired parent', async () => {
    await assertFails(
      updateDoc(doc(client('child1'), 'users/child1'), {
        pairedParentId: 'parent2',
      })
    );
  });

  it('denies child changing paired profile', async () => {
    await assertFails(
      updateDoc(doc(client('child1'), 'users/child1'), {
        pairedChildProfileId: 'waiting1',
      })
    );
  });

  it('denies child changing pairing status', async () => {
    await assertFails(
      updateDoc(doc(client('child1'), 'users/child1'), {
        pairingStatus: 'not_paired',
      })
    );
  });

  it('allows normal user profile updates', async () => {
    await assertSucceeds(
      updateDoc(doc(client('child1'), 'users/child1'), {
        fullName: 'Updated Name',
      })
    );
  });

  // Child profile security.

  it('allows owning parent to read child profile', async () => {
    await assertSucceeds(
      getDoc(doc(client('parent1'), 'child_profiles/profile1'))
    );
  });

  it('allows paired child to read own profile', async () => {
    await assertSucceeds(
      getDoc(doc(client('child1'), 'child_profiles/profile1'))
    );
  });

  it('denies unrelated parent reading child profile', async () => {
    await assertFails(
      getDoc(doc(client('parent2'), 'child_profiles/profile1'))
    );
  });

  it('denies unrelated child reading child profile', async () => {
    await assertFails(
      getDoc(doc(client('child2'), 'child_profiles/profile1'))
    );
  });

  it('denies direct child profile creation', async () => {
    await assertFails(
      setDoc(doc(client('parent1'), 'child_profiles/newProfile'), {
        parentId: 'parent1',
        pairingStatus: 'waiting',
      })
    );
  });

  it('denies claiming an unpaired child profile directly', async () => {
    await assertFails(
      updateDoc(doc(client('child2'), 'child_profiles/waiting1'), {
        childAccountId: 'child2',
        pairingStatus: 'connected',
      })
    );
  });

  it('denies parent replacing paired child identity', async () => {
    await assertFails(
      updateDoc(doc(client('parent1'), 'child_profiles/profile1'), {
        childAccountId: 'child2',
      })
    );
  });

  it('denies parent changing profile ownership', async () => {
    await assertFails(
      updateDoc(doc(client('parent1'), 'child_profiles/profile1'), {
        parentId: 'parent2',
      })
    );
  });

  it('denies child changing parent identity information', async () => {
    await assertFails(
      updateDoc(doc(client('child1'), 'child_profiles/profile1'), {
        parentDisplayName: 'Forged Name',
      })
    );
  });

  it('allows parent updating normal child profile information', async () => {
    await assertSucceeds(
      updateDoc(doc(client('parent1'), 'child_profiles/profile1'), {
        parentDisplayName: 'Updated Parent Name',
      })
    );
  });

  it('allows paired child updating display name', async () => {
    await assertSucceeds(
      updateDoc(doc(client('child1'), 'child_profiles/profile1'), {
        childDisplayName: 'Updated Child Name',
      })
    );
  });

  // Application rules.

  it('allows parent reading own app rules', async () => {
    await assertSucceeds(
      getDoc(doc(client('parent1'), 'app_rules/parent1'))
    );
  });

  it('allows verified paired child reading parent app rules', async () => {
    await assertSucceeds(
      getDoc(doc(client('child1'), 'app_rules/parent1'))
    );
  });

  it.each(['parent2', 'child2', null])(
    'denies unauthorized app rules access for %s',
    async (uid) => {
      await assertFails(
        getDoc(doc(client(uid), 'app_rules/parent1'))
      );
    }
  );

  it('allows parent updating own app rules', async () => {
    await assertSucceeds(
      updateDoc(doc(client('parent1'), 'app_rules/parent1'), {
        rules: [],
      })
    );
  });

  it('denies child updating parent app rules', async () => {
    await assertFails(
      updateDoc(doc(client('child1'), 'app_rules/parent1'), {
        rules: [],
      })
    );
  });

  it('denies another parent updating app rules', async () => {
    await assertFails(
      updateDoc(doc(client('parent2'), 'app_rules/parent1'), {
        rules: [],
      })
    );
  });

  // Restriction settings.

  it('allows parent reading own restriction settings', async () => {
    await assertSucceeds(
      getDoc(doc(client('parent1'), 'restriction_settings/settings1'))
    );
  });

  it('allows paired child reading restriction settings', async () => {
    await assertSucceeds(
      getDoc(doc(client('child1'), 'restriction_settings/settings1'))
    );
  });

  it.each(['parent2', 'child2', null])(
    'denies unauthorized restriction settings access for %s',
    async (uid) => {
      await assertFails(
        getDoc(doc(client(uid), 'restriction_settings/settings1'))
      );
    }
  );

  it('denies child modifying restriction settings', async () => {
    await assertFails(
      updateDoc(
        doc(client('child1'), 'restriction_settings/settings1'),
        { enabled: false }
      )
    );
  });
});
