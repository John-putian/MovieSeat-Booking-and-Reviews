import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:movie_seat/booking_journey.dart';
import 'package:movie_seat/catalog_models.dart';
import 'package:movie_seat/catalog_service.dart';
import 'package:movie_seat/cinema_pages.dart';
import 'package:movie_seat/main.dart';

final movieJson =
    (jsonDecode(File('api/movies.json').readAsStringSync()) as List).first
        as Map<String, dynamic>;
Movie get movie => Movie.fromJson(movieJson);
http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class FlowApi {
  late final CatalogService service = CatalogService(
    client: MockClient(handle),
  );
  Map<String, dynamic>? quotePayload;
  Map<String, dynamic>? booking;
  Map<String, dynamic>? order;
  final paymentAttempts = <Map<String, dynamic>>[];
  bool failNetworkOnce = false;
  bool loseConfirmationResponseOnce = false;
  final checkoutAttempts = <Map<String, dynamic>>[];
  Map<String, dynamic> get receipt => {'booking': booking, 'order': order};
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path == '/availability') {
      return response({
        'rows': 1,
        'columns': 4,
        'seats': ['A1', 'A2', 'A3', 'A4'],
        'taken': [],
      });
    }
    if (path == '/services') {
      return http.Response.bytes(
        File('api/services.json').readAsBytesSync(),
        200,
      );
    }
    if (path == '/checkout/quote') {
      quotePayload = jsonDecode(request.body) as Map<String, dynamic>;
      final lines = quotePayload!['items'] as List;
      final items = lines
          .map(
            (x) => {
              'id': x['id'],
              'name': 'Classic Butter Popcorn',
              'quantity': x['quantity'],
              'price': 120,
            },
          )
          .toList();
      final ticketTotal = (quotePayload!['ticketCount'] as int) * 280;
      final foodTotal = items.fold<num>(
        0,
        (sum, x) => sum + (x['quantity'] as int) * 120,
      );
      return response({
        ...quotePayload!,
        'quoteId': 'QUOTE-TEST',
        'movie': movieJson,
        'items': items,
        'ticketTotal': ticketTotal,
        'foodTotal': foodTotal,
        'total': ticketTotal + foodTotal,
      });
    }
    if (path == '/checkout') {
      checkoutAttempts.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (booking != null) return response(receipt);
      final ticketTotal = (quotePayload!['ticketCount'] as int) * 280;
      final items = quotePayload!['items'] as List;
      final foodTotal = items.fold<num>(
        0,
        (sum, x) => sum + (x['quantity'] as int) * 120,
      );
      booking = {
        'id': 'MS-FLOW',
        'movie': movieJson,
        'date': quotePayload!['date'],
        'showtime': quotePayload!['showtime'],
        'seats': quotePayload!['seats'],
        'ticketCount': quotePayload!['ticketCount'],
        'ticketTotal': ticketTotal,
        'foodTotal': foodTotal,
        'total': ticketTotal + foodTotal,
        'status': 'pending_payment',
        'payment': null,
        'paymentStatus': 'unpaid',
        'tickets': [],
        'createdAt': DateTime.now().toIso8601String(),
        'holdExpiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
      };
      if (items.isNotEmpty) {
        order = {
          'id': 'FOOD-FLOW',
          'bookingId': 'MS-FLOW',
          'status': 'awaiting_payment',
          'paymentStatus': 'unpaid',
          'items': items
              .map(
                (x) => {
                  'id': x['id'],
                  'name': 'Classic Butter Popcorn',
                  'quantity': x['quantity'],
                  'price': 120,
                },
              )
              .toList(),
          'total': foodTotal,
        };
      }
      if (loseConfirmationResponseOnce) {
        loseConfirmationResponseOnce = false;
        throw http.ClientException('Confirmation response lost');
      }
      return response(receipt);
    }
    if (path == '/bookings/MS-FLOW/payment') {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      paymentAttempts.add(payload);
      if (failNetworkOnce) {
        failNetworkOnce = false;
        throw http.ClientException('Connection lost');
      }
      booking!['payment'] = payload['method'];
      if (payload['method'] == 'counter') {
        booking!['paymentStatus'] = 'awaiting_counter';
      } else if (payload['outcome'] == 'declined') {
        booking!['paymentStatus'] = 'failed';
      } else {
        settle();
      }
      return response(receipt);
    }
    if (path == '/bookings/MS-FLOW') return response(receipt);
    if (path == '/review-eligibility') {
      return response({
        'eligible': false,
        'reason': 'Reviews unlock after your screening ends.',
      });
    }
    if (path == '/reviews') return response([]);
    return response({'error': 'Not found'}, 404);
  }

  void settle() {
    booking!['status'] = 'confirmed';
    booking!['paymentStatus'] = 'demo_paid';
    booking!['tickets'] = (booking!['seats'] as List)
        .map(
          (seat) => {
            'seat': seat,
            'token': 'MS-T-TEST-$seat',
            'redeemedAt': null,
          },
        )
        .toList();
    if (order != null) {
      order!['status'] = 'placed';
      order!['paymentStatus'] = 'demo_paid';
      order!['voucher'] = {'token': 'MS-F-TEST', 'redeemedAt': null};
    }
  }
}

