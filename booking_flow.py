"""Combined booking, payment and cinema redemption workflow."""
import copy
import secrets
import re
from datetime import datetime, timedelta, timezone

MANILA = timezone(timedelta(hours=8))
UNHANDLED = object()

class ApiError(Exception):
    def __init__(self, message, status=400):
        self.message, self.status = message, status

def is_paid(record):
    return record.get('paymentStatus') in ('demo_paid', 'paid_at_counter')

def screening_end(booking):
    try:
        start = datetime.strptime(booking['date'] + ' ' + booking['showtime'], '%Y-%m-%d %I:%M %p').replace(tzinfo=MANILA)
        duration = booking['movie'].get('duration', '')
        hours = re.search(r'(\d+)\s*h', duration)
        minutes = re.search(r'(\d+)\s*m', duration)
        return start + timedelta(hours=int(hours[1]) if hours else 0, minutes=int(minutes[1]) if minutes else 0)
    except (ValueError, KeyError, TypeError):
        return None

def expire_holds(state, now):
    for booking in state['bookings']:
        if booking['status'] == 'pending_payment' and booking.get('holdExpiresAt', '') <= now.isoformat():
            booking.update(status='expired', paymentStatus='expired')
            for order in state['orders']:
                if order.get('bookingId') == booking['id'] and not is_paid(order):
                    order['status'] = 'cancelled'
    quotes = state.get('quotes', {})
    state['quotes'] = {key: value for key, value in quotes.items() if value['expiresAt'] > now.isoformat()}

def issue_documents(state, booking):
    if booking['status'] != 'confirmed' or not is_paid(booking):
        return
    if not booking.get('tickets'):
        booking['tickets'] = [dict(seat=seat, token='MS-T-' + secrets.token_urlsafe(24), redeemedAt=None)
                              for seat in booking['seats']]
    for order in state['orders']:
        if order.get('bookingId') == booking['id']:
            order['paymentStatus'] = booking['paymentStatus']
            if order['status'] == 'awaiting_payment':
                order['status'] = 'placed'
            issue_voucher(order)

def issue_voucher(order):
    if is_paid(order) and order['status'] != 'cancelled' and not order.get('voucher'):
        order['voucher'] = dict(token='MS-F-' + secrets.token_urlsafe(24), redeemedAt=None)

def review_eligibility(state, user_id, movie_id, now):
    attended = [b for b in state['bookings'] if b['userId'] == user_id and b['movie']['id'] == movie_id
        and b['status'] == 'confirmed' and is_paid(b) and any(t.get('redeemedAt') for t in b.get('tickets', []))]
    if any(screening_end(b) and screening_end(b) <= now for b in attended):
        return dict(eligible=True, reason='You can now rate and review this movie.')
    return dict(eligible=False, reason='Reviews unlock after your ticket is checked at the cinema and your screening has ended.')

def receipt(state, booking):
    return dict(booking=booking, order=next((o for o in state['orders'] if o.get('bookingId') == booking['id']), None))

