# MovieSeat

Flutter cinema reservation and management app with a persistent local Python API.

## Run on the Android emulator

1. Double-click `start_api_server.bat` and leave it open. It uses the portable Python runtime in `.tools/python` when present; otherwise install Python 3.10 or newer and make `python` available on PATH.
2. On the **first start**, the server displays the administrator email (`admin@movieseat.local`) and a generated initial password. Save that password. Alternatively, set `MOVIESEAT_ADMIN_PASSWORD` (at least 8 characters) before the first start. Existing accounts are preserved on subsequent starts.
3. Start the Android emulator and run `flutter run`.
4. Customers choose **Create an account** on the login screen. Administrators sign in using the initial credentials and open the **Admin** tab.

The default API URL is `http://10.0.2.2:8001`, which reaches the development PC from the Android emulator. For a physical Android phone on the same Wi-Fi, use `flutter run --dart-define=API_BASE_URL=http://YOUR_PC_LAN_IP:8001` and allow the server through the PC firewall. The PC must stay on while the app is used.

## Customer features

- Register, sign in, and sign out using server-validated accounts.
- Browse movies loaded with HTTP GET, map JSON arrays into typed objects, and filter by title or genre.
- View daily showtimes and choose a screening date within the next 30 days (Philippine calendar dates).
- View shared seat availability, refreshed every three seconds. Choose 1-6 tickets and select exactly the same number of seats. The server atomically rejects conflicting bookings, including purchases submitted by different users at the same time. Seats are held for ten minutes after booking confirmation. They are released automatically if payment is not completed.
- After reviewing and confirming a booking, choose **pay at cinema** or a clearly labeled **demo payment**. Demo checkout does not charge money or collect card details. There is no live payment gateway.
- Retrieve saved tickets and their payment/booking status under **My Tickets**. Returning to that tab reloads history; pull down or tap Refresh to fetch administrator changes.
- Browse and search snacks, drinks, combos, and services; filter by category; add available items to a cart; adjust quantities; place an order for counter payment.
- View food order status under **My Tickets > Food orders**.
- Read reviews and submit/update one 1–5-star review per movie per customer.

## Administrator features

The server checks the administrator role for every management endpoint; hiding the tab is not the access control.

- Add, edit, and delete movies; edit ticket prices and daily showtimes.
- Add, edit, and delete food/menu items; change availability and prices.
- Review all bookings, cancel or restore bookings, and record counter payments. Cancellation releases seats. Restoring a booking checks seat availability again.
- Review food orders and update placed/preparing/ready/completed/cancelled status; record counter payments.
- View and delete reviews.
- Configure one auditorium's rows and columns (1–12 each). Capacity changes cannot remove booked or blocked seats.
- Block or unblock seats for an individual movie/date/showtime and inspect occupied seats. Booked seats must be cancelled before they can be blocked.

Pull down on customer catalogs or tap the management refresh button after editing catalog data. A booked showtime/movie cannot be removed until affected bookings are cancelled.

## Data and project scope

`api/movies.json` and `api/services.json` seed the database on the first start. Afterwards, the source of truth is `api/movieseat.sqlite3`. Accounts, sessions, bookings, orders, reviews, catalog edits, capacity, and blocked seats survive server and app restarts. Sign in again after restarting the app; sessions expire after 24 hours. Passwords use salted scrypt hashes. Keep the database backed up and out of source control.

This is a local classroom system with one auditorium and repeating daily schedules. Availability uses polling, rather than instant push updates. It uses HTTP for the local emulator connection. Public deployment, HTTPS, account recovery, refunds, and real online payment processing would require further work.

## Catalog assessment

| Criterion | Implementation |
|---|---|
| HTTP GET | `lib/catalog_service.dart` |
| JSON array to typed products | `Movie.fromJson` / `ServiceItem.fromJson` in `lib/catalog_models.dart` |
| Dynamic scrolling product lists | `SliverList.separated` in `lib/main.dart` and `lib/services_page.dart` |
| Search filtering | `matches` methods and `CatalogSearchField` |

## Validation

- `flutter analyze --no-pub`
- `flutter test --no-pub`
- `.tools\python\python.exe test\api_server_test.py` (or `python test/api_server_test.py` with installed Python)

Backend tests use temporary databases and a temporary HTTP server. They exercise authentication, administrator permissions, persistence, private history, concurrent seat conflicts, idempotency, cancellation, capacity, blocked seats, menu changes, order totals, review moderation, and actual HTTP transport. Flutter tests cover catalog search, cart checkout, review submission, seat polling, ticket checkout, and management editing.

## Catalog pictures

Original movie posters and food/service photographs are bundled in `assets/images/`, so default pictures work offline. The JSON field `image` selects each asset. Older saved catalog records automatically use their matching bundled pictures without resetting bookings or accounts.

In **Admin**, edit a movie or menu item and set **Picture** to a direct HTTPS image URL or a bundled path such as `assets/images/MOV-001.png`. Remote pictures need an internet connection. Missing or invalid images show the item's fallback icon. New local files must be added to `assets/images/` and included in a rebuilt app.

Generation prompts and asset information are in `assets/IMAGE_PROMPTS.md`.

## REST CRUD integration

