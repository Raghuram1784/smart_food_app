String formatPaise(int paise) => paise % 100 == 0
    ? '${paise ~/ 100}'
    : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

class Restaurant {
  final String id, name, cuisine, description, image, time;
  final double rating;
  final int? startingPricePaise;
  final String operatingStatus;
  final bool deliveryAvailable;
  final String? localityName;
  final List<String> serviceAreaNames;
  const Restaurant(
    this.id,
    this.name,
    this.cuisine,
    this.description,
    this.image,
    this.time,
    this.rating, {
    this.startingPricePaise,
    this.operatingStatus = 'OPEN',
    this.deliveryAvailable = false,
    this.localityName,
    this.serviceAreaNames = const [],
  });
  factory Restaurant.fromJson(Map<String, dynamic> j) {
    final locality = j['locality'];
    final areas = j['serviceAreas'];
    return Restaurant(
      j['id'] as String,
      j['name'] as String,
      j['cuisineDescription'] as String,
      j['description'] as String,
      j['imageKey'] as String,
      "${j['estimatedDeliveryMinutes']}–${j['estimatedDeliveryMaxMinutes']} min",
      (j['rating'] as num).toDouble(),
      startingPricePaise: j['startingPricePaise'] as int?,
      operatingStatus: (j['operatingStatus'] as String?) ?? 'OPEN',
      deliveryAvailable: (j['deliveryAvailability'] as bool?) ?? false,
      localityName: locality is Map ? locality['name'] as String? : null,
      serviceAreaNames: areas is List
          ? areas
                .map((a) => a is Map ? a['name'] as String? : a?.toString())
                .whereType<String>()
                .toList()
          : const [],
    );
  }
}

class DishOption {
  final String id, name;
  final int pricePaise;
  final bool available;
  const DishOption(this.id, this.name, this.pricePaise, this.available);
  factory DishOption.fromJson(Map<String, dynamic> j, bool variant) =>
      DishOption(
        j['id'] as String,
        j['name'] as String,
        j[variant ? 'priceAdjustmentPaise' : 'pricePaise'] as int,
        j['isAvailable'] as bool,
      );
}

class Dish {
  final String id, restaurantId, name, description, category, image, section;
  // Offline fixture retains its original whole-rupee constructor; live money stays in paise.
  final int price;
  final int? _apiPricePaise;
  final String availabilityStatus, restaurantName;
  final String? availabilityReason;
  final bool? isVegetarian;
  final List<String> variants, addOns;
  final List<DishOption> variantOptions, addOnOptions;
  int get pricePaise => _apiPricePaise ?? price * 100;
  String get displayPrice => formatPaise(pricePaise);
  String get photoKey => photoKeyFor(image, name);
  static String photoKeyFor(String imageKey, String dishName) {
    final lower = dishName.toLowerCase();
    if (imageKey == 'dosa') {
      if (lower.contains('nellore karam')) return 'karam-dosa';
      if (lower.contains('rava') ||
          lower.contains('uttapam') ||
          lower.contains('pesarattu') ||
          lower.contains('plain dosa')) {
        return 'uttapam';
      }
    }
    if (imageKey == 'idli' &&
        lower.contains('vada') &&
        !lower.contains('idli')) {
      return 'vada';
    }
    if ((imageKey == 'meals' || imageKey == 'paneer') &&
        (lower.contains('dal') || lower.contains('chole'))) {
      return 'dal-curry';
    }
    if (lower.contains('naan') ||
        lower.contains('paratha') ||
        lower.contains('roti') ||
        lower.contains('bread basket')) {
      return 'roti-naan';
    }
    if (imageKey == 'chai' &&
        (lower.contains('lassi') ||
            lower.contains('shake') ||
            lower.contains('cold brew') ||
            lower.contains('iced') ||
            lower.contains('badam'))) {
      return 'cold-beverage';
    }
    return imageKey;
  }

