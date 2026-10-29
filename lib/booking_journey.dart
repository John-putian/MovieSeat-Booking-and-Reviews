import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'catalog_models.dart';
import 'catalog_service.dart';
import 'catalog_widgets.dart';
import 'brand_widgets.dart';
import 'cinema_pages.dart';
import 'ui_widgets.dart';

class BookingSelection {
  const BookingSelection({
    required this.movie,
    required this.showtime,
    required this.date,
    required this.ticketCount,
    required this.seats,
  });
  final Movie movie;
  final String showtime;
  final String date;
  final int ticketCount;
  final List<String> seats;
  Map<String, dynamic> toJson() => {
    'movieId': movie.id,
    'showtime': showtime,
    'date': date,
    'ticketCount': ticketCount,
    'seats': seats,
  };
}

class TicketQuantityPage extends StatefulWidget {
  const TicketQuantityPage({
    super.key,
    required this.movie,
    required this.showtime,
    required this.seatBuilder,
  });
  final Movie movie;
  final String showtime;
  final Widget Function(int count, DateTime date) seatBuilder;
  @override
  State<TicketQuantityPage> createState() => _TicketQuantityPageState();
}

class _TicketQuantityPageState extends State<TicketQuantityPage> {
  int _count = 1;
  late DateTime _date;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    _date = DateTime(now.year, now.month, now.day);
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
    ).firstMatch(widget.showtime);
    if (match != null) {
      final hour = int.parse(match[1]!) % 12 + (match[3] == 'PM' ? 12 : 0);
      if (!_date
          .add(Duration(hours: hour, minutes: int.parse(match[2]!)))
          .isAfter(
            DateTime(now.year, now.month, now.day, now.hour, now.minute),
          )) {
        _date = _date.add(const Duration(days: 1));
      }
    }
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final day = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (day != null && mounted) setState(() => _date = day);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const MovieSeatPageTitle('Your tickets')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const BookingProgress(step: 0),
        Text(
          'Plan your movie visit',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a date and the number of people joining you.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 20),
        const SizedBox(height: 24),
        const Text(
          'How many tickets?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '${formatPeso(widget.movie.price)} each - up to 6 per booking',
          style: const TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: 'Remove ticket',
              onPressed: _count > 1 ? () => setState(() => _count--) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 100,
              child: Column(
                children: [
                  Text(
                    '$_count',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _count == 1 ? 'ticket' : 'tickets',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Add ticket',
              onPressed: _count < 6 ? () => setState(() => _count++) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 24),
        BookingSummary(
          movie: widget.movie,
          date: screeningDate(_date),
          showtime: widget.showtime,
          onChangeDate: _chooseDate,
        ),
        const UiNotice(
          title: 'One ticket, one seat',
          message: 'You will choose a seat for each person on the next screen.',
          icon: Icons.event_seat_outlined,
        ),
      ],
    ),
    bottomNavigationBar: BookingActionBar(
      label: 'Choose $_count seat${_count == 1 ? '' : 's'}',
      total: widget.movie.price * _count,
      totalLabel: 'Ticket subtotal',
      hint: 'Next: select your seats',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => widget.seatBuilder(_count, _date),
        ),
      ),
    ),
  );
}

class AddOnsChoicePage extends StatelessWidget {
  const AddOnsChoicePage({
    super.key,
    required this.selection,
    required this.service,
  });
  final BookingSelection selection;
  final CatalogService service;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const MovieSeatPageTitle('Food & beverages')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const BookingProgress(step: 2),
        Text(
          'Add food and beverages?',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'This step is optional. You can also book tickets only.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 20),
        BookingSummary(
          movie: selection.movie,
          date: selection.date,
          showtime: selection.showtime,
          seats: selection.seats,
        ),
        const CatalogArtwork(
          image: 'assets/images/SVC-008.png',
          label: 'Popcorn and a cold drink',
          height: 150,
          radius: 16,
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        decoration: const BoxDecoration(
          color: Color(0xFF171321),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      FoodAddOnsPage(selection: selection, service: service),
                ),
              ),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Add food & beverages'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BookingReviewPage(
                    selection: selection,
                    service: service,
                    items: const [],
                  ),
                ),
              ),
              child: const Text('Skip add-ons'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Next: review your booking',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class FoodAddOnsPage extends StatefulWidget {
  const FoodAddOnsPage({
    super.key,
    required this.selection,
    required this.service,
  });
  final BookingSelection selection;
  final CatalogService service;
  @override
  State<FoodAddOnsPage> createState() => _FoodAddOnsPageState();
}