Future<void> pumpFlow(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: child),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final base = find.text(text);
  if (base.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      base,
      160,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final finder = base.last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> selectDemo(WidgetTester tester) async {
  await tapText(tester, 'Demo checkout - no money charged');
}

BookingSelection selection() => BookingSelection(
  movie: movie,
  showtime: '10:30 AM',
  date: '2026-10-28',
  ticketCount: 2,
  seats: ['A1', 'A2'],
);
void main() {
  testWidgets('Choose ticket quantity before choosing seats', (tester) async {
    int? count;
    await pumpFlow(
      tester,
      TicketQuantityPage(
        movie: movie,
        showtime: '10:30 AM',
        seatBuilder: (n, date) {
          count = n;
          return const Scaffold(body: Text('Seat selection destination'));
        },
      ),
    );
    await tester.ensureVisible(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add ticket'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Choose 2 seats');
    expect(count, 2);
    expect(find.text('Seat selection destination'), findsOneWidget);
  });
  testWidgets('Continue requires exactly as many seats as tickets', (
    tester,
  ) async {
    final api = FlowApi();
    await pumpFlow(
      tester,
      SeatSelectionPage(
        movie: movie,
        showtime: '10:30 AM',
        service: api.service,
        bookings: const [],
        onBooked: (_) {},
        ticketCount: 2,
      ),
    );
    await tester.tap(find.text('A1'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue with 2 seats'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('A2'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue with 2 seats'),
          )
          .onPressed,
      isNotNull,
    );
    await tapText(tester, 'Continue with 2 seats');
    expect(find.text('Add food and beverages?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Skip food, review, confirm, decline payment, retry, then issue one QR per seat',
    (tester) async {
      final api = FlowApi();
      await pumpFlow(
        tester,
        AddOnsChoicePage(selection: selection(), service: api.service),
      );
      await tapText(tester, 'Skip add-ons');
      expect(api.quotePayload!['items'], isEmpty);
      expect(find.text('Total: ₱560'), findsOneWidget);
      await tapText(tester, 'Confirm booking');
      expect(find.byType(QrImageView), findsNothing);
      await selectDemo(tester);
      await tapText(tester, 'Demo test options');
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tapText(tester, 'Make payment');
      expect(find.byType(QrImageView), findsNothing);
      expect(find.textContaining('Demo payment declined'), findsOneWidget);
      await tapText(tester, 'Retry payment');
      expect(find.byType(BookingPassesPage), findsOneWidget);
      // ListView lazily builds receipts as they scroll into view.
      expect(find.text('Seat A1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Seat A2'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(BookingPassesPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Seat A2'), findsOneWidget);
      expect((api.booking!['tickets'] as List).length, 2);
      expect(api.order, isNull);
      expect(api.paymentAttempts.map((x) => x['outcome']), [
        'declined',
        'success',
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Food add-ons are included in review and produce a separate voucher',
    (tester) async {
      final api = FlowApi();
      await pumpFlow(
        tester,
        AddOnsChoicePage(selection: selection(), service: api.service),
      );
      await tapText(tester, 'Add food & beverages');
      await tester.tap(find.byTooltip('Add Classic Butter Popcorn'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add Classic Butter Popcorn'));
      await tester.pump();
      await tapText(tester, 'Review booking');
      expect(api.quotePayload!['items'], [
        {'id': 'SVC-001', 'quantity': 2},
      ]);
      expect(find.text('Total: ₱800'), findsOneWidget);
      await tapText(tester, 'Confirm booking');
      await selectDemo(tester);
      await tapText(tester, 'Make payment');
      await tester.scrollUntilVisible(
        find.text('Food voucher'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(BookingPassesPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Food voucher'), findsOneWidget);
      expect(api.order!['voucher']['token'], 'MS-F-TEST');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Counter payment displays no QR until staff settlement is refreshed',
    (tester) async {
      final api = FlowApi();
      final quote = await api.service.request(
        'checkout/quote',
        body: {...selection().toJson(), 'items': []},
      );
      final receipt = await api.service.request(
        'checkout',
        body: {'quoteId': quote['quoteId'], 'requestId': 'test'},
      );
      await pumpFlow(
        tester,
        BookingPaymentPage(
          service: api.service,
          initialReceipt: Map<String, dynamic>.from(receipt as Map),
        ),
      );
      await tapText(tester, 'Pay at cinema counter');
      await tapText(tester, 'Reserve for counter payment');
      expect(find.byType(QrImageView), findsNothing);
      expect(find.textContaining('Awaiting counter payment.'), findsOneWidget);
      api.settle();
      await tapText(tester, 'Refresh payment status');
      expect(find.byType(BookingPassesPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Network retry keeps the same payment attempt ID', (
    tester,
  ) async {
    final api = FlowApi()..failNetworkOnce = true;
    final quote = await api.service.request(
      'checkout/quote',
      body: {...selection().toJson(), 'items': []},
    );
    final receipt = await api.service.request(
      'checkout',
      body: {'quoteId': quote['quoteId'], 'requestId': 'test'},
    );
    await pumpFlow(
      tester,
      BookingPaymentPage(
        service: api.service,
        initialReceipt: Map<String, dynamic>.from(receipt as Map),
      ),
    );
    await selectDemo(tester);
    await tapText(tester, 'Make payment');
    await tapText(tester, 'Retry payment');
    expect(
      api.paymentAttempts[0]['attemptId'],
      api.paymentAttempts[1]['attemptId'],
    );
    expect(find.byType(BookingPassesPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Reviews can be read but not submitted before eligibility', (
    tester,
  ) async {
    final api = FlowApi();
    await pumpFlow(tester, ReviewsPage(movie: movie, service: api.service));
    expect(
      find.text('Reviews unlock after your screening ends.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Be the first to review this movie.'), findsOneWidget);
  });
  testWidgets(
    'Staff can accept a ticket code and see an already-used rejection',
    (tester) async {
      var used = false;
      final service = CatalogService(
        client: MockClient((request) async {
          expect(request.url.path, '/admin/redeem');
          if (used) {
            return response({
              'error': 'This ticket has already been used.',
            }, 409);
          }
          used = true;
          return response({
            'type': 'ticket',
            'message': 'Admission accepted.',
            'movie': movie.title,
            'seat': 'A1',
            'showtime': '10:30 AM',
          });
        }),
      );
      await pumpFlow(tester, RedeemPassesPage(service: service));
      await tester.enterText(find.byType(TextField), 'MS-T-TEST-A1');
      await tapText(tester, 'Validate & redeem');
      expect(find.textContaining('Admission accepted.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'MS-T-TEST-A1');
      await tapText(tester, 'Validate & redeem');
      expect(find.text('This ticket has already been used.'), findsOneWidget);
    },
  );
  testWidgets(
    'A lost booking response can retry confirmation without creating another reservation',
    (tester) async {
      final api = FlowApi()..loseConfirmationResponseOnce = true;
      await pumpFlow(
        tester,
        BookingReviewPage(
          selection: selection(),
          service: api.service,
          items: const [],
        ),
      );
      await tapText(tester, 'Confirm booking');
      await tester.scrollUntilVisible(
        find.text('Retry confirmation'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(BookingReviewPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Retry confirmation'), findsOneWidget);
      await tapText(tester, 'Retry confirmation');
      expect(find.byType(BookingPaymentPage), findsOneWidget);
      expect(api.checkoutAttempts.length, 2);
      expect(
        api.checkoutAttempts[0]['requestId'],
        api.checkoutAttempts[1]['requestId'],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Leaving payment returns to movies while the pending reservation stays resumable',
    (tester) async {
      final api = FlowApi();
      await pumpFlow(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BookingReviewPage(
                    selection: selection(),
                    service: api.service,
                    items: const [],
                  ),
                ),
              ),
              child: const Text('Browse movies'),
            ),
          ),
        ),
      );
      await tapText(tester, 'Browse movies');
      await tapText(tester, 'Confirm booking');
      expect(find.byType(BookingPaymentPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Browse movies'), findsOneWidget);
      expect(api.booking!['status'], 'pending_payment');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
