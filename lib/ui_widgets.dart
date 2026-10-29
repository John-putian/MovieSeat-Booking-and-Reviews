import 'package:flutter/material.dart';
import 'catalog_models.dart';
import 'catalog_widgets.dart';

class BookingProgress extends StatelessWidget {
  const BookingProgress({super.key, required this.step});
  final int step;
  static const labels = ['Tickets', 'Seats', 'Food', 'Review', 'Payment'];
  @override
  Widget build(BuildContext context) => Semantics(
    label: step >= 5
        ? 'Booking complete'
        : 'Step ${step + 1} of 5: ${labels[step]}',
    child: Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step >= 5 ? 'BOOKING COMPLETE' : 'STEP ${step + 1} OF 5',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 4 ? 0 : 6),
                    child: Column(
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: i <= step
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white12,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          labels[i],
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == step
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: i <= step ? Colors.white : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

String friendlyDate(BuildContext context, String date) {
  final parsed = DateTime.tryParse(date);
  return parsed == null
      ? date
      : MaterialLocalizations.of(context).formatMediumDate(parsed);
}

class BookingSummary extends StatelessWidget {
  const BookingSummary({
    super.key,
    required this.movie,
    required this.date,
    required this.showtime,
    this.seats = const [],
    this.onChangeDate,
  });
  final Movie movie;
  final String date;
  final String showtime;
  final List<String> seats;
  final VoidCallback? onChangeDate;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CatalogArtwork(
            width: 56,
            height: 82,
            radius: 8,
            image: movie.image,
            label: '${movie.title} poster',
            colors: movie.colors,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movie.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${friendlyDate(context, date)} - $showtime',
                  style: const TextStyle(color: Colors.white70),
                ),
                const Text('Cinema 1', style: TextStyle(color: Colors.white54)),
                if (onChangeDate != null)
                  TextButton.icon(
                    onPressed: onChangeDate,
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: const Text('Change date'),
                  ),
                if (seats.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final seat in seats)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF33264D),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              seat,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFE3D5FF),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
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

class BookingActionBar extends StatelessWidget {
  const BookingActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.total,
    this.totalLabel = 'Total',
    this.hint,
  });
  final String label;
  final VoidCallback? onPressed;
  final double? total;
  final String totalLabel;
  final String? hint;
  @override
  Widget build(BuildContext context) => SafeArea(
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
          if (total != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '$totalLabel: ${formatPeso(total!)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(label),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );
}

class UiNotice extends StatelessWidget {
  const UiNotice({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.info_outline,
    this.error = false,
    this.success = false,
  });
  final String title;
  final String? message;
  final IconData icon;
  final bool error;
  final bool success;
  @override
  Widget build(BuildContext context) {
    final color = error
        ? const Color(0xFFFFB4AB)
        : success
        ? const Color(0xFF8FE3BB)
        : const Color(0xFFD5C5FF);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      message!,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentOption extends StatelessWidget {
  const PaymentOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? const Color(0xFF302242) : const Color(0xFF1B1726),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? const Color(0xFFB59CFF) : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFD2BFFF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? const Color(0xFFB59CFF) : Colors.white38,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
