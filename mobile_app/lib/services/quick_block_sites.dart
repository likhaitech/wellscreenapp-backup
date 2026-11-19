/// One-tap website blocks for popular apps, shown on the guardian's Rules
/// screen. Blocks the app's websites even when the child never installed
/// the app (or uninstalled it). Same websites as the native list in
/// RelatedTargets.kt, which blocks them automatically when the app itself
/// is blocked.
class QuickBlockSite {
  const QuickBlockSite(this.name, this.domains);

  final String name;
  final List<String> domains;

  /// True when every website of this app is already on [blockedDomains].
  bool isBlockedIn(List<String> blockedDomains) =>
      domains.every(blockedDomains.contains);
}

const List<QuickBlockSite> quickBlockSites = [
  QuickBlockSite('TikTok', ['tiktok.com']),
  QuickBlockSite('Facebook', ['facebook.com', 'fb.com', 'fb.watch']),
  QuickBlockSite('Messenger', ['messenger.com']),
  QuickBlockSite('Instagram', ['instagram.com']),
  QuickBlockSite('YouTube', ['youtube.com', 'youtu.be']),
  QuickBlockSite('X (Twitter)', ['twitter.com', 'x.com']),
  QuickBlockSite('Roblox', ['roblox.com']),
  QuickBlockSite('Snapchat', ['snapchat.com']),
  QuickBlockSite('Discord', ['discord.com', 'discord.gg', 'discordapp.com']),
  QuickBlockSite('Reddit', ['reddit.com', 'redd.it']),
  QuickBlockSite('Twitch', ['twitch.tv']),
];
