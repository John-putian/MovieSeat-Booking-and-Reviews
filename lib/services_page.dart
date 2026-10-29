import 'package:flutter/material.dart';

import 'catalog_models.dart';
import 'catalog_service.dart';
import 'catalog_widgets.dart';
import 'cinema_pages.dart';

/// "Snacks & Services" catalog: loads services.json from the MovieSeat API
/// with an HTTP GET request and shows it as a searchable list.
class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key, required this.service});

  final CatalogService service;

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  static const _allCategories = 'All';

  final _searchController = TextEditingController();

  List<ServiceItem> _items = const [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _category = _allCategories;
  final Map<String, int> _cart = {};
  Future<void> _openCart() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            CartPage(service: widget.service, items: _items, quantities: _cart),
      ),
    );
    if (mounted) setState(() {});
  }

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.fetchServices();
      if (!mounted) return;
      setState(() {
        _items = items;
        _cart.removeWhere((id, _) => !items.any((item) => item.id == id));
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

  /// Category chips, built from whatever categories the API returned.
  List<String> get _categories => [
    _allCategories,
    ...{for (final item in _items) item.category},
  ];

  /// The items that match both the search text and the selected chip.
  List<ServiceItem> get _filtered => _items
      .where(
        (item) =>
            (_category == _allCategories || item.category == _category) &&
            item.matches(_query),
      )
      .toList();

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _category = _allCategories;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OutlinedButton.icon(
                  onPressed: _openCart,
                  icon: const Icon(Icons.shopping_cart),
                  label: Text(
                    'Cart (${_cart.values.fold<int>(0, (a, b) => a + b)})',
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 4),
                child: Text(
                  'Snacks & Services',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'Food, drinks and extras for your movie',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: CatalogSearchField(
                  controller: _searchController,
                  hintText: 'Search snacks and services',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),
            if (!_loading && _error == null)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    children: [
                      for (final category in _categories)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(category),
                            selected: _category == category,
                            onSelected: (_) =>
                                setState(() => _category = category),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_loading)
              const SliverToBoxAdapter(
                child: CatalogLoading(label: 'Loading snacks and services…'),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: CatalogMessage(
                  icon: Icons.cloud_off_rounded,
                  title: "Couldn't load the catalog",
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: _load,
                ),
              )
            else if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: CatalogMessage(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  message: _query.trim().isEmpty
                      ? 'No items in this category.'
                      : 'Nothing matches "${_query.trim()}".',
                  actionLabel: 'Clear search',
                  actionIcon: Icons.close_rounded,
                  onAction: _clearFilters,
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Text(
                    '${filtered.length} of ${_items.length} items',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return ServiceCard(
                      item: item,
                      onTap: () => _showDetails(context, item),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, ServiceItem item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CatalogArtwork(
                height: 180,
                radius: 16,
                image: item.image,
                label: item.name,
                icon: item.icon,
                fit: BoxFit.contain,
                colors: [item.color, item.color],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CatalogArtwork(
                    width: 72,
                    height: 72,
                    radius: 16,
                    image: item.image,
                    label: item.name,
                    icon: item.icon,
                    colors: [item.color, item.color],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: !item.available
                    ? null
                    : () {
                        if ((_cart[item.id] ?? 0) >= 20) {
                          showApiError(context, 'Maximum 20 of each item.');
                          return;
                        }
                        setState(
                          () => _cart[item.id] = (_cart[item.id] ?? 0) + 1,
                        );
                        Navigator.pop(sheetContext);
                        showApiError(context, '${item.name} added to cart.');
                      },
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(item.available ? 'Add to cart' : 'Sold out'),
              ),
              const SizedBox(height: 16),
              Text(
                item.description,
                style: const TextStyle(height: 1.5, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Text(
                [
                  item.category,
                  if (item.size.isNotEmpty) item.size,
                  formatPeso(item.price),
                  item.available ? 'Available' : 'Sold out',
                ].join(' • '),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One snack or service in the list.
class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.item, required this.onTap});

  final ServiceItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CatalogArtwork(
                width: 68,
                height: 68,
                radius: 14,
                image: item.image,
                label: item.name,
                icon: item.icon,
                colors: [item.color, item.color],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        item.category,
                        if (item.size.isNotEmpty) item.size,
                      ].join(' • '),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatPeso(item.price),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.available ? 'Available' : 'Sold out',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: item.available
                          ? const Color(0xFF34D399)
                          : const Color(0xFFF87171),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
