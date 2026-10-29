import 'package:flutter/material.dart';

/// Shared identity for login, page headers and ticket/order receipts.
class MovieSeatLogo extends StatelessWidget {
  const MovieSeatLogo({
    super.key,
    this.width = 180,
    this.height = 52,
    this.onDark,
  });
  final double width;
  final double height;
  final bool? onDark;
  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    final logo = Image.asset(
      'assets/branding/movieseat-logo.png',
      fit: BoxFit.contain,
      semanticLabel: 'MovieSeat',
    );
    return SizedBox(
      width: width,
      height: height,
      child: dark
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: logo,
              ),
            )
          : logo,
    );
  }
}

class MovieSeatMark extends StatelessWidget {
  const MovieSeatMark({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/movieseat-mark.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'MovieSeat logo',
  );
}

class MovieSeatPageTitle extends StatelessWidget {
  const MovieSeatPageTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const MovieSeatMark(size: 32),
      const SizedBox(width: 8),
      Flexible(
        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}
