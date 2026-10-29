import 'package:flutter/material.dart';

// ── MovieSeat data catalog: product models ──────────────────────────────
// Every item the app shows comes from a JSON array returned by the MovieSeat
// API (see catalog_service.dart). Each class below has a `fromJson` factory
// that maps ONE JSON object from that array onto a typed Dart object.

/// A movie in the "Now Showing" catalog (the app's main product).
class Movie {
  const Movie({
    required this.id,
    required this.title,
    required this.genre,
    required this.duration,
    required this.rating,
    required this.price,
    required this.synopsis,
    required this.showtimes,
    required this.colors,
    this.image = '',
  });

  final String id;
  final String image;
  final String title;
  final String genre;
  final String duration;
  final double rating;

  /// Ticket price per seat, in pesos.
  final double price;
  final String synopsis;
  final List<String> showtimes;

  /// Two colors for the poster gradient.
  final List<Color> colors;

  /// Maps one object from `movies.json` into a [Movie].
  factory Movie.fromJson(Map<String, dynamic> json) {
    final colors = (json['colors'] as List<dynamic>? ?? const [])
        .map((hex) => colorFromHex(hex as String?))
        .toList();

    return Movie(
      id: json['id'] as String? ?? '',
      image:
          json['image'] as String? ??
          defaultCatalogImage(json['id'] as String? ?? ''),
      title: json['title'] as String? ?? 'Untitled',
      genre: json['genre'] as String? ?? '',
      duration: json['duration'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      synopsis: json['synopsis'] as String? ?? '',
      showtimes: List<String>.from(json['showtimes'] as List? ?? const []),
      colors: colors.length >= 2
          ? colors
          : const [Color(0xFF312E81), Color(0xFF7C3AED)],
    );
  }

  /// Serialize a movie for POST and PUT requests.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'genre': genre,
    'duration': duration,
    'rating': rating,
    'price': price,
    'synopsis': synopsis,
    'showtimes': showtimes,
    'colors': colors.map(colorToHex).toList(),
    'image': image,
  };

  /// True when the movie's title or genre contains [query].
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) || genre.toLowerCase().contains(q);
  }
}

/// A snack or cinema service in the "Snacks & Services" catalog.
class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.price,
    required this.size,
    required this.available,
    required this.icon,
    this.iconKey = 'store',
    required this.color,
    this.image = '',
  });

  final String id;
  final String image;
  final String name;

  /// Snacks, Drinks, Combos or Services.
  final String category;
  final String description;
  final double price;

  /// e.g. "Large", "500 ml" or "Per seat". May be empty.
  final String size;
  final bool available;
  final IconData icon;
  final String iconKey;
  final Color color;

  /// Maps one object from `services.json` into a [ServiceItem].
  factory ServiceItem.fromJson(Map<String, dynamic> json) {
    return ServiceItem(
      id: json['id'] as String? ?? '',
      image:
          json['image'] as String? ??
          defaultCatalogImage(json['id'] as String? ?? ''),
      name: json['name'] as String? ?? 'Unnamed item',
      category: json['category'] as String? ?? 'Other',
      description: json['description'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      size: json['size'] as String? ?? '',
      available: json['available'] as bool? ?? true,
      icon: _iconFor(json['icon'] as String?),
      iconKey: json['icon'] as String? ?? 'store',
      color: colorFromHex(json['color'] as String?),
    );
  }

  /// Serialize a menu item while retaining its API icon key and color.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'description': description,
    'price': price,
    'size': size,
    'available': available,
    'icon': iconKey,
    'color': colorToHex(color),
    'image': image,
  };

  /// True when the item's name, category or description contains [query].
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q);
  }

  static IconData _iconFor(String? key) {
    switch (key) {
      case 'popcorn':
        return Icons.fastfood_rounded;
      case 'nachos':
        return Icons.lunch_dining_rounded;
      case 'drink':
        return Icons.local_drink_rounded;
      case 'coffee':
        return Icons.coffee_rounded;
      case 'dessert':
        return Icons.icecream_rounded;
      case 'combo':
        return Icons.restaurant_menu_rounded;
      case 'seat':
        return Icons.event_seat_rounded;
      case 'party':
        return Icons.celebration_rounded;
      case 'parking':
        return Icons.local_parking_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }
}

/// Turns "#RRGGBB" into a [Color]. Falls back to purple if it's missing or
/// not a valid hex color.
Color colorFromHex(String? hex) {
  final cleaned = (hex ?? '').replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (cleaned.length != 6 || value == null) return const Color(0xFF7C3AED);
  return Color(0xFF000000 | value);
}

/// Bundled artwork also works with records saved before images were introduced.
String defaultCatalogImage(String id) {
  const bundledIds = {
    'MOV-001',
    'MOV-002',
    'MOV-003',
    'MOV-004',
    'MOV-005',
    'MOV-006',
    'MOV-007',
    'MOV-008',
    'SVC-001',
    'SVC-002',
    'SVC-003',
    'SVC-004',
    'SVC-005',
    'SVC-006',
    'SVC-007',
    'SVC-008',
    'SVC-009',
    'SVC-010',
    'SVC-011',
    'SVC-012',
  };
  return bundledIds.contains(id) ? 'assets/images/$id.png' : '';
}

String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
