import 'dart:convert';
import 'package:http/http.dart' as http;
import 'catalog_models.dart';

class CatalogException implements Exception {
  const CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CatalogService {
  CatalogService({http.Client? client, this.baseUrl = defaultBaseUrl})
    : _client = client ?? http.Client();
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8001',
  );
  final http.Client _client;
  final String baseUrl;
  String? token;
  String email = '';
  String role = 'customer';
  bool get isAdmin => role == 'admin';
  void close() => _client.close();

  Future<dynamic> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? method,
  }) async {
    final uri = Uri.parse('$baseUrl/$path').replace(queryParameters: query);
    final headers = {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };
    final verb = method ?? (body == null ? 'GET' : 'POST');
    if (!const ['GET', 'POST', 'PUT', 'DELETE'].contains(verb)) {
      throw ArgumentError.value(verb, 'method', 'Unsupported HTTP method');
    }
    final http.Response response;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      final pending = switch (verb) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: encoded),
        'PUT' => _client.put(uri, headers: headers, body: encoded),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => throw StateError('Unsupported method'),
      };
      response = await pending.timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const CatalogException(
        "We could not connect to MovieSeat. Please try again.",
      );
    }
    // A successful DELETE normally has no JSON response body.
    if (response.statusCode == 204) return null;
    final dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const CatalogException('The server sent invalid JSON.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CatalogException(
        data is Map && data['error'] is String
            ? data['error'] as String
            : 'Server error (HTTP ${response.statusCode}).',
      );
    }
    return data;
  }

  Future<List<Movie>> fetchMovies() async =>
      (await list('movies')).map(Movie.fromJson).toList();
  Future<List<ServiceItem>> fetchServices() async =>
      (await list('services')).map(ServiceItem.fromJson).toList();
  Future<List<Map<String, dynamic>>> list(
    String path, {
    Map<String, String>? query,
  }) async {
    final data = await request(path, query: query);
    if (data is! List || data.any((e) => e is! Map<String, dynamic>)) {
      throw const CatalogException('The API did not send a valid list.');
    }
    return data.cast<Map<String, dynamic>>();
  }

  /// POST creates; the server assigns the permanent record ID.
  Future<Movie> createMovie(Movie movie) async => Movie.fromJson(
    Map<String, dynamic>.from(
      await request(
            'movies',
            method: 'POST',
            body: Map<String, dynamic>.from(movie.toJson())..remove('id'),
          )
          as Map,
    ),
  );

  /// PUT replaces the movie identified by its existing ID.
  Future<Movie> updateMovie(Movie movie) async => Movie.fromJson(
    Map<String, dynamic>.from(
      await request(
            'movies/${Uri.encodeComponent(movie.id)}',
            method: 'PUT',
            body: movie.toJson(),
          )
          as Map,
    ),
  );

  Future<void> deleteMovie(String id) async {
    await request('movies/${Uri.encodeComponent(id)}', method: 'DELETE');
  }

  Future<ServiceItem> createService(ServiceItem item) async =>
      ServiceItem.fromJson(
        Map<String, dynamic>.from(
          await request(
                'services',
                method: 'POST',
                body: Map<String, dynamic>.from(item.toJson())..remove('id'),
              )
              as Map,
        ),
      );

  Future<ServiceItem> updateService(ServiceItem item) async =>
      ServiceItem.fromJson(
        Map<String, dynamic>.from(
          await request(
                'services/${Uri.encodeComponent(item.id)}',
                method: 'PUT',
                body: item.toJson(),
              )
              as Map,
        ),
      );

  Future<void> deleteService(String id) async {
    await request('services/${Uri.encodeComponent(id)}', method: 'DELETE');
  }

  Future<void> signIn(
    String email,
    String password, {
    bool register = false,
  }) async {
    final data = await request(
      register ? 'register' : 'login',
      body: {'email': email, 'password': password},
    );
    token = data['token'] as String;
    this.email = data['email'] as String;
    role = data['role'] as String;
  }

  Future<void> signOut() async {
    try {
      await request('logout', body: {});
    } finally {
      token = null;
      email = '';
      role = 'customer';
    }
  }
}

String screeningDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String newRequestId() => DateTime.now().microsecondsSinceEpoch.toString();
String paymentLabel(String value) => switch (value) {
  'demo_paid' => 'Demo payment — no money charged',
  'paid_at_counter' => 'Paid at cinema',
  'failed' => 'Payment failed - retry available',
  'expired' => 'Payment hold expired',
  'awaiting_counter' => 'Awaiting payment at cinema',
  _ => 'Pay at cinema',
};

String bookingStatusLabel(String value) => switch (value) {
  'pending_payment' || 'awaiting_payment' => 'Awaiting payment',
  'confirmed' => 'Confirmed',
  'expired' => 'Expired',
  'cancelled' => 'Cancelled',
  'placed' => 'Order placed',
  'preparing' => 'Preparing',
  'ready' => 'Ready to collect',
  'completed' => 'Collected',
  _ => value,
};