class _FoodAddOnsPageState extends State<FoodAddOnsPage> {
  late Future<List<ServiceItem>> _future;
  final Map<String, int> _quantities = {};
  @override
  void initState() {
    super.initState();
    _future = widget.service.fetchServices();
  }

  void _reload() {
    setState(() {
      _future = widget.service.fetchServices();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const MovieSeatPageTitle('Select food add-ons')),
    body: FutureBuilder<List<ServiceItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return CatalogMessage(
            icon: Icons.cloud_off,
            title: 'Unable to load menu',
            message: '${snapshot.error}',
            actionLabel: 'Try again',
            onAction: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const CatalogLoading(label: 'Loading food and beverages...');
        }
        final items = snapshot.data!
            .where(
              (x) =>
                  x.available &&
                  ['Snacks', 'Drinks', 'Combos'].contains(x.category),
            )
            .toList();
        final total = items.fold<double>(
          0,
          (sum, x) => sum + x.price * (_quantities[x.id] ?? 0),
        );
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const BookingProgress(step: 2),
                  const Text(
                    'Choose your snacks',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap + to add an item. Leave quantities at zero to skip.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 16),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No food add-ons are available. You can skip this step.',
                      ),
                    ),
                  for (final item in items)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CatalogArtwork(
                                  width: 60,
                                  height: 60,
                                  radius: 10,
                                  image: item.image,
                                  label: item.name,
                                  icon: item.icon,
                                  colors: [item.color, item.color],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name),
                                      Text(formatPeso(item.price)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: 'Remove ${item.name}',
                                  onPressed: (_quantities[item.id] ?? 0) == 0
                                      ? null
                                      : () => setState(() {
                                          final count =
                                              _quantities[item.id]! - 1;
                                          if (count == 0) {
                                            _quantities.remove(item.id);
                                          } else {
                                            _quantities[item.id] = count;
                                          }
                                        }),
                                  icon: const Icon(Icons.remove),
                                ),
                                Text('${_quantities[item.id] ?? 0}'),
                                IconButton(
                                  tooltip: 'Add ${item.name}',
                                  onPressed: (_quantities[item.id] ?? 0) >= 20
                                      ? null
                                      : () => setState(() {
                                          _quantities[item.id] =
                                              (_quantities[item.id] ?? 0) + 1;
                                        }),
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            BookingActionBar(
              label: 'Review booking',
              total: total,
              totalLabel: 'Food subtotal',
              hint: _quantities.isEmpty
                  ? 'No food selected - continue with tickets only'
                  : 'Next: review tickets and food together',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BookingReviewPage(
                    selection: widget.selection,
                    service: widget.service,
                    items: _quantities.entries
                        .map(
                          (x) => <String, dynamic>{
                            'id': x.key,
                            'quantity': x.value,
                          },
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class BookingReviewPage extends StatefulWidget {
  const BookingReviewPage({
    super.key,
    required this.selection,
    required this.service,
    required this.items,
  });
  final BookingSelection selection;
  final CatalogService service;
  final List<Map<String, dynamic>> items;
  @override
  State<BookingReviewPage> createState() => _BookingReviewPageState();
}

class _BookingReviewPageState extends State<BookingReviewPage> {
  Map<String, dynamic>? _quote;
  String? _error;
  bool _busy = false;
  bool _confirmFailed = false;
  final _requestId = newRequestId();
  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _busy = true;
      _error = null;
      _confirmFailed = false;
    });
    try {
      final quote = await widget.service.request(
        'checkout/quote',
        body: {...widget.selection.toJson(), 'items': widget.items},
      );
      if (mounted) {
        setState(() => _quote = Map<String, dynamic>.from(quote as Map));
      }
    } on CatalogException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service.request(
        'checkout',
        body: {'quoteId': _quote!['quoteId'], 'requestId': _requestId},
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BookingPaymentPage(
            service: widget.service,
            initialReceipt: Map<String, dynamic>.from(result as Map),
          ),
        ),
      );
    } on CatalogException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _confirmFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const MovieSeatPageTitle('Review booking')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const BookingProgress(step: 3),
        const Text(
          'Everything look right?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Check your visit and total before you continue.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          UiNotice(
            title: 'Please check your booking',
            message: _error!,
            error: true,
          ),
          OutlinedButton(
            onPressed: _busy ? null : _loadQuote,
            child: const Text('Refresh prices'),
          ),
          const SizedBox(height: 16),
        ],
        if (_busy && _quote == null)
          const CatalogLoading(label: 'Checking seats and prices...'),
        if (_quote != null) ...[
          BookingSummary(
            movie: Movie.fromJson(
              Map<String, dynamic>.from(_quote!['movie'] as Map),
            ),
            date: _quote!['date'] as String,
            showtime: _quote!['showtime'] as String,
            seats: List<String>.from(_quote!['seats'] as List),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Price breakdown',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_quote!['ticketCount']} movie tickets'),
                    trailing: Text(
                      formatPeso((_quote!['ticketTotal'] as num).toDouble()),
                    ),
                  ),
                  if ((_quote!['items'] as List).isEmpty)
                    const Text(
                      'No food add-ons',
                      style: TextStyle(color: Colors.white60),
                    ),
                  for (final item in _quote!['items'] as List)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${item['quantity']} x ${item['name']}'),
                      trailing: Text(
                        formatPeso(
                          (item['price'] as num).toDouble() *
                              (item['quantity'] as num),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const UiNotice(
            title: 'No payment yet',
            message:
                'Confirm to hold your seats for 10 minutes. You will choose how to pay next.',
            icon: Icons.lock_clock_outlined,
          ),
        ],
      ],
    ),
    bottomNavigationBar: BookingActionBar(
      total: (_quote?['total'] as num?)?.toDouble(),
      label: _busy
          ? 'Confirming...'
          : _confirmFailed
          ? 'Retry confirmation'
          : 'Confirm booking',
      hint: 'Next: choose a payment method',
      onPressed: _busy || _quote == null || (_error != null && !_confirmFailed)
          ? null
          : _confirm,
    ),
  );
}

