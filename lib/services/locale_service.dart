import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleConfig {
  final String countryCode;
  final String countryName;
  final String currencyCode;
  final String currencySymbol;
  final String locale;
  final bool useMetric;
  final String emoji;

  const LocaleConfig({
    required this.countryCode,
    required this.countryName,
    required this.currencyCode,
    required this.currencySymbol,
    required this.locale,
    required this.useMetric,
    required this.emoji,
  });
}

class LocaleService extends ChangeNotifier {
  static const _storageKey = 'lobohub_locale';

  LocaleConfig _config = LocaleService.defaultConfig;

  LocaleConfig get config => _config;

  static const defaultConfig = LocaleConfig(
    countryCode: 'US',
    countryName: 'United States',
    currencyCode: 'USD',
    currencySymbol: '\$',
    locale: 'en_US',
    useMetric: false,
    emoji: '🇺🇸',
  );

  static const List<LocaleConfig> allCountries = [
    // English-speaking / North America
    LocaleConfig(
      countryCode: 'US',
      countryName: 'United States',
      currencyCode: 'USD',
      currencySymbol: '\$',
      locale: 'en_US',
      useMetric: false,
      emoji: '🇺🇸',
    ),
    LocaleConfig(
      countryCode: 'GB',
      countryName: 'United Kingdom',
      currencyCode: 'GBP',
      currencySymbol: '£',
      locale: 'en_GB',
      useMetric: true,
      emoji: '🇬🇧',
    ),
    LocaleConfig(
      countryCode: 'CA',
      countryName: 'Canada',
      currencyCode: 'CAD',
      currencySymbol: 'CA\$',
      locale: 'en_CA',
      useMetric: true,
      emoji: '🇨🇦',
    ),
    LocaleConfig(
      countryCode: 'AU',
      countryName: 'Australia',
      currencyCode: 'AUD',
      currencySymbol: 'A\$',
      locale: 'en_AU',
      useMetric: true,
      emoji: '🇦🇺',
    ),
    LocaleConfig(
      countryCode: 'NZ',
      countryName: 'New Zealand',
      currencyCode: 'NZD',
      currencySymbol: 'NZ\$',
      locale: 'en_NZ',
      useMetric: true,
      emoji: '🇳🇿',
    ),
    LocaleConfig(
      countryCode: 'IE',
      countryName: 'Ireland',
      currencyCode: 'EUR',
      currencySymbol: '€',
      locale: 'en_IE',
      useMetric: true,
      emoji: '🇮🇪',
    ),
    // South/Southeast Asia
    LocaleConfig(
      countryCode: 'IN',
      countryName: 'India',
      currencyCode: 'INR',
      currencySymbol: '₹',
      locale: 'en_IN',
      useMetric: true,
      emoji: '🇮🇳',
    ),
    LocaleConfig(
      countryCode: 'PH',
      countryName: 'Philippines',
      currencyCode: 'PHP',
      currencySymbol: '₱',
      locale: 'en_PH',
      useMetric: true,
      emoji: '🇵🇭',
    ),
    LocaleConfig(
      countryCode: 'SG',
      countryName: 'Singapore',
      currencyCode: 'SGD',
      currencySymbol: 'S\$',
      locale: 'en_SG',
      useMetric: true,
      emoji: '🇸🇬',
    ),
    LocaleConfig(
      countryCode: 'MY',
      countryName: 'Malaysia',
      currencyCode: 'MYR',
      currencySymbol: 'RM',
      locale: 'ms_MY',
      useMetric: true,
      emoji: '🇲🇾',
    ),
    // Africa
    LocaleConfig(
      countryCode: 'NG',
      countryName: 'Nigeria',
      currencyCode: 'NGN',
      currencySymbol: '₦',
      locale: 'en_NG',
      useMetric: true,
      emoji: '🇳🇬',
    ),
    LocaleConfig(
      countryCode: 'ZA',
      countryName: 'South Africa',
      currencyCode: 'ZAR',
      currencySymbol: 'R',
      locale: 'en_ZA',
      useMetric: true,
      emoji: '🇿🇦',
    ),
    LocaleConfig(
      countryCode: 'KE',
      countryName: 'Kenya',
      currencyCode: 'KES',
      currencySymbol: 'KSh',
      locale: 'en_KE',
      useMetric: true,
      emoji: '🇰🇪',
    ),
    LocaleConfig(
      countryCode: 'GH',
      countryName: 'Ghana',
      currencyCode: 'GHS',
      currencySymbol: 'GH₵',
      locale: 'en_GH',
      useMetric: true,
      emoji: '🇬🇭',
    ),
    LocaleConfig(
      countryCode: 'ZW',
      countryName: 'Zimbabwe',
      currencyCode: 'USD',
      currencySymbol: '\$',
      locale: 'en_ZW',
      useMetric: true,
      emoji: '🇿🇼',
    ),
    // Caribbean
    LocaleConfig(
      countryCode: 'JM',
      countryName: 'Jamaica',
      currencyCode: 'JMD',
      currencySymbol: 'J\$',
      locale: 'en_JM',
      useMetric: true,
      emoji: '🇯🇲',
    ),
    LocaleConfig(
      countryCode: 'TT',
      countryName: 'Trinidad and Tobago',
      currencyCode: 'TTD',
      currencySymbol: 'TT\$',
      locale: 'en_TT',
      useMetric: true,
      emoji: '🇹🇹',
    ),
    LocaleConfig(
      countryCode: 'BB',
      countryName: 'Barbados',
      currencyCode: 'BBD',
      currencySymbol: 'Bds\$',
      locale: 'en_BB',
      useMetric: true,
      emoji: '🇧🇧',
    ),
    // Latin America
    LocaleConfig(
      countryCode: 'MX',
      countryName: 'Mexico',
      currencyCode: 'MXN',
      currencySymbol: 'MX\$',
      locale: 'es_MX',
      useMetric: true,
      emoji: '🇲🇽',
    ),
    LocaleConfig(
      countryCode: 'BR',
      countryName: 'Brazil',
      currencyCode: 'BRL',
      currencySymbol: 'R\$',
      locale: 'pt_BR',
      useMetric: true,
      emoji: '🇧🇷',
    ),
  ];

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_storageKey);
      if (savedCode != null) {
        final match = allCountries.firstWhere(
          (c) => c.countryCode == savedCode,
          orElse: () => defaultConfig,
        );
        _config = match;
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint('[LocaleService] init() error: $e\n$st');
    }
  }

  Future<void> setCountry(LocaleConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, config.countryCode);
      _config = config;
      notifyListeners();
    } catch (e, st) {
      debugPrint('[LocaleService] setCountry() error: $e\n$st');
    }
  }

  String formatCurrency(double amount) {
    try {
      return NumberFormat.simpleCurrency(
        locale: _config.locale,
        name: _config.currencyCode,
      ).format(amount);
    } catch (e) {
      return '${_config.currencySymbol}${amount.toStringAsFixed(2)}';
    }
  }

  String formatDate(DateTime date) {
    try {
      return DateFormat.yMMMd(_config.locale).format(date);
    } catch (e) {
      return date.toIso8601String().substring(0, 10);
    }
  }

  String formatDistance(double km) {
    if (_config.useMetric) {
      return '${km.toStringAsFixed(1)} km';
    } else {
      return '${(km * 0.621371).toStringAsFixed(1)} mi';
    }
  }

  String formatWeight(double kg) {
    if (_config.useMetric) {
      return '${kg.toStringAsFixed(1)} kg';
    } else {
      return '${(kg * 2.20462).toStringAsFixed(1)} lbs';
    }
  }
}
