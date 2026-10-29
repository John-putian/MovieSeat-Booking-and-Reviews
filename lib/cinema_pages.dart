import 'package:flutter/material.dart';
import 'catalog_service.dart';
import 'catalog_models.dart';
import 'catalog_widgets.dart';
import 'brand_widgets.dart';
import 'booking_journey.dart';

void showApiError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
}

/// Server-backed list with explicit loading, error, empty and refresh states.
class ServerList extends StatefulWidget {
  const ServerList({
    super.key,
    required this.load,
    required this.builder,
    this.empty = 'Nothing here yet.',
  });
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(Map<String, dynamic>) builder;
  final String empty;
  @override
  State<ServerList> createState() => ServerListState();
}

class ServerListState extends State<ServerList> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> reload() async {
    final next = widget.load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      /* FutureBuilder displays the failure. */
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Refresh',
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const CatalogLoading(label: 'Loading…')
              else if (snapshot.hasError)
                CatalogMessage(
                  icon: Icons.cloud_off,
                  title: 'Unable to load',
                  message: '${snapshot.error}',
                  actionLabel: 'Try again',
                  onAction: reload,
                )
              else if (snapshot.data!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(widget.empty),
                )
              else
                ...snapshot.data!.map(widget.builder),
            ],
          ),
        ),
      );
}

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.service});
  final CatalogService service;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'My Tickets'),
              Tab(text: 'Food orders'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ServerList(
                  load: () => service.list('bookings'),
                  empty: 'No reservations yet.',
                  builder: (x) => Card(
                    child: ListTile(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => BookingPassesPage(
                            service: service,
                            bookingId: x['id'] as String,
                          ),
                        ),
                      ),
                      leading: CatalogArtwork(
                        width: 42,
                        height: 64,
                        radius: 6,
                        image: Movie.fromJson(
                          Map<String, dynamic>.from(x['movie'] as Map),
                        ).image,
                        label: x['movie']['title'] as String,
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const MovieSeatLogo(width: 110, height: 32),
                          Text(x['movie']['title'] as String),
                        ],
                      ),
                      subtitle: Text(
                        '${x['date']} • ${x['showtime']}\nSeats: ${(x['seats'] as List).join(', ')}\n'
                        '${x['id']} • ${bookingStatusLabel(x['status'] as String)}\n${paymentLabel(x['paymentStatus'] as String)}',
                      ),
                      trailing: Text(
                        formatPeso((x['total'] as num).toDouble()),
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
                ServerList(
                  load: () => service.list('orders'),
                  empty: 'No food orders yet.',
                  builder: (x) => Card(
                    child: ListTile(
                      onTap: () {
                        if (x['bookingId'] != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => BookingPassesPage(
                                service: service,
                                bookingId: x['bookingId'] as String,
                              ),
                            ),
                          );
                        } else if (x['voucher'] != null &&
                            x['status'] != 'cancelled') {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => SingleChildScrollView(
                              child: QrPassCard(
                                title: 'Food voucher',
                                token: x['voucher']['token'] as String,
                                redeemed: x['voucher']['redeemedAt'] != null,
                              ),
                            ),
                          );
                        } else {
                          showApiError(
                            context,
                            'Food vouchers become available after counter payment is recorded.',
                          );
                        }
                      },
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const MovieSeatLogo(width: 110, height: 32),
                          Text(
                            '${x['id']} - ${bookingStatusLabel(x['status'] as String)}',
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${(x['items'] as List).map((i) => '${i['quantity']} × ${i['name']}').join('\n')}\n'
                        '${paymentLabel(x['paymentStatus'] as String)}',
                      ),
                      trailing: Text(
                        formatPeso((x['total'] as num).toDouble()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class CartPage extends StatefulWidget {
  const CartPage({
    super.key,
    required this.service,
    required this.items,
    required this.quantities,
  });
  final CatalogService service;
  final List<ServiceItem> items;
  final Map<String, int> quantities;
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool _busy = false;
  String _requestId = newRequestId();
  Future<void> _checkout() async {
    setState(() => _busy = true);
    try {
      final result = await widget.service.request(
        'orders',
        body: {
          'requestId': _requestId,
          'items': widget.quantities.entries
              .map((e) => {'id': e.key, 'quantity': e.value})
              .toList(),
        },
      );
      if (!mounted) return;
      widget.quantities.clear();
      showApiError(
        context,
        'Order ${result['id']} placed. Pay at the cinema counter.',
      );
      Navigator.pop(context);
    } on CatalogException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.items
        .where((x) => widget.quantities.containsKey(x.id))
        .toList();
    final total = products.fold<double>(
      0,
      (sum, x) => sum + x.price * widget.quantities[x.id]!,
    );
    return Scaffold(
      appBar: AppBar(title: const MovieSeatPageTitle('Your cart')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final item in products)
            Card(
              child: ListTile(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CatalogArtwork(
                      width: 56,
                      height: 56,
                      radius: 8,
                      image: item.image,
                      label: item.name,
                      icon: item.icon,
                      colors: [item.color, item.color],
                    ),
                    const SizedBox(height: 6),
                    Text(item.name),
                  ],
                ),
                subtitle: Text('${formatPeso(item.price)} each'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              final n = widget.quantities[item.id]! - 1;
                              if (n == 0) {
                                widget.quantities.remove(item.id);
                              } else {
                                widget.quantities[item.id] = n;
                              }
                              _requestId = newRequestId();
                            }),
                      icon: const Icon(Icons.remove),
                    ),
                    Text('${widget.quantities[item.id]}'),
                    IconButton(
                      onPressed: _busy || widget.quantities[item.id]! >= 20
                          ? null
                          : () => setState(() {
                              widget.quantities[item.id] =
                                  widget.quantities[item.id]! + 1;
                              _requestId = newRequestId();
                            }),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ),
          if (products.isEmpty) const Text('Your cart is empty.'),
          const SizedBox(height: 20),
          Text(
            'Total: ${formatPeso(total)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Collect your order and pay at the cinema counter. Availability and prices are checked at checkout.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || products.isEmpty ? null : _checkout,
            child: Text(
              _busy ? 'Placing order…' : 'Place order — pay at cinema',
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewsPage extends StatefulWidget {
  const ReviewsPage({super.key, required this.movie, required this.service});
  final Movie movie;
  final CatalogService service;
  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  bool _eligible = false;
  bool _saved = false;
  String _eligibilityReason = 'Checking review availability...';
  @override
  void initState() {
    super.initState();
    _checkEligibility();
  }

  Future<void> _checkEligibility() async {
    try {
      final result = await widget.service.request(
        'review-eligibility',
        query: {'movieId': widget.movie.id},
      );
      if (mounted) {
        setState(() {
          _eligible = result['eligible'] == true;
          _eligibilityReason = result['reason'] as String;
        });
      }
    } on CatalogException catch (e) {
      if (mounted) setState(() => _eligibilityReason = e.message);
    }
  }

  final _listKey = GlobalKey<ServerListState>();
  final _comment = TextEditingController();
  int _rating = 5;
  bool _busy = false;
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_comment.text.trim().isEmpty) {
      showApiError(context, 'Write a review first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.request(
        'reviews',
        body: {
          'movieId': widget.movie.id,
          'rating': _rating,
          'comment': _comment.text.trim(),
        },
      );
      if (!mounted) return;
      _comment.clear();
      setState(() => _saved = true);
      showApiError(context, 'Your review has been saved.');
      await _listKey.currentState?.reload();
    } on CatalogException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: MovieSeatPageTitle('${widget.movie.title} reviews')),
    body: Column(
      children: [
        if (!_eligible)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_eligibilityReason),
          ),
        if (_eligible)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_saved) ...[
                  const Text('Thank you! Your review is saved.'),
                  TextButton(
                    onPressed: () =>
                        Navigator.popUntil(context, (route) => route.isFirst),
                    child: const Text('Finish'),
                  ),
                ],
                const Text('Write or update your review'),
                Wrap(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        tooltip: '$i stars',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _rating = i),
                        icon: Icon(
                          i <= _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                        ),
                      ),
                  ],
                ),
                TextField(
                  controller: _comment,
                  maxLength: 1000,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Your review'),
                ),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Saving…' : 'Submit review'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ServerList(
            key: _listKey,
            load: () => widget.service.list(
              'reviews',
              query: {'movieId': widget.movie.id},
            ),
            empty: 'Be the first to review this movie.',
            builder: (x) => Card(
              child: ListTile(
                title: Text('${x['rating']} / 5 stars'),
                subtitle: Text(x['comment'] as String),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