class BookingPaymentPage extends StatefulWidget {
  const BookingPaymentPage({
    super.key,
    required this.service,
    required this.initialReceipt,
  });
  final CatalogService service;
  final Map<String, dynamic> initialReceipt;
  @override
  State<BookingPaymentPage> createState() => _BookingPaymentPageState();
}

class _BookingPaymentPageState extends State<BookingPaymentPage> {
  late Map<String, dynamic> _receipt;
  Map<String, dynamic> get _booking =>
      Map<String, dynamic>.from(_receipt['booking'] as Map);
  String? _method;
  String? _error;
  bool _busy = false;
  bool _decline = false;
  Timer? _poll;
  String _attemptId = newRequestId();
  @override
  void initState() {
    super.initState();
    _receipt = widget.initialReceipt;
    _method = _booking['payment'] as String?;
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_booking['paymentStatus'] == 'awaiting_counter' && !_busy) _refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool get _paid =>
      ['demo_paid', 'paid_at_counter'].contains(_booking['paymentStatus']);
  void _accept(Map<String, dynamic> result) {
    setState(() {
      _receipt = result;
      _error = null;
    });
    if (_paid) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BookingPassesPage(
            service: widget.service,
            bookingId: _booking['id'] as String,
            initialReceipt: result,
          ),
        ),
      );
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final data = await widget.service.request('bookings/${_booking['id']}');
      if (mounted) _accept(Map<String, dynamic>.from(data as Map));
    } on CatalogException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.request(
        'bookings/${_booking['id']}/payment',
        body: {
          'attemptId': _attemptId,
          'method': _method,
          if (_method == 'demo') 'outcome': _decline ? 'declined' : 'success',
        },
      );
      if (!mounted) return;
      _accept(Map<String, dynamic>.from(data as Map));
      if (_booking['paymentStatus'] == 'failed') {
        setState(() {
          _error =
              'Demo payment declined. No money was charged. Retry payment to continue.';
          _decline = false;
        });
        _attemptId = newRequestId();
      }
    } on CatalogException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unavailable = ['cancelled', 'expired'].contains(_booking['status']);
    final waiting =
        _booking['paymentStatus'] == 'awaiting_counter' && _method == 'counter';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_busy) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const MovieSeatPageTitle('Payment')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const BookingProgress(step: 4),
            const Text(
              'How would you like to pay?',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            BookingSummary(
              movie: Movie.fromJson(
                Map<String, dynamic>.from(_booking['movie'] as Map),
              ),
              date: _booking['date'] as String,
              showtime: _booking['showtime'] as String,
              seats: List<String>.from(_booking['seats'] as List),
            ),
            if (_booking['holdExpiresAt'] != null)
              UiNotice(
                title: 'Your seats are on hold',
                icon: Icons.timer_outlined,
                message:
                    'Please pay before ${DateTime.parse(_booking['holdExpiresAt'] as String).toUtc().add(const Duration(hours: 8)).toIso8601String().substring(11, 16)} (Philippine time).',
              ),
            if (_error != null)
              UiNotice(
                title: 'Payment needs attention',
                message: _error!,
                error: true,
              ),
            if (unavailable)
              UiNotice(
                title: 'Reservation ${_booking['status']}',
                message: 'Return to movies to choose a new screening.',
                error: true,
              )
            else ...[
              PaymentOption(
                title: 'Demo checkout - no money charged',
                subtitle:
                    'Try the complete booking flow without using a card or wallet.',
                icon: Icons.credit_card_outlined,
                selected: _method == 'demo',
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _method = 'demo';
                        _attemptId = newRequestId();
                      }),
              ),
              PaymentOption(
                title: 'Pay at cinema counter',
                subtitle:
                    'Staff will confirm your payment before your QR tickets are issued.',
                icon: Icons.storefront_outlined,
                selected: _method == 'counter',
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _method = 'counter';
                        _attemptId = newRequestId();
                      }),
              ),
              if (_method == 'demo')
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Demo test options'),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Demonstrate a declined payment'),
                      value: _decline,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _decline = value;
                              _attemptId = newRequestId();
                            }),
                    ),
                  ],
                ),
              if (waiting)
                const UiNotice(
                  title: 'Awaiting counter payment',
                  message:
                      'Awaiting counter payment. Tell staff your booking code. Your tickets will appear here when payment is confirmed.',
                  icon: Icons.storefront,
                ),
              if (waiting)
                SelectableText(
                  'Booking code: ${_booking['id']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              if (!waiting)
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Refresh payment status'),
                ),
            ],
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.popUntil(context, (route) => route.isFirst),
              child: const Text('Return to movies'),
            ),
            const Text(
              'Need to leave? Resume this reservation in My Tickets before the hold expires.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        bottomNavigationBar: BookingActionBar(
          total: (_booking['total'] as num).toDouble(),
          label: unavailable
              ? 'Start a new booking'
              : _busy
              ? 'Processing...'
              : waiting
              ? 'Refresh payment status'
              : _booking['paymentStatus'] == 'failed' || _error != null
              ? 'Retry payment'
              : _method == 'counter'
              ? 'Reserve for counter payment'
              : _method == null
              ? 'Choose a payment method'
              : 'Make payment',
          hint: waiting
              ? 'QR tickets appear after staff confirm payment'
              : 'Your QR tickets are issued after payment',
          onPressed: _busy
              ? null
              : unavailable
              ? () => Navigator.popUntil(context, (route) => route.isFirst)
              : waiting
              ? _refresh
              : _method == null
              ? null
              : _pay,
        ),
      ),
    );
  }
}

