import 'package:flutter/material.dart';

// Small widgets shared by the Movies and the Snacks & Services catalogs.

/// Search box used to filter a catalog list as the user types.
class CatalogSearchField extends StatelessWidget {
  const CatalogSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        );
      },
    );
  }
}

/// Spinner shown while the HTTP GET request is running.
class CatalogLoading extends StatelessWidget {
  const CatalogLoading({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(color: Colors.white60)),
        ],
      ),
    );
  }
}

/// Message with an icon and an optional button, used for errors
/// ("Try again") and for searches with no results ("Clear search").
class CatalogMessage extends StatelessWidget {
  const CatalogMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon = Icons.refresh_rounded,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.white38),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

String formatPeso(double amount) => amount == 0
    ? 'Free'
    : '\u20b1${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)}';

/// Bundled images work offline; administrators can also supply HTTPS images.
class CatalogArtwork extends StatelessWidget {
  const CatalogArtwork({
    super.key,
    required this.image,
    required this.label,
    this.width,
    this.height,
    this.radius = 0,
    this.fit = BoxFit.cover,
    this.icon = Icons.movie_outlined,
    this.colors = const [Color(0xFF312E81), Color(0xFF7C3AED)],
  });
  final String image;
  final String label;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;
  final IconData icon;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    Widget fallback() =>
        Center(child: Icon(icon, color: Colors.white70, size: 32));
    final uri = Uri.tryParse(image);
    final isNetwork =
        uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
    final Widget picture;
    if (image.startsWith('assets/images/')) {
      picture = Image.asset(
        image,
        fit: fit,
        cacheWidth: width == null ? null : (width! * 3).ceil(),
        semanticLabel: label,
        errorBuilder: (_, _, _) => fallback(),
      );
    } else if (isNetwork) {
      picture = Image.network(
        image,
        fit: fit,
        cacheWidth: width == null ? null : (width! * 3).ceil(),
        semanticLabel: label,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback(),
        errorBuilder: (_, _, _) => fallback(),
      );
    } else {
      picture = Semantics(label: label, image: true, child: fallback());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
          child: Stack(fit: StackFit.expand, children: [picture]),
        ),
      ),
    );
  }
}
