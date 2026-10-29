import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movie_seat/catalog_models.dart';
import 'package:movie_seat/catalog_service.dart';
import 'package:movie_seat/main.dart';

/// A fake MovieSeat API that answers GET requests with the real JSON files
/// from the project's `api` folder, so the tests use the same data as the app.
CatalogService fakeApi({int statusCode = 200}) {
  final client = MockClient((request) async {
    if (statusCode != 200) return http.Response('Server error', statusCode);
    final file = File(
      'api${request.url.path.endsWith('.json') ? request.url.path : '${request.url.path}.json'}',
    );
    if (request.method != 'GET' || !file.existsSync()) {
      return http.Response('Not found', 404);
    }
    return http.Response.bytes(
      file.readAsBytesSync(),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return CatalogService(client: client);
}

Future<void> pumpHome(WidgetTester tester, CatalogService service) async {
  // Start on the home screen to test the catalog independently of authentication.
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: HomeShell(
        bookings: const [],
        onBooked: (_) {},
        catalogService: service,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('JSON object maps to a Movie', () {
    final movie = Movie.fromJson({
      'id': 'MOV-001',
      'title': 'Beyond the Stars',
      'genre': 'Sci-Fi',
      'duration': '2h 12m',
      'rating': 8.7,
      'price': 280,
      'synopsis': 'A young engineer...',
      'showtimes': ['10:30 AM', '1:45 PM'],
      'colors': ['#312E81', '#7C3AED'],
    });

    expect(movie.title, 'Beyond the Stars');
    expect(movie.rating, 8.7);
    expect(movie.price, 280.0);
    expect(movie.showtimes, ['10:30 AM', '1:45 PM']);
    expect(movie.colors.first, const Color(0xFF312E81));
    expect(movie.matches('sci'), isTrue);
    expect(movie.matches('comedy'), isFalse);
  });

  test('HTTP GET returns the whole JSON array as objects', () async {
    final service = fakeApi();
    expect((await service.fetchMovies()).length, 8);
    expect((await service.fetchServices()).length, 12);
  });

  test('A server error becomes a CatalogException', () async {
    expect(
      fakeApi(statusCode: 500).fetchMovies(),
      throwsA(isA<CatalogException>()),
    );
  });

  testWidgets('Movies load from the API, can be searched and opened', (
    tester,
  ) async {
    await pumpHome(tester, fakeApi());

    expect(find.text('Beyond the Stars'), findsOneWidget);
    expect(find.text('8 of 8'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'comedy');
    await tester.pumpAndSettle();
    expect(find.text('Barkada Weekend'), findsOneWidget);
    expect(find.text('Beyond the Stars'), findsNothing);
    expect(find.text('1 of 8'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No movies found'), findsOneWidget);

    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Beyond the Stars'), findsOneWidget);

    await tester.tap(find.text('View').first);
    await tester.pumpAndSettle();
    expect(find.text('Movie Details'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Choose a showtime'), 150);
    expect(find.text('Choose a showtime'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('10:30 AM'), 150);
    expect(find.text('10:30 AM'), findsOneWidget);
  });

  testWidgets('Snacks & Services catalog loads and filters', (tester) async {
    await pumpHome(tester, fakeApi());

    await tester.tap(find.text('Snacks'));
    await tester.pumpAndSettle();
    expect(find.text('Snacks & Services'), findsOneWidget);
    expect(find.text('12 of 12 items'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'popcorn');
    await tester.pumpAndSettle();
    expect(find.text('Classic Butter Popcorn'), findsOneWidget);
    expect(find.text('Bottled Water'), findsNothing);
  });

  testWidgets('Shows an error with Try again when the API fails', (
    tester,
  ) async {
    await pumpHome(tester, fakeApi(statusCode: 500));

    expect(find.text("Couldn't load movies"), findsOneWidget);
    expect(find.text('Try again'), findsWidgets);
  });
}
