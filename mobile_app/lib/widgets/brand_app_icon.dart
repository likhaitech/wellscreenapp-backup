import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The real icon of an app or website, wherever one is shown.
///
/// Tries, in order:
/// 1. [iconBase64]: the icon Android gives for the app installed on the
///    child's phone (synced in the usage report / looked up on the child).
/// 2. A bundled icon in assets/icons for a few common apps.
/// 3. The site's own icon (favicon), loaded on the phone, for a [domain] or
///    for a well-known app's package. This covers Quick block apps and
///    blocked websites that aren't installed.
/// 4. The first letter of [label] as a last resort (no internet, unknown
///    app).
class BrandAppIcon extends StatelessWidget {
  const BrandAppIcon({
    super.key,
    required this.label,
    this.packageName,
    this.domain,
    this.iconBase64,
    this.size = 40,
    this.radius,
  });

  final String label;
  final String? packageName;
  final String? domain;
  final String? iconBase64;
  final double size;
  final double? radius;

  /// Well-known apps -> their website, so a not-yet-synced app still gets
  /// its real icon. Mirrors RelatedTargets.kt / quick_block_sites.dart.
  static const Map<String, String> packageDomains = {
    'com.zhiliaoapp.musically': 'tiktok.com',
    'com.ss.android.ugc.trill': 'tiktok.com',
    'com.zhiliaoapp.musically.go': 'tiktok.com',
    'com.google.android.youtube': 'youtube.com',
    'com.google.android.apps.youtube.kids': 'youtubekids.com',
    'com.facebook.katana': 'facebook.com',
    'com.facebook.lite': 'facebook.com',
    'com.facebook.orca': 'messenger.com',
    'com.facebook.mlite': 'messenger.com',
    'com.instagram.android': 'instagram.com',
    'com.instagram.lite': 'instagram.com',
    'com.twitter.android': 'x.com',
    'com.roblox.client': 'roblox.com',
    'com.snapchat.android': 'snapchat.com',
    'com.discord': 'discord.com',
    'com.reddit.frontpage': 'reddit.com',
    'tv.twitch.android.app': 'twitch.tv',
    'com.mobile.legends': 'mobilelegends.com',
    'com.android.chrome': 'google.com',
    'com.google.android.gm': 'mail.google.com',
    'com.whatsapp': 'whatsapp.com',
    'com.spotify.music': 'spotify.com',
    'com.netflix.mediaclient': 'netflix.com',
  };

  /// Quick block names -> website.
  static const Map<String, String> nameDomains = {
    'tiktok': 'tiktok.com',
    'facebook': 'facebook.com',
    'messenger': 'messenger.com',
    'instagram': 'instagram.com',
    'youtube': 'youtube.com',
    'x (twitter)': 'x.com',
    'roblox': 'roblox.com',
    'snapchat': 'snapchat.com',
    'discord': 'discord.com',
    'reddit': 'reddit.com',
    'twitch': 'twitch.tv',
  };

  /// Icons that ship with the app (assets/icons), by website.
  static const Map<String, String> bundled = {
    'tiktok.com': 'assets/icons/tiktok.png',
    'youtube.com': 'assets/icons/youtube.png',
    'instagram.com': 'assets/icons/instagram.png',
    'roblox.com': 'assets/icons/roblox.png',
    'discord.com': 'assets/icons/discord.png',
  };

  /// The website whose icon stands for this app or site, if any.
  static String? domainFor({
    String? packageName,
    String? domain,
    String? label,
  }) {
    final d = domain?.trim().toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (d != null && d.isNotEmpty) return d;
    final fromPackage = packageDomains[packageName?.trim()];
    if (fromPackage != null) return fromPackage;
    return nameDomains[label?.trim().toLowerCase()];
  }

  /// Favicon address for [domain] (PNG, sized for a sharp 48 px tile).
  static String faviconUrl(String domain) =>
      'https://www.google.com/s2/favicons?domain=${Uri.encodeComponent(domain)}&sz=128';

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size * 0.28;
    final letter = _letterTile(r);
    Widget? image;

    final encoded = iconBase64;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        image = Image.memory(
          base64Decode(encoded),
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => letter,
        );
      } on FormatException {
        image = null;
      }
    }

    final site = domainFor(packageName: packageName, domain: domain, label: label);
    if (image == null && site != null) {
      final asset = bundled[site];
      if (asset != null) {
        image = Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => letter,
        );
      } else {
        image = Padding(
          padding: EdgeInsets.all(size * 0.16),
          child: Image.network(
            faviconUrl(site),
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => letter,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : letter,
          ),
        );
      }
    }

    return Semantics(
      label: '$label icon',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: SizedBox(
          width: size,
          height: size,
          child: image == null
              ? letter
              : ColoredBox(color: AppColors.surface, child: image),
        ),
      ),
    );
  }

  Widget _letterTile(double r) {
    final text = label.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(r),
      ),
      child: Text(
        text.isEmpty ? '?' : text.characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: AppFonts.heading,
          color: AppColors.primary,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
