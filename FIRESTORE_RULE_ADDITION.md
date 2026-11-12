# Parent read access to the monitoring-alert inbox

The existing monitoring backend writes alert records to
`child_profiles/{childProfileId}/monitoring_alerts/{alertId}` with fields
`parentId`, `title`, `body`, `kind`, `createdAt`, `pushStatus`, and `smsStatus`.

You **must** add the following NESTED block INSIDE your existing
`match /child_profiles/{childProfileId}` block in `firestore.rules`:

```javascript
match /monitoring_alerts/{alertId} {
  // Authorize using the owner of the enclosing child profile.
  // The profile path is fixed for this query, unlike fields on the alerts.
  // Do not allow clients to create, modify, or delete these records.
  allow get, list: if request.auth != null &&
      get(/databases/$(database)/documents/child_profiles/$(childProfileId))
          .data.parentId == request.auth.uid;
  allow create, update, delete: if false;
}
```

Keep your existing parent/child profile rules and their other nested matches.
The Firebase Admin SDK used by FastAPI can still write these documents,
because it bypasses Security Rules. Before deploying, test that the paired
parent can read, another authenticated user cannot read, and a child cannot
forge or delete a notification. The inbox queries each child's subcollection
using `.orderBy('createdAt', descending: true).limit(100)`, and requires the
usual Firestore single-field index for `createdAt` (normally automatic).

**Important:** Do not replace this rule with just
`resource.data.parentId == request.auth.uid` unless the query itself filters
on that field. Firestore security rules are not result filters. The fixed
parent-profile document lookup above authorizes the scoped child alert list.
Make sure the existing rules protect the `parentId` field against unauthorized
modification.

This rule enables history for the new **server-authored monitoring events**.
Other existing FCM notifications are not retroactively saved to this
collection unless their existing sender also persists matching alert records.
