/**
 * WellScreen Firebase Cloud Functions
 *
 * Child device notifications for app time limits
 * and newly blocked applications.
 */

exports.notifyChildAppTimeLimit =
  require('./child_app_time_limit_notifications').notifyChildAppTimeLimit;

exports.notifyChildBlockedApps =
  require('./child_blocked_app_notifications').notifyChildBlockedApps;