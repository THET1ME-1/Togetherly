import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Test ad unit IDs from Google for development.
/// Replace [adUnitId] with your real AdMob unit ID before release.
const String _testBannerAdUnit = 'ca-app-pub-3940256099942544/6300978111';

/// A self-disposing banner ad that loads once and shows between content.
/// Produces nothing on web, desktop, or when the ad fails to load.
class AdBanner extends StatefulWidget {
  final String adUnitId;

  /// The ad unit ID for this banner. Leave empty to use the test unit.
  final double height;

  const AdBanner({
    super.key,
    this.adUnitId = '',
    this.height = 50,
  });

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  void _loadAd() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final unitId = widget.adUnitId.isNotEmpty
        ? widget.adUnitId
        : (kDebugMode ? _testBannerAdUnit : '');

    if (unitId.isEmpty) return;

    BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad as BannerAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('AdBanner failed to load: $error');
        },
      ),
    ).load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();

    return Container(
      height: widget.height,
      alignment: Alignment.center,
      child: AdWidget(ad: _ad!),
    );
  }
}