class QrPassCard extends StatelessWidget {
  const QrPassCard({
    super.key,
    required this.title,
    required this.token,
    this.redeemed = false,
  });
  final String title;
  final String token;
  final bool redeemed;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const MovieSeatLogo(width: 140, height: 40),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (redeemed)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Already redeemed'),
            )
          else
            Semantics(
              label: '$title QR code',
              image: true,
              child: QrImageView(
                data: token,
                version: QrVersions.auto,
                size: 220,
                padding: const EdgeInsets.all(24),
                backgroundColor: Colors.white,
              ),
            ),
          ExpansionTile(
            title: const Text('Backup code'),
            subtitle: const Text('Use this if scanning does not work'),
            children: [
              SelectableText(
                token,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (context.mounted) showApiError(context, 'Code copied.');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy backup code'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class BookingPassesPage extends StatefulWidget {
  const BookingPassesPage({
    super.key,
    required this.service,
    required this.bookingId,
    this.initialReceipt,
  });
  final CatalogService service;
  final String bookingId;
  final Map<String, dynamic>? initialReceipt;
  @override
  State<BookingPassesPage> createState() => _BookingPassesPageState();
}

class _BookingPassesPageState extends State<BookingPassesPage> {
  Map<String, dynamic>? _receipt;
  Map<String, dynamic>? _eligibility;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _receipt = widget.initialReceipt;
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final data = await widget.service.request('bookings/${widget.bookingId}');
      final result = Map<String, dynamic>.from(data as Map);
      if (mounted) {
        setState(() {
          _receipt = result;
          _error = null;
        });
      }
      final eligibility = await widget.service.request(
        'review-eligibility',
        query: {'movieId': result['booking']['movie']['id'] as String},
      );
      if (mounted) {
        setState(
          () => _eligibility = Map<String, dynamic>.from(eligibility as Map),
        );
      }
    } on CatalogException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = _receipt?['booking'] as Map?;
    final order = _receipt?['order'] as Map?;
    final paid =
        booking != null &&
        ['demo_paid', 'paid_at_counter'].contains(booking['paymentStatus']) &&
        booking['status'] == 'confirmed';
    return Scaffold(
      appBar: AppBar(
        title: const MovieSeatPageTitle('Tickets & food voucher'),
        actions: [
          IconButton(
            tooltip: 'Refresh passes',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          if (booking != null) ...[
            BookingProgress(step: paid ? 5 : 4),
            if (paid)
              const UiNotice(
                title: 'You are booked!',
                message:
                    'Your tickets are ready. Show each QR at the cinema entrance.',
                success: true,
                icon: Icons.check_circle_outline,
              ),
            Text(
              booking['movie']['title'] as String,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('${booking['date']} - ${booking['showtime']} - Cinema 1'),
            Text(
              '${booking['id']} - ${bookingStatusLabel(booking['status'] as String)}',
            ),
            Text(paymentLabel(booking['paymentStatus'] as String)),
            Text('Total: ${formatPeso((booking['total'] as num).toDouble())}'),
            if (!paid && !['cancelled', 'expired'].contains(booking['status']))
              FilledButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => BookingPaymentPage(
                      service: widget.service,
                      initialReceipt: _receipt!,
                    ),
                  ),
                ),
                child: const Text('Continue payment'),
              ),
            if (paid) ...[
              const SizedBox(height: 20),
              const Text(
                'Your seat tickets - show one QR for each person at the entrance.',
              ),
              for (final ticket in booking['tickets'] as List? ?? [])
                QrPassCard(
                  title: 'Seat ${ticket['seat']}',
                  token: ticket['token'] as String,
                  redeemed: ticket['redeemedAt'] != null,
                ),
              if (order != null) ...[
                const SizedBox(height: 20),
                const Text(
                  'Your food order',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                for (final item in order['items'] as List)
                  Text('${item['quantity']} x ${item['name']}'),
                if (order['status'] == 'cancelled')
                  const Text('Food order cancelled')
                else if (order['voucher'] != null)
                  QrPassCard(
                    title: 'Food voucher',
                    token: order['voucher']['token'] as String,
                    redeemed: order['voucher']['redeemedAt'] != null,
                  ),
                const Text(
                  'After entering the cinema, show this separate voucher at the food counter. It can be used once.',
                ),
              ],
              const SizedBox(height: 20),
              const Text('Enjoy your movie!'),
              Text(
                _eligibility?['reason'] as String? ??
                    'Review availability is being checked.',
              ),
              FilledButton.icon(
                onPressed: _eligibility?['eligible'] == true
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ReviewsPage(
                            movie: Movie.fromJson(
                              Map<String, dynamic>.from(
                                booking['movie'] as Map,
                              ),
                            ),
                            service: widget.service,
                          ),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.star),
                label: const Text('Rate and review'),
              ),
            ],
            TextButton(
              onPressed: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
              child: const Text('Done'),
            ),
          ],
        ],
      ),
    );
  }
}