  const Dish(
    this.id,
    this.restaurantId,
    this.name,
    this.description,
    this.category,
    this.image,
    this.price,
    this.section, {
    int? pricePaise,
    this.availabilityStatus = 'AVAILABLE',
    this.restaurantName = '',
    this.availabilityReason,
    this.isVegetarian,
    this.variantOptions = const [],
    this.addOnOptions = const [],
    this.variants = const [],
    this.addOns = const [],
  }) : _apiPricePaise = pricePaise;
  factory Dish.fromJson(Map<String, dynamic> j) => Dish(
    j['id'] as String,
    j['restaurantId'] as String,
    j['name'] as String,
    j['description'] as String,
    j['category']['name'] as String,
    j['imageKey'] as String,
    (j['basePricePaise'] as int) ~/ 100,
    j['section']['name'] as String,
    pricePaise: j['basePricePaise'] as int,
    availabilityStatus: j['availabilityStatus'] as String,
    restaurantName: j['restaurant']['name'] as String,
    availabilityReason: j['availabilityReason'] as String?,
    isVegetarian: j['isVegetarian'] as bool?,
    variantOptions: (j['variants'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((v) => DishOption.fromJson(v, true))
        .toList(),
    addOnOptions: (j['addOns'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((v) => DishOption.fromJson(v, false))
        .toList(),
    variants: _parseVariants(j['variants']),
    addOns: _parseAddOns(j['addOns']),
  );

  static List<String> _parseVariants(dynamic raw) {
    if (raw is! List) return const [];
    final result = <String>[];
    for (final item in raw) {
      if (item is String) {
        result.add(item);
      } else if (item is Map) {
        final name = item['name'] as String?;
        if (name == null) continue;
        final adj = (item['priceAdjustmentPaise'] as num?)?.toInt() ?? 0;
        final label = adj > 0
            ? '$name (+₹${formatPaise(adj)})'
            : adj < 0
            ? '$name (-₹${formatPaise(-adj)})'
            : name;
        result.add(
          item['isAvailable'] == false ? '$label · unavailable' : label,
        );
      }
    }
    return result;
  }

  static List<String> _parseAddOns(dynamic raw) {
    if (raw is! List) return const [];
    final result = <String>[];
    for (final item in raw) {
      if (item is String) {
        result.add(item);
      } else if (item is Map) {
        final map = item['addOn'] is Map ? item['addOn'] as Map : item;
        final name = map['name'] as String?;
        if (name == null) continue;
        final price = (map['pricePaise'] as num?)?.toInt() ?? 0;
        final label = price > 0 ? '$name (+₹${formatPaise(price)})' : name;
        result.add(
          map['isAvailable'] == false ? '$label · unavailable' : label,
        );
      }
    }
    return result;
  }
}

const restaurants = [
  Restaurant(
    'tiffin',
    'The Tiffin Room',
    'Indian · Vegetarian kitchen',
    'Crisp dosas, comforting curries and everyday Indian favourites. A little taste of home, made with care.',
    'dosa',
    '20–30 min',
    4.8,
  ),
  Restaurant(
    'hearth',
    'Hearth & Crust',
    'Italian · Wood-fired kitchen',
    'Slow dough. A little fire. A lot of soul. Discover a small menu of comforting Italian favourites.',
    'pizza',
    '25–35 min',
    4.8,
  ),
  Restaurant(
    'table',
    'The Green Table',
    'Mediterranean · Fresh bowls',
    'Bright produce, generous bowls and simple ingredients that speak for themselves.',
    'salad',
    '20–30 min',
    4.7,
  ),
  Restaurant(
    'bun',
    'Bun & Beyond',
    'American · Burgers',
    'Properly stacked burgers, toasted buns and familiar flavours, made for a good lunch.',
    'burger',
    '25–40 min',
    4.6,
  ),
];
const dishes = [
  Dish(
    'pizza',
    'hearth',
    'Wood-fired pepperoni',
    'Pepperoni, melted mozzarella and tomato on a crisp, golden crust.',
    'Pizza',
    'pizza',
    349,
    'From the oven',
  ),
  Dish(
    'pasta',
    'hearth',
    'Tomato & basil penne',
    'Penne tossed in a rich tomato sauce with fresh basil and herbs.',
    'Pasta',
    'pasta',
    229,
    'Comfort classics',
  ),
  Dish(
    'salad',
    'table',
    'Mediterranean garden bowl',
    'Crisp greens, tomato, olives and creamy feta with a light dressing.',
    'Bowls',
    'salad',
    199,
    'Freshly prepared',
  ),
  Dish(
    'burger',
    'bun',
    'Signature cheeseburger',
    'A beef patty, bacon, melted cheese, tomato and greens in a toasted sesame bun.',
    'Burgers',
    'burger',
    249,
    'House favourites',
  ),
  Dish(
    'dosa',
    'tiffin',
    'Masala dosa',
    'Golden rice-and-lentil dosa with a spiced potato filling, coconut chutney and sambar.',
    'Dosa',
    'dosa',
    149,
    'From the griddle',
  ),
  Dish(
    'idli',
    'tiffin',
    'Vegetable idli',
    'Soft vegetable-studded idli served with coconut and tomato chutneys.',
    'Idli',
    'idli',
    119,
    'Tiffin favourites',
  ),
  Dish(
    'biryani',
    'tiffin',
    'Vegetable biryani',
    'Fragrant spiced rice with carrots, peas and green beans.',
    'Biryani',
    'biryani',
    229,
    'Comfort classics',
  ),
  Dish(
    'paneer',
    'tiffin',
    'Paneer pepper masala',
    'Paneer and bell peppers in a rich spiced gravy, finished with cream.',
    'Paneer',
    'paneer',
    279,
    'Comfort classics',
  ),
];
const categories = {
  'Dosa': 'dosa',
  'Idli': 'idli',
  'Biryani': 'biryani',
  'Paneer': 'paneer',
  'Pizza': 'pizza',
  'Burgers': 'burger',
  'Pasta': 'pasta',
  'Bowls': 'salad',
};
Restaurant restaurantFor(String id) =>
    restaurants.firstWhere((r) => r.id == id);
List<Dish> searchDishes(
  String query,
  String? category, {
  bool affordable = false,
}) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
  return dishes.where((d) {
    final r = restaurantFor(d.restaurantId);
    final text =
        '${d.name} ${d.description} ${d.category} ${r.name} ${r.cuisine}'
            .toLowerCase();
    return words.every(text.contains) &&
        (category == null || d.category == category) &&
        (!affordable || d.price <= 250);
  }).toList();
}