def checkout_flow(state, method, path, query, body, user, now):
    def record(prefix):
        return dict(id=prefix + '-' + secrets.token_hex(6).upper(), userId=user['id'], email=user['email'], createdAt=now.isoformat())

    def calculate(data):
        movie = next((m for m in state['movies'] if m['id'] == data.get('movieId')), None)
        try:
            day = datetime.strptime(str(data.get('date', '')), '%Y-%m-%d').date()
        except ValueError:
            raise ApiError('Choose a valid screening date.')
        today = now.astimezone(MANILA).date()
        if day < today or day > today + timedelta(days=30) or not movie or data.get('showtime') not in movie['showtimes']:
            raise ApiError('This screening is no longer available.', 409)
        # Do not sell a screening that has already begun.
        try:
            start = datetime.strptime(data['date'] + ' ' + data['showtime'], '%Y-%m-%d %I:%M %p').replace(tzinfo=MANILA)
        except ValueError:
            raise ApiError('This screening has an invalid showtime.')
        if start <= now:
            raise ApiError('This screening has already started. Choose another showtime or date.', 409)
        count, selected = data.get('ticketCount'), data.get('seats')
        if type(count) is not int or not 1 <= count <= 6 or not isinstance(selected, list) or len(selected) != count or any(not isinstance(x, str) for x in selected):
            raise ApiError('Select exactly one seat for each ticket (1-6 tickets).')
        valid = {f'{chr(65+r)}{c+1}' for r in range(state['cinema']['rows']) for c in range(state['cinema']['columns'])}
        key = '|'.join([movie['id'], data['date'], data['showtime']])
        taken = set(state['blocked'].get(key, [])) | {seat for b in state['bookings'] if b['screening'] == key
            and b['status'] in ('confirmed', 'pending_payment') for seat in b['seats']}
        if len(set(selected)) != count or not set(selected) <= valid:
            raise ApiError('Invalid or duplicate seats.')
        if set(selected) & taken:
            raise ApiError('Some seats were just taken. Return to seat selection.', 409)
        lines = data.get('items', [])
        if not isinstance(lines, list) or len(lines) > 50:
            raise ApiError('Invalid food selection.')
        items, seen = [], set()
        for line in lines:
            if not isinstance(line, dict):
                raise ApiError('Invalid food item.')
            product = next((p for p in state['services'] if p['id'] == line.get('id')), None)
            quantity = line.get('quantity')
            if not product or not product['available'] or product['category'] not in ('Snacks', 'Drinks', 'Combos'):
                raise ApiError('A food item is no longer available.', 409)
            if type(quantity) is not int or not 1 <= quantity <= 20 or product['id'] in seen:
                raise ApiError('Choose 1-20 of each food item.')
            seen.add(product['id'])
            items.append(dict(id=product['id'], name=product['name'], price=product['price'], quantity=quantity))
        ticket_total = round(movie['price'] * count, 2)
        food_total = round(sum(x['price'] * x['quantity'] for x in items), 2)
        return dict(movie=copy.deepcopy(movie), movieId=movie['id'], date=data['date'], showtime=data['showtime'],
            ticketCount=count, seats=sorted(selected), screening=key, items=items,
            ticketTotal=ticket_total, foodTotal=food_total, total=round(ticket_total + food_total, 2))

    if method == 'GET' and path == '/review-eligibility':
        return review_eligibility(state, user['id'], query.get('movieId'), now)
    if method == 'POST' and path == '/checkout/quote':
        quote = dict(**calculate(body), quoteId=secrets.token_urlsafe(24), userId=user['id'],
                     expiresAt=(now + timedelta(minutes=10)).isoformat())
        state.setdefault('quotes', {})[quote['quoteId']] = quote
        return quote
    if method == 'POST' and path == '/checkout':
        request_id = body.get('requestId')
        if not isinstance(request_id, str) or not 1 <= len(request_id) <= 128:
            raise ApiError('A request ID is required.')
        previous = next((b for b in state['bookings'] if b['userId'] == user['id'] and b.get('requestId') == request_id), None)
        if previous:
            return receipt(state, previous)
        quote = state.get('quotes', {}).get(body.get('quoteId'))
        if not quote or quote['userId'] != user['id'] or quote['expiresAt'] <= now.isoformat():
            raise ApiError('Your price review expired. Review the booking again.', 409)
        current = calculate(quote)
        if current['ticketTotal'] != quote['ticketTotal'] or current['items'] != quote['items']:
            raise ApiError('Prices changed. Review the booking again.', 409)
        booking = dict(**record('MS'), **{key: current[key] for key in ['movie', 'screening', 'date', 'showtime',
            'seats', 'ticketCount', 'ticketTotal', 'foodTotal', 'total']}, requestId=request_id, checkout=True,
            status='pending_payment', paymentStatus='unpaid', payment=None, tickets=[], paymentAttempts=[],
            holdExpiresAt=(now + timedelta(minutes=10)).isoformat())
        if current['items']:
            order = dict(**record('FOOD'), bookingId=booking['id'], items=current['items'],
                         total=current['foodTotal'], status='awaiting_payment', paymentStatus='unpaid')
            state['orders'].append(order)
        state['bookings'].append(booking)
        return receipt(state, booking)
    parts = path.strip('/').split('/')
    if len(parts) in (2, 3) and parts[0] == 'bookings':
        booking = next((b for b in state['bookings'] if b['id'] == parts[1] and b['userId'] == user['id']), None)
        if booking is None:
            raise ApiError('Booking not found.', 404)
        if method == 'GET' and len(parts) == 2:
            issue_documents(state, booking)
            return receipt(state, booking)
        if method == 'POST' and parts[2:] == ['payment']:
            if booking['status'] in ('cancelled', 'expired'):
                raise ApiError('This reservation is no longer payable. Start a new booking.', 409)
            if is_paid(booking):
                issue_documents(state, booking)
                return receipt(state, booking)
            attempt_id = body.get('attemptId')
            if not isinstance(attempt_id, str) or not 1 <= len(attempt_id) <= 128:
                raise ApiError('A payment attempt ID is required.')
            attempts = booking.setdefault('paymentAttempts', [])
            if any(a['id'] == attempt_id for a in attempts):
                return receipt(state, booking)
            payment = body.get('method')
            if payment == 'counter':
                booking.update(payment='counter', paymentStatus='awaiting_counter')
                outcome = 'awaiting_counter'
            elif payment == 'demo' and body.get('outcome') in ('success', 'declined'):
                outcome = body['outcome']
                if outcome == 'success':
                    booking.update(status='confirmed', payment='demo', paymentStatus='demo_paid')
                    issue_documents(state, booking)
                else:
                    booking.update(payment='demo', paymentStatus='failed')
            else:
                raise ApiError('Choose demo checkout or payment at the cinema counter.')
            attempts.append(dict(id=attempt_id, outcome=outcome, createdAt=now.isoformat()))
            return receipt(state, booking)
    if method == 'POST' and path == '/admin/redeem':
        if user['role'] != 'admin':
            raise ApiError('Administrator access required.', 403)
        code = str(body.get('token', '')).strip()
        for booking in state['bookings']:
            for ticket in booking.get('tickets', []):
                if ticket['token'] == code:
                    if not is_paid(booking) or booking['status'] != 'confirmed':
                        raise ApiError('This ticket is not valid for admission.', 409)
                    if ticket.get('redeemedAt'):
                        raise ApiError('This ticket has already been used.', 409)
                    if booking['date'] != now.astimezone(MANILA).date().isoformat() or not screening_end(booking) or screening_end(booking) <= now:
                        raise ApiError('This ticket is not valid for admission at this time.', 409)
                    ticket['redeemedAt'] = now.isoformat()
                    return dict(type='ticket', seat=ticket['seat'], movie=booking['movie']['title'],
                                date=booking['date'], showtime=booking['showtime'], message='Admission accepted.')
        for order in state['orders']:
            voucher = order.get('voucher')
            if voucher and voucher['token'] == code:
                if not is_paid(order) or order['status'] == 'cancelled':
                    raise ApiError('This food voucher is not valid.', 409)
                booking = next((b for b in state['bookings'] if b['id'] == order.get('bookingId')), None)
                if booking and (booking['status'] != 'confirmed' or not is_paid(booking)
                    or booking['date'] != now.astimezone(MANILA).date().isoformat()
                    or not any(t.get('redeemedAt') for t in booking.get('tickets', []))):
                    raise ApiError('Present the paid ticket for this screening before claiming food.', 409)
                if voucher.get('redeemedAt'):
                    raise ApiError('This food voucher has already been claimed.', 409)
                voucher['redeemedAt'] = now.isoformat()
                order['status'] = 'completed'
                return dict(type='food', items=order['items'], message='Food voucher accepted. Hand over these items.')
        raise ApiError('Ticket or voucher code not found.', 404)
    return UNHANDLED
