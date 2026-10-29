import 'package:flutter/material.dart';
import 'catalog_service.dart';
import 'cinema_pages.dart';
import 'catalog_models.dart';
import 'catalog_widgets.dart';
import 'brand_widgets.dart';
import 'booking_journey.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.service});
  final CatalogService service;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  String _section = 'movies';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final data = await widget.service.request('admin/state');
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(data as Map);
          _error = null;
        });
      }
    } on CatalogException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _save(String path, Map<String, dynamic> body) async {
    try {
      await widget.service.request('admin/$path', body: body);
      await _load();
      return true;
    } on CatalogException catch (e) {
      if (mounted) showApiError(context, e);
      return false;
    }
  }

  Future<void> _delete(String kind, Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text('${item['title'] ?? item['name'] ?? item['comment']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      if (kind == 'movies') {
        await widget.service.deleteMovie(item['id'] as String);
      } else if (kind == 'services') {
        await widget.service.deleteService(item['id'] as String);
      } else {
        await widget.service.request(
          'admin/delete',
          body: {'kind': kind, 'id': item['id']},
        );
      }
      await _load();
    } on CatalogException catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _edit(String kind, [Map<String, dynamic>? original]) async {
    final movie = kind == 'movies';
    final item = Map<String, dynamic>.from(
      original ??
          (movie
              ? {
                  'id': 'MOV-${newRequestId()}',
                  'title': '',
                  'genre': '',
                  'duration': '',
                  'price': 280,
                  'synopsis': '',
                  'rating': 0,
                  'showtimes': ['10:30 AM'],
                  'colors': ['#312E81', '#7C3AED'],
                }
              : {
                  'id': 'SVC-${newRequestId()}',
                  'name': '',
                  'category': 'Snacks',
                  'description': '',
                  'price': 0,
                  'size': '',
                  'available': true,
                  'icon': 'popcorn',
                  'color': '#F59E0B',
                }),
    );
    item['image'] ??= defaultCatalogImage(item['id'] as String);
    final fields = movie
        ? [
            'title',
            'genre',
            'duration',
            'synopsis',
            'price',
            'rating',
            'showtimes',
            'image',
          ]
        : [
            'name',
            'category',
            'description',
            'price',
            'size',
            'icon',
            'color',
            'image',
          ];
    final controls = {
      for (final field in fields)
        field: TextEditingController(
          text: field == 'showtimes'
              ? (item[field] as List).join(', ')
              : '${item[field]}',
        ),
    };
    bool available = item['available'] as bool? ?? true;
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: Text(
            '${original == null ? 'Add' : 'Edit'} ${movie ? 'movie' : 'menu item'}',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: controls[field],
                        enabled: !saving,
                        decoration: InputDecoration(
                          labelText: field == 'showtimes'
                              ? 'Daily showtimes, separated by commas'
                              : field == 'image'
                              ? 'Picture (HTTPS URL or bundled asset path)'
                              : field,
                        ),
                        maxLines: field == 'description' || field == 'synopsis'
                            ? 3
                            : 1,
                      ),
                    ),
                  if (!movie)
                    SwitchListTile(
                      title: const Text('Available'),
                      value: available,
                      onChanged: saving
                          ? null
                          : (v) => update(() => available = v),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final price = double.tryParse(controls['price']!.text);
                      final rating = movie
                          ? double.tryParse(controls['rating']!.text)
                          : 0.0;
                      if (price == null ||
                          !price.isFinite ||
                          rating == null ||
                          !rating.isFinite) {
                        update(
                          () =>
                              error = 'Enter valid numeric prices and ratings.',
                        );
                        return;
                      }
                      for (final field in fields) {
                        item[field] = controls[field]!.text.trim();
                      }
                      item['price'] = price;
                      if (movie) {
                        item['rating'] = rating;
                        item['showtimes'] = controls['showtimes']!.text
                            .split(',')
                            .map((x) => x.trim())
                            .where((x) => x.isNotEmpty)
                            .toList();
                      } else {
                        item['available'] = available;
                      }
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        if (movie) {
                          final model = Movie.fromJson(item);
                          if (original == null) {
                            await widget.service.createMovie(model);
                          } else {
                            await widget.service.updateMovie(model);
                          }
                        } else {
                          final model = ServiceItem.fromJson(item);
                          if (original == null) {
                            await widget.service.createService(model);
                          } else {
                            await widget.service.updateService(model);
                          }
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await _load();
                      } on CatalogException catch (e) {
                        update(() {
                          error = e.message;
                          saving = false;
                        });
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
    // Dialog routes finish their closing animation before controllers are released.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final control in controls.values) {
      control.dispose();
    }
  }

  Future<void> _capacity() async {
    final cinema = _data!['cinema'] as Map;
    final rows = TextEditingController(text: '${cinema['rows']}');
    final cols = TextEditingController(text: '${cinema['columns']}');
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: const Text('Cinema capacity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'One auditorium. Rows and columns: 1–12 each. Booked seats cannot be removed.',
              ),
              TextField(
                controller: rows,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Rows'),
              ),
              TextField(
                controller: cols,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Columns'),
              ),
              if (error != null) Text(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      update(() => saving = true);
                      try {
                        await widget.service.request(
                          'admin/cinema',
                          body: {
                            'rows': int.tryParse(rows.text),
                            'columns': int.tryParse(cols.text),
                          },
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await _load();
                      } on CatalogException catch (e) {
                        update(() {
                          error = e.message;
                          saving = false;
                        });
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    rows.dispose();
    cols.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = (_data?[_section] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final cinema = _data?['cinema'] as Map?;
    return SafeArea(
      child: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cinema management',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh management data',
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          if (cinema != null)
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: Text(
                    'Capacity: ${(cinema['rows'] as int) * (cinema['columns'] as int)} seats',
                  ),
                  onPressed: _busy ? null : _capacity,
                ),
                ActionChip(
                  label: const Text('Validate tickets & food'),
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                RedeemPassesPage(service: widget.service),
                          ),
                        ),
                ),
                ActionChip(
                  label: const Text('Manage screening seats'),
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => AdminSeatsPage(
                              service: widget.service,
                              movies: (_data!['movies'] as List)
                                  .cast<Map<String, dynamic>>(),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButton<String>(
              isExpanded: true,
              value: _section,
              items: const [
                DropdownMenuItem(
                  value: 'movies',
                  child: Text('Movies & daily showtimes'),
                ),
                DropdownMenuItem(
                  value: 'services',
                  child: Text('Food & service menu'),
                ),
                DropdownMenuItem(value: 'bookings', child: Text('Bookings')),
                DropdownMenuItem(value: 'orders', child: Text('Food orders')),
                DropdownMenuItem(value: 'reviews', child: Text('Reviews')),
              ],
              onChanged: (value) => setState(() => _section = value!),
            ),
          ),
          if (_section == 'movies' || _section == 'services')
            FilledButton.icon(
              onPressed: _busy ? null : () => _edit(_section),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final x = items[index];
                final catalog = _section == 'movies' || _section == 'services';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (catalog)
                          CatalogArtwork(
                            width: 64,
                            height: 72,
                            radius: 8,
                            image:
                                x['image'] as String? ??
                                defaultCatalogImage(x['id'] as String),
                            label: '${x['title'] ?? x['name']}',
                            icon: Icons.local_movies,
                          ),

                        Text(
                          '${x['title'] ?? x['name'] ?? x['id']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (catalog)
                          Text(
                            _section == 'movies'
                                ? '₱${x['price']} • ${(x['showtimes'] as List).join(', ')}'
                                : '₱${x['price']} • ${x['available'] == true ? 'Available' : 'Sold out'}',
                          ),
                        if (_section == 'reviews')
                          Text(
                            '${x['rating']}/5 • ${x['movieId']}\n${x['comment']}',
                          ),
                        if (_section == 'bookings')
                          Text(
                            '${x['email']}\n${x['movie']['title']} • ${x['date']} • ${x['showtime']}\n'
                            'Seats: ${(x['seats'] as List).join(', ')} • ₱${x['total']}\n${paymentLabel(x['paymentStatus'] as String)}',
                          ),
                        if (_section == 'orders')
                          Text(
                            '${x['email']}\n${(x['items'] as List).map((i) => '${i['quantity']} × ${i['name']}').join(', ')}\n'
                            '₱${x['total']} • ${paymentLabel(x['paymentStatus'] as String)}',
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (catalog)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _edit(_section, x),
                                child: const Text('Edit'),
                              ),
                            if (catalog || _section == 'reviews')
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _delete(_section, x),
                                child: const Text('Delete'),
                              ),
                            if (_section == 'bookings' ||
                                _section == 'orders') ...[
                              DropdownButton<String>(
                                value: x['status'] as String,
                                items:
                                    (_section == 'bookings'
                                            ? [
                                                'pending_payment',
                                                'confirmed',
                                                'cancelled',
                                                'expired',
                                              ]
                                            : [
                                                'awaiting_payment',
                                                'placed',
                                                'preparing',
                                                'ready',
                                                'completed',
                                                'cancelled',
                                              ])
                                        .map(
                                          (v) => DropdownMenuItem(
                                            value: v,
                                            child: Text(bookingStatusLabel(v)),
                                          ),
                                        )
                                        .toList(),
                                onChanged: _busy
                                    ? null
                                    : (v) => _save('status', {
                                        'kind': _section,
                                        'id': x['id'],
                                        'status': v,
                                      }),
                              ),
                              if ([
                                    'unpaid',
                                    'failed',
                                    'awaiting_counter',
                                  ].contains(x['paymentStatus']) &&
                                  ![
                                    'cancelled',
                                    'expired',
                                  ].contains(x['status']) &&
                                  (_section == 'bookings' ||
                                      x['bookingId'] == null))
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _save('status', {
                                          'kind': _section,
                                          'id': x['id'],
                                          'status': x['status'],
                                          'markPaid': true,
                                        }),
                                  child: const Text('Mark paid at counter'),
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AdminSeatsPage extends StatefulWidget {
  const AdminSeatsPage({
    super.key,
    required this.service,
    required this.movies,
  });
  final CatalogService service;
  final List<Map<String, dynamic>> movies;
  @override
  State<AdminSeatsPage> createState() => _AdminSeatsPageState();
}

class _AdminSeatsPageState extends State<AdminSeatsPage> {
  String? _movieId;
  String? _time;
  DateTime _date = DateTime.now().toUtc().add(const Duration(hours: 8));
  final _blocked = TextEditingController();
  String? _message;
  bool _busy = false;
  @override
  void dispose() {
    _blocked.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _query => {
    'movieId': _movieId,
    'showtime': _time,
    'date': screeningDate(_date),
  };
  Future<void> _load() async {
    if (_movieId == null || _time == null) return;
    setState(() => _busy = true);
    try {
      final state = await widget.service.request('admin/state');
      final availability = await widget.service.request(
        'availability',
        query: _query.cast<String, String>(),
      );
      if (!mounted) return;
      final key = '$_movieId|${screeningDate(_date)}|$_time';
      _blocked.text = ((state['blocked'][key] ?? []) as List).join(', ');
      setState(
        () => _message =
            '${(availability['seats'] as List).length} seats; taken or blocked: ${(availability['taken'] as List).join(', ')}',
      );
    } on CatalogException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movies.where((m) => m['id'] == _movieId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const MovieSeatPageTitle('Screening seats')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButton<String>(
            isExpanded: true,
            value: _movieId,
            hint: const Text('Choose movie'),
            items: widget.movies
                .map(
                  (m) => DropdownMenuItem(
                    value: m['id'] as String,
                    child: Text(m['title'] as String),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _movieId = v;
                    _time = null;
                    _blocked.clear();
                    _message = null;
                  }),
          ),
          DropdownButton<String>(
            isExpanded: true,
            value: _time,
            hint: const Text('Choose showtime'),
            items: (movie?['showtimes'] as List? ?? [])
                .map(
                  (t) => DropdownMenuItem(value: t as String, child: Text(t)),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (v) {
                    setState(() => _time = v);
                    _load();
                  },
          ),
          TextButton.icon(
            icon: const Icon(Icons.calendar_month),
            label: Text(screeningDate(_date)),
            onPressed: _busy
                ? null
                : () async {
                    final today = DateTime.now().toUtc().add(
                      const Duration(hours: 8),
                    );
                    final day = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(today.year, today.month, today.day),
                      lastDate: today.add(const Duration(days: 30)),
                    );
                    if (day != null && mounted) {
                      setState(() => _date = day);
                      _load();
                    }
                  },
          ),
          if (_message != null) Text(_message!),
          const SizedBox(height: 16),
          TextField(
            controller: _blocked,
            enabled: !_busy && _time != null,
            decoration: const InputDecoration(
              labelText: 'Blocked seats, separated by commas',
              hintText: 'A1, A2, B3',
            ),
          ),
          const Text(
            'Leave blank to unblock all seats for this screening. Booked seats cannot be blocked.',
          ),
          FilledButton(
            onPressed: _busy || _time == null
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.service.request(
                        'admin/seats',
                        body: {
                          ..._query,
                          'seats': _blocked.text
                              .split(',')
                              .map((x) => x.trim().toUpperCase())
                              .where((x) => x.isNotEmpty)
                              .toList(),
                        },
                      );
                      await _load();
                    } on CatalogException catch (e) {
                      if (context.mounted) showApiError(context, e);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: const Text('Save blocked seats'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _load,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
