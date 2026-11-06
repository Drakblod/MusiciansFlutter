import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/city_location.dart';

class CityCandidate {
  final String placeId;
  final String city;
  final String country;
  final String? region;
  const CityCandidate({
    required this.placeId,
    required this.city,
    required this.country,
    this.region,
  });
  String get label => region == null || region!.isEmpty
      ? '$city, $country'
      : '$city, $region, $country';
}

abstract class CitySearchProvider {
  Future<String> createSession();
  Future<List<CityCandidate>> search(String query, String sessionToken);
  Future<CityLocation?> resolve(CityCandidate candidate, String sessionToken, {
    required String purpose,
    required String targetId,
    required String city,
    required String country,
  });
}

/// Calls a server-side Places proxy. No Places key enters the Flutter bundle.
class GooglePlacesCitySearchProvider implements CitySearchProvider {
  const GooglePlacesCitySearchProvider();
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  @override
  Future<String> createSession() async {
    final result=await _functions.httpsCallable('startCatalogueCitySession')
        .call<Map<Object?,Object?>>({});
    final token=result.data['sessionToken'];
    if(token is! String || token.isEmpty)throw StateError('City session unavailable.');
    return token;
  }

  @override
  Future<List<CityCandidate>> search(String query, String sessionToken) async {
    final result = await _functions
        .httpsCallable('searchCatalogueCities')
        .call<Map<Object?, Object?>>({
          'query': query,
          'sessionToken': sessionToken,
        });
    final rows = result.data['candidates'];
    if (rows is! List) return [];
    return rows
        .whereType<Map>()
        .map(
          (row) => CityCandidate(
            placeId: row['placeId'] as String,
            city: row['city'] as String,
            country: row['country'] as String,
            region: row['region'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<CityLocation?> resolve(
    CityCandidate candidate,
    String sessionToken,
    {required String purpose, required String targetId,
    required String city, required String country}
  ) async {
    final result = await _functions
        .httpsCallable('resolveCatalogueCity')
        .call<Map<Object?, Object?>>({
          'placeId': candidate.placeId,
          'sessionToken': sessionToken,
          'purpose': purpose,
          'targetId': targetId,
          'city': city,
          'country': country,
        });
    final confirmed=CityLocation.fromJson(result.data['location']);
    final nonce=result.data['nonce'];
    if(confirmed==null || nonce is! String || nonce.isEmpty)return null;
    final credits=<CityAttribution>[];
    final rawCredits=result.data['attributions'];
    if(rawCredits is List){
      for(final raw in rawCredits){
        if(raw is! Map || raw['provider'] is! String)continue;
        final provider=(raw['provider'] as String).trim();
        if(provider.isEmpty)continue;
        final link=raw['providerUri'] is String
            ? Uri.tryParse(raw['providerUri'] as String) : null;
        credits.add(CityAttribution(provider,
            link?.scheme=='https' ? link : null));
      }
    }
    return CityLocation.confirmed(city:confirmed.city,region:confirmed.region,
      country:confirmed.country,countryCode:confirmed.countryCode,
      confirmationNonce:nonce,attributions:credits);
  }
}

String newCitySearchSessionToken() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