class RedeemPassesPage extends StatefulWidget {
  const RedeemPassesPage({super.key, required this.service});
  final CatalogService service;
  @override
  State<RedeemPassesPage> createState() => _RedeemPassesPageState();
}

class _RedeemPassesPageState extends State<RedeemPassesPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _accepted = false;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.service.request(
        'admin/redeem',
        body: {'token': _code.text.trim()},
      );
      if (!mounted) return;
      setState(() {
        _accepted = true;
        _message = result['type'] == 'ticket'
            ? '${result['message']}\n${result['movie']}\nSeat ${result['seat']} - ${result['showtime']}'
            : '${result['message']}\n${(result['items'] as List).map((x) => '${x['quantity']} x ${x['name']}').join('\n')}';
        _code.clear();
      });
    } on CatalogException catch (e) {
      if (mounted) {
        setState(() {
          _accepted = false;
          _message = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const MovieSeatPageTitle('Cinema admission & food')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const MovieSeatLogo(),
        const SizedBox(height: 24),
        const Text(
          'Scan with your counter scanner, or paste a ticket or food voucher code below.',
        ),
        TextField(
          controller: _code,
          enabled: !_busy,
          onSubmitted: (_) => _redeem(),
          decoration: const InputDecoration(
            labelText: 'Ticket or food voucher code',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _redeem,
          child: Text(_busy ? 'Checking...' : 'Validate & redeem'),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _message!,
              style: TextStyle(
                color: _accepted ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ),
        const Text(
          'Each ticket admits one person. A food voucher can be claimed once. Used, unpaid, cancelled and expired passes are rejected.',
        ),
      ],
    ),
  );
}
