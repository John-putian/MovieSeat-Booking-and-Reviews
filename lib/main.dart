import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog_models.dart';
import 'catalog_service.dart';
import 'catalog_widgets.dart';
import 'login_page.dart';
import 'services_page.dart';
import 'cinema_pages.dart';
import 'admin_page.dart';
import 'brand_widgets.dart';
import 'booking_journey.dart';
import 'ui_widgets.dart';

void main() {
  runApp(const MovieSeatApp());
}

class MovieSeatApp extends StatefulWidget {
  const MovieSeatApp({super.key});

  @override
  State<MovieSeatApp> createState() => _MovieSeatAppState();
}

class _MovieSeatAppState extends State<MovieSeatApp> {
  final List<MovieBooking> _bookings = [];

  void _addBooking(MovieBooking booking) {
    setState(() => _bookings.insert(0, booking));
  }

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF8B5CF6);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MovieSeat',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0B1B),
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: const Color(0xFF1B1726),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white10),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 52),
            textStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: const Color(0xFFDECEFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          height: 72,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
      ),
      home: LoginPage(bookings: _bookings, onBooked: _addBooking),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.bookings,
    required this.onBooked,
    this.catalogService,
  });

  final List<MovieBooking> bookings;
  final ValueChanged<MovieBooking> onBooked;

  /// Loads the catalogs from the MovieSeat API. Tests pass a fake one.
  final CatalogService? catalogService;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  int _activityRevision = 0;

  late final CatalogService _catalog =
      widget.catalogService ?? CatalogService();

  @override
  Widget build(BuildContext context) {
    final pages = [
      MoviesPage(
        service: _catalog,
        bookings: widget.bookings,
        onBooked: widget.onBooked,
      ),
      ServicesPage(service: _catalog),
      ActivityPage(key: ValueKey(_activityRevision), service: _catalog),
      if (_catalog.isAdmin) AdminPage(service: _catalog),
    ];

    // Use light status-bar icons on the dark cinema screens.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Flexible(child: MovieSeatLogo(width: 170, height: 44)),
              if (_catalog.isAdmin) ...[
                const SizedBox(width: 12),
                const Text('Admin', style: TextStyle(fontSize: 14)),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                try {
                  await _catalog.signOut();
                } catch (_) {
                  /* Local session is cleared. */
                }
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LoginPage(bookings: const [], onBooked: (_) {}),
                  ),
                  (_) => false,
                );
              },
            ),
          ],
        ),
        body: IndexedStack(index: _selectedIndex, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
              if (index == 2) _activityRevision++;
            });
          },
          destinations: [
            NavigationDestination(
              icon: MovieSeatMark(size: 30),
              selectedIcon: MovieSeatMark(size: 32),
              label: 'Movies',
            ),
            NavigationDestination(
              icon: Icon(Icons.fastfood_outlined),
              selectedIcon: Icon(Icons.fastfood_rounded),
              label: 'Snacks',
            ),
            NavigationDestination(
              icon: Icon(Icons.confirmation_number_outlined),
              selectedIcon: Icon(Icons.confirmation_number_rounded),
              label: 'My Tickets',
            ),
            if (_catalog.isAdmin)
              const NavigationDestination(
                icon: Icon(Icons.admin_panel_settings),
                label: 'Admin',
              ),
          ],
        ),
      ),
    );
  }
}

/// "Now Showing" catalog: loads movies.json from the MovieSeat API with an
/// HTTP GET request, maps the JSON array to Movie objects and shows them in
/// a searchable list.
class MoviesPage extends StatefulWidget {
  const MoviesPage({
    super.key,
    required this.service,
    required this.bookings,
    required this.onBooked,
  });

  final CatalogService service;
  final List<MovieBooking> bookings;
  final ValueChanged<MovieBooking> onBooked;

  @override
  State<MoviesPage> createState() => _MoviesPageState();
}

class _MoviesPageState extends State<MoviesPage> {
  final _searchController = TextEditingController();

