class Listing {
  final String? id;
  final String? userId;
  final String? title;
  final String? description;
  final String? category;
  final String? listingType; // sell, buy, rent, service
  final String? marketplaceIntent; // looking_for, offering
  final String? marketplaceCategory; // stable internal category ID
  final double price;
  final String? city;
  final List<String> imageUrls;
  final String status; // active, sold, inactive, deleted
  final int createdAt;
  final int updatedAt;

  Listing({
    this.id,
    this.userId,
    this.title,
    this.description,
    this.category,
    this.listingType,
    this.marketplaceIntent,
    this.marketplaceCategory,
    this.price = 0.0,
    this.city,
    this.imageUrls = const [],
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
  });

  String get effectiveIntent {
    if (marketplaceIntent != null && marketplaceIntent!.isNotEmpty) {
      return marketplaceIntent!;
    }
    if (listingType == 'buy') {
      return 'looking_for';
    }
    return 'offering';
  }

  String get effectiveCategory {
    if (marketplaceCategory != null && marketplaceCategory!.isNotEmpty) {
      return marketplaceCategory!;
    }
    // Fallback from legacy category
    switch (category) {
      case 'Instruments':
      case 'Amps & Effects':
        return 'instrument_gear';
      case 'Studio & Recording':
        return effectiveIntent == 'looking_for' ? 'studio' : 'recording_production';
      case 'Rehearsal Spaces':
        return 'rehearsal_space';
      case 'Music Services':
        return 'music_services';
      case 'Other':
      default:
        return 'other_services';
    }
  }

  factory Listing.fromJson(Map<dynamic, dynamic> json, String keyId) {
    final rawUrls = json['imageUrls'] ?? json['ImageUrls'];
    List<String> urls = [];
    if (rawUrls is List) {
      urls = rawUrls.map((e) => e.toString()).toList();
    } else if (rawUrls is Map) {
      urls = rawUrls.values.map((e) => e.toString()).toList();
    }

    double parsedPrice = 0.0;
    final priceRaw = json['price'] ?? json['Price'];
    if (priceRaw is num) {
      parsedPrice = priceRaw.toDouble();
    }

    return Listing(
      id: keyId,
      userId: (json['userId'] ?? json['UserId'])?.toString(),
      title: (json['title'] ?? json['Title'])?.toString(),
      description: (json['description'] ?? json['Description'])?.toString(),
      category: (json['category'] ?? json['Category'])?.toString(),
      listingType: (json['listingType'] ?? json['ListingType'])?.toString(),
      marketplaceIntent: (json['marketplaceIntent'] ?? json['MarketplaceIntent'])?.toString(),
      marketplaceCategory: (json['marketplaceCategory'] ?? json['MarketplaceCategory'])?.toString(),
      price: parsedPrice,
      city: (json['city'] ?? json['City'])?.toString(),
      imageUrls: urls,
      status: (json['status'] ?? json['Status'])?.toString() ?? 'active',
      createdAt: json['createdAt'] is int ? json['createdAt'] as int : (json['CreatedAt'] is int ? json['CreatedAt'] as int : 0),
      updatedAt: json['updatedAt'] is int ? json['updatedAt'] as int : (json['UpdatedAt'] is int ? json['UpdatedAt'] as int : 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'description': description,
      'category': category,
      'listingType': listingType,
      'marketplaceIntent': marketplaceIntent,
      'marketplaceCategory': marketplaceCategory,
      'price': price,
      'city': city,
      'imageUrls': imageUrls,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