MovieSeat applies the GET/POST/PUT/DELETE pattern from the supplied Flutter REST API integration guide to its cinema catalog. The HTTP package is already installed; no additional package is required.

| Action | HTTP method and route | Success |
|---|---|---|
| Browse movies or menu items | `GET /movies`, `GET /services` | 200 + JSON array |
| Create catalog item (admin) | `POST /movies`, `POST /services` | 201 + item with server-assigned ID |
| Update catalog item (admin) | `PUT /movies/{id}`, `PUT /services/{id}` | 200 + updated item |
| Delete catalog item (admin) | `DELETE /movies/{id}`, `DELETE /services/{id}` | 204, empty body |

`Movie` and `ServiceItem` implement both `fromJson` and `toJson`, including artwork, colors, and icon keys. `CatalogService` exposes typed create/update/delete methods and sends JSON bodies with the content type and session token. The Admin add/edit dialogs await successful writes before closing and refreshing their lists. Delete actions ask for confirmation. Errors remain visible, and booking protections still apply to movie updates/deletion. Existing legacy JSON routes and management endpoints remain supported for compatibility with earlier app builds.

After changing API code, restart `api_server.py` so the running server uses the new routes. The existing SQLite database is preserved.

## MovieSeat branding

The shared logo is used on sign-in/registration, the main header, movie navigation, detail/seat/cart/review headers, tickets, food receipts, and administration screens. Dark screens place the original logo on a light backing to preserve contrast. All brand artwork is local and works offline; sign-in no longer downloads a font.

`assets/branding/movieseat-logo.png` is the original horizontal logo and `movieseat-mark.png` is its square icon companion. `lib/brand_widgets.dart` centralizes their use. Brand prompts are recorded in `assets/branding/LOGO_PROMPT.md` and `BRAND_VARIANTS.md`.

Platform resources include Android adaptive/legacy launcher icons and launch screens, iOS icons and launch artwork, macOS icons, Windows icons, and web/PWA icons. The browser, PWA, desktop window and iOS display names use MovieSeat. Android builds are verified on the emulator; native Apple/Windows builds require their respective toolchains. The packaging scripts in `tools/` resize the approved mark into platform icon sizes.

## Booking journey

The customer journey follows the supplied flowchart:

1. Register or log in, browse movies, and select a movie/showtime.
2. Choose a screening date and 1-6 tickets. A showtime that has already passed defaults to tomorrow; started screenings cannot be purchased.
3. Select exactly the same number of seats as tickets. Shared availability still refreshes every three seconds.
4. Choose **Add food & beverages** and select quantities, or **Skip add-ons**.
5. Review ticket details, add-ons, subtotals, and the combined total calculated by the server.
6. Confirm booking. The server atomically holds the seats and creates a linked food order, if any, pending payment.
7. Choose a payment method and make payment. **Demo checkout** simulates success or decline without charging money. A declined payment shows **Retry payment**. Network retries reuse the same attempt ID. **Pay at cinema counter** waits for an administrator to record payment on the booking; it settles food and tickets together.
8. After successful payment, view a separate scannable QR ticket for each seat and one separate QR food voucher when add-ons were purchased. My Tickets retains passes and lets customers resume pending payment during the ten-minute hold.
9. Staff open **Admin > Validate tickets & food**, scan with a counter keyboard scanner or paste a copied code, and validate admission. This screen does not include phone-camera scanning. Each ticket admits one customer for its screening on the correct date, before the screening ends.
10. After admission, claim food using the separate voucher. Tickets and vouchers are single-use; unpaid/cancelled/expired codes are rejected.
11. Watch the movie. Rating/review submission unlocks only after admission and the screening end time. Submit a review and select **Finish**.

Quotes expire after ten minutes. Prices and seat availability are checked again at confirmation. An unpaid ten-minute hold expires automatically, cancels its unfulfilled linked food order, and releases the seats. Expired reservations cannot be paid or restored. Movie/food prices, payment state, pass tokens, admission, redemption, and review eligibility are validated by the server. Paid demo records are visibly labeled as demonstrations throughout.

New API routes are `POST /checkout/quote`, `POST /checkout`, `GET /bookings/{id}`, `POST /bookings/{id}/payment`, `GET /review-eligibility?movieId=...`, and `POST /admin/redeem`. `booking_flow.py` contains the transaction-safe journey rules; `lib/booking_journey.dart` contains the corresponding screens. QR rendering uses [qr_flutter](https://pub.dev/packages/qr_flutter).

Additional checks: `.tools\python\python.exe test/booking_flow_test.py` and `flutter test --no-pub test/booking_journey_test.dart`. These cover both add-on branches, combined totals, ticket counts, held-seat conflicts, expiry, declined/network payment retries, counter settlement, separate passes, single-use redemption, and review eligibility.

## Clearer booking interface

The booking screens share a five-step progress guide, movie/date/seat summaries, and a fixed bottom action area with the current subtotal or total. Ticket quantity uses large plus/minus controls. Payment methods are visible selection cards. Optional food can always be added or skipped from the fixed bottom controls. Demo decline controls are tucked under an optional section, and QR backup codes are collapsed until needed. Sign-in uses persistent field labels, autofill, a show/hide-password control, and a clear loading/disabled button state. Shared interface components are in `lib/ui_widgets.dart`.
