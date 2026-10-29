import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movie_seat/catalog_models.dart';
import 'package:movie_seat/catalog_service.dart';
import 'package:movie_seat/cinema_pages.dart';
import 'package:movie_seat/admin_page.dart';
import 'package:movie_seat/main.dart';

Movie fixtureMovie() => Movie.fromJson(
  (jsonDecode(File('api/movies.json').readAsStringSync()) as List).first
      as Map<String, dynamic>,
);
ServiceItem fixtureSnack() => ServiceItem.fromJson(
  (jsonDecode(File('api/services.json').readAsStringSync()) as List).first
      as Map<String, dynamic>,
);
http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: page),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'Sign in attaches the bearer token and propagates the administrator role',
    () async {
      final service = CatalogService(
        client: MockClient((request) async {
          if (request.url.path == '/login') {
            expect(jsonDecode(request.body)['email'], 'admin@example.com');
            return reply({
              'token': 'session-token',
              'role': 'admin',
              'email': 'admin@example.com',
            });
          }
          expect(request.headers['Authorization'], 'Bearer session-token');
          return reply({'movies': []});
        }),
      );
      await service.signIn('admin@example.com', 'password123');
      expect(service.isAdmin, isTrue);
      await service.request('admin/state');
      service.close();
    },
  );
  testWidgets(
    'Cart changes quantities, submits once, and clears after success',
    (tester) async {
      final quantities = {'SVC-001': 1};
      Map<String, dynamic>? submitted;
      final service = CatalogService(
        client: MockClient((request) async {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return reply({'id': 'FOOD-TEST'});
        }),
      );
      await pumpPage(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CartPage(
                    service: service,
                    items: [fixtureSnack()],
                    quantities: quantities,
                  ),
                ),
              ),
              child: const Text('Open cart'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open cart'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(quantities['SVC-001'], 2);
      await tester.tap(find.text('Place order — pay at cinema'));
      await tester.pumpAndSettle();
      expect((submitted!['items'] as List).single['quantity'], 2);
      expect(quantities, isEmpty);
      expect(find.text('Open cart'), findsOneWidget);
    },
  );
  testWidgets('Review form submits selected stars and refreshes the reviews', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    final service = CatalogService(
      client: MockClient((request) async {
        if (request.url.path == '/review-eligibility') {
          return reply({'eligible': true, 'reason': 'Review available'});
        }
        if (request.method == 'POST') {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return reply(submitted!);
        }
        return reply(submitted == null ? [] : [submitted]);
      }),
    );
    await pumpPage(
      tester,
      ReviewsPage(movie: fixtureMovie(), service: service),
    );
    await tester.enterText(find.byType(TextField), 'Great cinema experience');
    await tester.tap(find.byTooltip('4 stars'));
    await tester.pump();
    await tester.tap(find.text('Submit review'));
    await tester.pumpAndSettle();
    expect(submitted!['rating'], 4);
    expect(submitted!['movieId'], 'MOV-001');
    expect(find.text('Great cinema experience'), findsOneWidget);
  });
  testWidgets('Seat polling removes a selection taken by another customer', (
    tester,
  ) async {
    var occupied = false;
    final service = CatalogService(
      client: MockClient(
        (request) async => reply({
          'rows': 1,
          'columns': 2,
          'seats': ['A1', 'A2'],
          'taken': occupied ? ['A1'] : [],
        }),
      ),
    );
    await pumpPage(
      tester,
      SeatSelectionPage(
        movie: fixtureMovie(),
        showtime: '10:30 AM',
        service: service,
        bookings: const [],
        onBooked: (_) {},
      ),
    );
    await tester.tap(find.text('A1'));
    await tester.pump();
    expect(
      tester.widget<SeatTile>(find.byType(SeatTile).first).isSelected,
      isTrue,
    );
    occupied = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(
      tester.widget<SeatTile>(find.byType(SeatTile).first).isSelected,
      isFalse,
    );
    expect(
      tester.widget<SeatTile>(find.byType(SeatTile).first).isReserved,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Seat selection continues to the optional food decision', (
    tester,
  ) async {
    final service = CatalogService(
      client: MockClient(
        (request) async => reply({
          'rows': 1,
          'columns': 2,
          'seats': ['A1', 'A2'],
          'taken': [],
        }),
      ),
    );
    await pumpPage(
      tester,
      SeatSelectionPage(
        movie: fixtureMovie(),
        showtime: '10:30 AM',
        service: service,
        bookings: const [],
        onBooked: (_) {},
      ),
    );
    await tester.tap(find.text('A1'));
    await tester.pump();
    await tester.tap(find.text('Continue with 1 seat'));
    await tester.pumpAndSettle();
    expect(find.text('Add food and beverages?'), findsOneWidget);
    expect(find.text('Skip add-ons'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Management loads and saves a food menu change', (tester) async {
    Map<String, dynamic>? submitted;
    final menu =
        jsonDecode(File('api/services.json').readAsStringSync()) as List;
    final service = CatalogService(
      client: MockClient((request) async {
        if (request.method == 'PUT') {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.url.path, '/services/SVC-001');
          return reply(submitted!);
        }
        return reply({
          'movies': [],
          'services': menu,
          'bookings': [],
          'orders': [],
          'reviews': [],
          'cinema': {'rows': 8, 'columns': 8},
        });
      }),
    );
    await pumpPage(tester, Scaffold(body: AdminPage(service: service)));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food & service menu').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(3), '150');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(submitted!['price'], 150);
    expect(submitted!['id'], 'SVC-001');
  });
  testWidgets('Returning to My Tickets reloads saved booking history', (
    tester,
  ) async {
    var reads = 0;
    final service = CatalogService(
      client: MockClient((request) async {
        if (request.url.path == '/bookings') {
          reads++;
          return reply([]);
        }
        if (request.url.path == '/orders') return reply([]);
        return http.Response.bytes(
          File(
            'api${request.url.path.endsWith('.json') ? request.url.path : '${request.url.path}.json'}',
          ).readAsBytesSync(),
          200,
        );
      }),
    );
    await pumpPage(
      tester,
      HomeShell(bookings: const [], onBooked: (_) {}, catalogService: service),
    );
    final initial = reads;
    await tester.tap(find.text('My Tickets').last);
    await tester.pumpAndSettle();
    expect(reads, greaterThan(initial));
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    final previous = reads;
    await tester.tap(find.text('My Tickets').last);
    await tester.pumpAndSettle();
    expect(reads, greaterThan(previous));
  });
  test(
    'Catalog models serialize and deserialize their pictures, colors and icons',
    () {
      final movie = fixtureMovie();
      final snack = fixtureSnack();
      expect(Movie.fromJson(movie.toJson()).toJson(), movie.toJson());
      expect(ServiceItem.fromJson(snack.toJson()).toJson(), snack.toJson());
      expect(snack.toJson()['icon'], 'popcorn');
      expect(snack.toJson()['color'], '#F59E0B');
    },
  );

  test('Catalog create, update and delete use POST, PUT and DELETE', () async {
    final calls = <String>[];
    final service = CatalogService(
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        expect(request.headers['Authorization'], 'Bearer admin-session');
        if (request.method == 'DELETE') return http.Response('', 204);
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.method == 'POST') {
          expect(data.containsKey('id'), isFalse);
          data['id'] = request.url.path == '/movies' ? 'MOV-NEW' : 'SVC-NEW';
        }
        return reply(data, request.method == 'POST' ? 201 : 200);
      }),
    )..token = 'admin-session';
    final movie = await service.createMovie(fixtureMovie());
    expect(movie.id, 'MOV-NEW');
    await service.updateMovie(movie);
    await service.deleteMovie(movie.id);
    final snack = await service.createService(fixtureSnack());
    expect(snack.id, 'SVC-NEW');
    await service.updateService(snack);
    await service.deleteService(snack.id);
    expect(calls, [
      'POST /movies',
      'PUT /movies/MOV-NEW',
      'DELETE /movies/MOV-NEW',
      'POST /services',
      'PUT /services/SVC-NEW',
      'DELETE /services/SVC-NEW',
    ]);
    service.close();
  });
}