  List<Movie> _movies = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Runs the GET request and stores the result (or the error message).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final movies = await widget.service.fetchMovies();
      if (!mounted) return;
      setState(() {
        _movies = movies;
        _loading = false;
      });
    } on CatalogException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _openMovie(BuildContext context, Movie movie) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MovieDetailsPage(
          movie: movie,
          service: widget.service,
          bookings: widget.bookings,
          onBooked: widget.onBooked,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Search filtering: keep only movies whose title or genre matches.
    final filtered = _movies.where((movie) => movie.matches(_query)).toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  children: [
                    const MovieSeatMark(size: 48),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your movie night',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Pick a movie and reserve your seat',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: CatalogSearchField(
                  controller: _searchController,
                  hintText: 'Search movies by title or genre',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Now Showing',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!_loading && _error == null)
                      Text(
                        '${filtered.length} of ${_movies.length}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: CatalogLoading(label: 'Loading movies from the API…'),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: CatalogMessage(
                  icon: Icons.cloud_off_rounded,
                  title: "Couldn't load movies",
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: _load,
                ),
              )
            else if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: CatalogMessage(
                  icon: Icons.search_off_rounded,
                  title: 'No movies found',
                  message: _query.trim().isEmpty
                      ? 'There are no movies showing right now.'
                      : 'No movie matches "${_query.trim()}".',
                  actionLabel: _query.trim().isEmpty ? null : 'Clear search',
                  actionIcon: Icons.close_rounded,
                  onAction: _clearSearch,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final movie = filtered[index];
                    return MovieCard(
                      movie: movie,
                      onTap: () => _openMovie(context, movie),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MovieCard extends StatelessWidget {
  const MovieCard({super.key, required this.movie, required this.onTap});

  final Movie movie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // IntrinsicHeight lets the card grow with its text (no fixed height),
        // while the poster on the left still stretches to the full card height.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CatalogArtwork(
                width: 94,
                image: movie.image,
                label: '${movie.title} poster',
                colors: movie.colors,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${movie.genre} • ${movie.duration}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        movie.synopsis,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: Color(0xFFFBBF24),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            movie.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          FilledButton.tonal(
                            onPressed: onTap,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('View'),
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
      ),
    );
  }
}

class MovieDetailsPage extends StatelessWidget {
  const MovieDetailsPage({
    super.key,
    required this.movie,
    required this.service,
    required this.bookings,
    required this.onBooked,
  });

  final Movie movie;
  final CatalogService service;
  final List<MovieBooking> bookings;
  final ValueChanged<MovieBooking> onBooked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const MovieSeatPageTitle('Movie Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          CatalogArtwork(
            height: 320,
            radius: 24,
            image: movie.image,
            label: '${movie.title} poster',
            colors: movie.colors,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 24),
          Text(
            movie.title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip(icon: Icons.category_outlined, text: movie.genre),
              InfoChip(icon: Icons.schedule_rounded, text: movie.duration),
              InfoChip(
                icon: Icons.star_rounded,
                text: movie.rating.toStringAsFixed(1),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            movie.synopsis,
            style: const TextStyle(
              height: 1.5,
              fontSize: 15,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ReviewsPage(movie: movie, service: service),
              ),
            ),
            icon: const Icon(Icons.reviews),
            label: const Text('Read reviews'),
          ),
          const Text(
            'Choose a showtime',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...movie.showtimes.map(
            (showtime) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                tileColor: Colors.white.withValues(alpha: 0.06),
                leading: const CircleAvatar(
                  child: Icon(Icons.schedule_rounded),
                ),
                title: Text(
                  showtime,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Cinema 1 • ${formatPeso(movie.price)} per seat',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TicketQuantityPage(
                        movie: movie,
                        showtime: showtime,
                        seatBuilder: (count, date) => SeatSelectionPage(
                          movie: movie,
                          service: service,
                          showtime: showtime,
                          bookings: bookings,
                          onBooked: onBooked,
                          ticketCount: count,
                          initialDate: date,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 17), const SizedBox(width: 6), Text(text)],
      ),
    );
  }
}

class SeatSelectionPage extends StatefulWidget {
  const SeatSelectionPage({
    super.key,
    required this.movie,
    required this.showtime,
    required this.service,
    required this.bookings,
    required this.onBooked,
    this.ticketCount = 1,
    this.initialDate,
  });

  final int ticketCount;
  final DateTime? initialDate;
  final Movie movie;
  final String showtime;
  final CatalogService service;
  final List<MovieBooking> bookings;
  final ValueChanged<MovieBooking> onBooked;

  @override
  State<SeatSelectionPage> createState() => _SeatSelectionPageState();
}

class _SeatSelectionPageState extends State<SeatSelectionPage> {
  Set<String> _takenSeats = {};
  List<String> _seats = [];
  int _columns = 8;
  final Set<String> _selectedSeats = {};
  Timer? _poll;
  bool _refreshing = false;
  bool _busy = false;
  String? _error;
  DateTime _date = DateTime.now().toUtc().add(const Duration(hours: 8));

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? _date;
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final date = screeningDate(_date);
    try {
      final data = await widget.service.request(
        'availability',
        query: {
          'movieId': widget.movie.id,
          'showtime': widget.showtime,
          'date': date,
        },
      );
      if (!mounted || date != screeningDate(_date)) return;
      setState(() {
        _error = null;
        _seats = List<String>.from(data['seats'] as List);
        _columns = data['columns'] as int;
        _takenSeats = Set<String>.from(data['taken'] as List);
        if (_selectedSeats.any(_takenSeats.contains)) {
          _selectedSeats.removeAll(_takenSeats);
          showApiError(
            context,
            'Some selected seats were taken. Please check your selection.',
          );
        }
      });
    } on CatalogException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _chooseDate() async {
    final today = DateTime.now().toUtc().add(const Duration(hours: 8));
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 30)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _date = selected;
      _selectedSeats.clear();
      _seats = [];
      _error = null;
    });
    await _refresh();
  }

  void _toggleSeat(String seat) {
    if (_busy || _error != null || _takenSeats.contains(seat)) return;

    setState(() {
      if (_selectedSeats.contains(seat)) {
        _selectedSeats.remove(seat);
      } else if (_selectedSeats.length < widget.ticketCount) {
        _selectedSeats.add(seat);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Select exactly ${widget.ticketCount} seats for your tickets.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _continueBooking() async {
    if (_selectedSeats.length != widget.ticketCount ||
        _busy ||
        _error != null) {
      return;
    }
    final selected = _selectedSeats.toList()..sort();
    _poll?.cancel();
    setState(() => _busy = true);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AddOnsChoicePage(
          service: widget.service,
          selection: BookingSelection(
            movie: widget.movie,
            showtime: widget.showtime,
            date: screeningDate(_date),
            ticketCount: widget.ticketCount,
            seats: selected,
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (mounted) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const MovieSeatPageTitle('Select Seats')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: BookingProgress(step: 1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text(
                widget.movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _chooseDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                '${friendlyDate(context, screeningDate(_date))} - ${widget.showtime}',
              ),
            ),
            Text(
              'Select ${widget.ticketCount} seats - ${_selectedSeats.length}/${widget.ticketCount} selected',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              )
            else
              Text('${_seats.length - _takenSeats.length} seats available'),
            Container(
              width: MediaQuery.sizeOf(context).width * 0.72,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.45),
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'SCREEN',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                itemCount: _seats.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  mainAxisExtent: 44,
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 7,
                ),
                itemBuilder: (context, index) {
                  final seat = _seats[index];
                  final isReserved = _takenSeats.contains(seat);
                  final isSelected = _selectedSeats.contains(seat);

                  return SeatTile(
                    seat: seat,
                    isReserved: isReserved,
                    isSelected: isSelected,
                    onTap: () => _toggleSeat(seat),
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  SeatLegend(color: Color(0xFF2A263C), label: 'Available'),
                  SeatLegend(color: Color(0xFF8B5CF6), label: 'Selected'),
                  SeatLegend(color: Color(0xFF545064), label: 'Reserved'),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BookingActionBar(
        label:
            'Continue with ${widget.ticketCount} seat${widget.ticketCount == 1 ? '' : 's'}',
        total: widget.movie.price * widget.ticketCount,
        totalLabel: 'Ticket subtotal',
        hint: _selectedSeats.length == widget.ticketCount
            ? 'Next: optional food & beverages'
            : 'Select ${widget.ticketCount - _selectedSeats.length} more seat${widget.ticketCount - _selectedSeats.length == 1 ? '' : 's'} to continue',
        onPressed:
            _selectedSeats.length == widget.ticketCount &&
                !_busy &&
                _error == null
            ? _continueBooking
            : null,
      ),
    );
  }
}

class SeatTile extends StatelessWidget {
  const SeatTile({
    super.key,
    required this.seat,
    required this.isReserved,
    required this.isSelected,
    required this.onTap,
  });

  final String seat;
  final bool isReserved;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isReserved
        ? const Color(0xFF545064)
        : isSelected
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF2A263C);

    return Semantics(
      button: true,
      label: 'Seat $seat',
      selected: isSelected,
      enabled: !isReserved,
      child: InkWell(
        onTap: isReserved ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            seat,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isReserved ? Colors.white38 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class SeatLegend extends StatelessWidget {
  const SeatLegend({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class BookingsPage extends StatelessWidget {
  const BookingsPage({super.key, required this.bookings});

  final List<MovieBooking> bookings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Text(
              'My Tickets',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: bookings.isEmpty
                ? const EmptyBookings()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: bookings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      return BookingCard(booking: bookings[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class EmptyBookings extends StatelessWidget {
  const EmptyBookings({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.confirmation_number_outlined,
              size: 72,
              color: Colors.white30,
            ),
            SizedBox(height: 16),
            Text(
              'No reservations yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Your confirmed movie tickets will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking});

  final MovieBooking booking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: booking.movie.colors,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.movie.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const MovieSeatMark(size: 38),
            ],
          ),
          const SizedBox(height: 16),
          Text('${booking.showtime} • Cinema 1'),
          const SizedBox(height: 5),
          Text('Seats: ${booking.seats.join(', ')}'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  booking.code,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '₱${booking.total.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MovieBooking {
  const MovieBooking({
    required this.movie,
    required this.showtime,
    required this.seats,
    required this.total,
    required this.bookedAt,
    required this.code,
  });

  final Movie movie;
  final String showtime;
  final List<String> seats;
  final double total;
  final DateTime bookedAt;
  final String code;
}
