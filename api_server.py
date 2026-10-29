"""Persistent MovieSeat classroom API (Python standard library only)."""
import argparse
import copy
from contextlib import closing
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import sqlite3
import sys
from datetime import datetime, timedelta, timezone, date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs, unquote

ROOT = Path(__file__).resolve().parent

sys.path.insert(0, str(ROOT))
from booking_flow import (ApiError, UNHANDLED, checkout_flow, expire_holds, issue_documents,
                          issue_voucher, is_paid, review_eligibility)

def password_hash(password, salt):
    return hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1).hex()

def new_user(email, password, role='customer'):
    salt = secrets.token_hex(16)
    return dict(id=secrets.token_hex(12), email=email, salt=salt, password=password_hash(password, salt), role=role)

class Store:
    def __init__(self, path, admin_password, clock=None):
        self.path = str(path)
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute('CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY, data TEXT NOT NULL)')
            if db.execute('SELECT id FROM state').fetchone() is None:
                state = dict(movies=json.loads((ROOT / 'api/movies.json').read_text()),
                    services=json.loads((ROOT / 'api/services.json').read_text()),
                    users=[new_user('admin@movieseat.local', admin_password, 'admin')], sessions={},
                    bookings=[], orders=[], reviews=[], cinema=dict(rows=8, columns=8), blocked={})
                db.execute('INSERT INTO state VALUES (1, ?)', (json.dumps(state),))

    def request(self, method, path, query=None, body=None, token=''):
        with closing(sqlite3.connect(self.path, timeout=15)) as db, db:
            # Serialize validation and insertion: two customers cannot buy the same seat.
            db.execute('BEGIN IMMEDIATE')
            state = json.loads(db.execute('SELECT data FROM state WHERE id=1').fetchone()[0])
            original = copy.deepcopy(state)
            expire_holds(state, self.clock())
            result = self.dispatch(state, method, path, query or {}, body or {}, token)
            if method != 'GET' or state != original:
                db.execute('UPDATE state SET data=? WHERE id=1', (json.dumps(state),))
            return copy.deepcopy(result)

    def dispatch(self, s, method, path, q, b, token):
        if method == 'GET' and path in ('/movies', '/services', '/movies.json', '/services.json'):
            return s[path.strip('/').removesuffix('.json')]
        if method == 'POST' and path in ('/login', '/register'):
            email, password = str(b.get('email', '')).strip().lower(), str(b.get('password', ''))
            if len(email) > 254 or '@' not in email or not 8 <= len(password) <= 128:
                raise ApiError('Enter a valid email and a password of 8-128 characters.')
            user = next((u for u in s['users'] if u['email'] == email), None)
            if path == '/register':
                if user:
                    raise ApiError('This email is already registered.', 409)
                user = new_user(email, password)
                s['users'].append(user)
            elif user is None or not hmac.compare_digest(user['password'], password_hash(password, user['salt'])):
                raise ApiError('Incorrect email or password.', 401)
            session, now = secrets.token_urlsafe(32), self.clock()
            s['sessions'] = {k: v for k, v in s['sessions'].items() if v['expires'] > now.isoformat()}
            s['sessions'][session] = dict(userId=user['id'], expires=(now + timedelta(hours=24)).isoformat())
            return dict(token=session, email=user['email'], role=user['role'])
        session = s['sessions'].get(token)
        if not session or session['expires'] < self.clock().isoformat():
            raise ApiError('Please sign in again.', 401)
        user = next(u for u in s['users'] if u['id'] == session['userId'])
        if path.startswith('/admin') and user['role'] != 'admin':
            raise ApiError('Administrator access required.', 403)
        if method == 'POST' and path == '/logout':
            del s['sessions'][token]
            return dict(ok=True)

        flow_result = checkout_flow(s, method, path, q, b, user, self.clock())
        if flow_result is not UNHANDLED:
            return flow_result

        def show(data):
            movie = next((m for m in s['movies'] if m['id'] == data.get('movieId')), None)
            day = str(data.get('date', ''))
            try:
                selected = date.fromisoformat(day)
            except ValueError:
                raise ApiError('Choose a valid screening date.')
            today = self.clock().astimezone(timezone(timedelta(hours=8))).date()
            if selected < today or selected > today + timedelta(days=30):
                raise ApiError('Choose a screening within the next 30 days.')
            if not movie or data.get('showtime') not in movie['showtimes']:
                raise ApiError('This showtime is no longer available.', 409)
            return movie, '|'.join([movie['id'], day, data['showtime']])

        def seats():
            return [f'{chr(65+r)}{c+1}' for r in range(s['cinema']['rows']) for c in range(s['cinema']['columns'])]

        def taken(key):
            return set(s['blocked'].get(key, [])) | {seat for x in s['bookings']
                if x['screening'] == key and x['status'] in ('confirmed', 'pending_payment') for seat in x['seats']}

        def replay(collection):
            key = str(b.get('requestId', ''))
            if not key or len(key) > 128:
                raise ApiError('A request ID is required.')
            return next((x for x in s[collection] if x['userId'] == user['id'] and x.get('requestId') == key), None)

        def record(prefix):
            return dict(id=f'{prefix}-{secrets.token_hex(5).upper()}', userId=user['id'],
                email=user['email'], createdAt=self.clock().isoformat())

        if method == 'GET' and path == '/availability':
            _, key = show(q)
            return dict(**s['cinema'], seats=seats(), taken=sorted(taken(key)))
        if method == 'GET' and path in ('/bookings', '/orders'):
            for booking in s['bookings']:
                issue_documents(s, booking)
            for order in s['orders']:
                issue_voucher(order)
            return [x for x in s[path[1:]] if x['userId'] == user['id']][::-1]
        if method == 'POST' and path == '/bookings':
            previous = replay('bookings')
            if previous:
                return previous
            movie, key = show(b)
            selected = b.get('seats', [])
            if not isinstance(selected, list) or not 1 <= len(selected) <= 6 or any(not isinstance(x, str) for x in selected):
                raise ApiError('Select 1-6 seats.')
            if len(set(selected)) != len(selected) or not set(selected) <= set(seats()):
                raise ApiError('Invalid seat selection.')
            if set(selected) & taken(key):
                raise ApiError('Some seats were just taken. Refresh and select other seats.', 409)
            payment = b.get('payment')
            if payment not in ('demo', 'counter'):
                raise ApiError('Choose a payment method.')
            item = dict(**record('MS'), requestId=b['requestId'], movie=copy.deepcopy(movie), screening=key,
                date=b['date'], showtime=b['showtime'], seats=selected, total=round(movie['price'] * len(selected), 2),
                status='confirmed', payment=payment, paymentStatus='demo_paid' if payment == 'demo' else 'unpaid')
            s['bookings'].append(item)
            issue_documents(s, item)
            return item
        if method == 'POST' and path == '/orders':
            previous = replay('orders')
            if previous:
                return previous
            lines = b.get('items', [])
            if not isinstance(lines, list) or not 1 <= len(lines) <= 50:
                raise ApiError('Your cart is empty or too large.')
            items, seen = [], set()
            for line in lines:
                product = next((p for p in s['services'] if p['id'] == line.get('id')), None)
                quantity = line.get('quantity')
                if not product or not product['available']:
                    raise ApiError('A cart item is no longer available.', 409)
                if type(quantity) is not int or not 1 <= quantity <= 20 or product['id'] in seen:
                    raise ApiError('Choose 1-20 of each item.')
                seen.add(product['id'])
                items.append(dict(id=product['id'], name=product['name'], price=product['price'], quantity=quantity))
            item = dict(**record('FOOD'), requestId=b['requestId'], items=items,
                total=round(sum(x['price'] * x['quantity'] for x in items), 2), status='placed', paymentStatus='unpaid')
            s['orders'].append(item)
            return item
        if method == 'GET' and path == '/reviews':
            return [x for x in s['reviews'] if x['movieId'] == q.get('movieId')][::-1]
        if method == 'POST' and path == '/reviews':
            eligibility = review_eligibility(s, user['id'], b.get('movieId'), self.clock())
            if not eligibility['eligible']:
                raise ApiError(eligibility['reason'], 403)
            if not any(m['id'] == b.get('movieId') for m in s['movies']):
                raise ApiError('Movie not found.', 404)
            rating, comment = b.get('rating'), str(b.get('comment', '')).strip()
            if type(rating) is not int or not 1 <= rating <= 5 or not 1 <= len(comment) <= 1000:
                raise ApiError('Choose 1-5 stars and write a review of up to 1,000 characters.')
            item = next((x for x in s['reviews'] if x['movieId'] == b['movieId'] and x['userId'] == user['id']), None)
            if item is None:
                item = dict(**record('REV'), movieId=b['movieId'])
                s['reviews'].append(item)
            item.update(rating=rating, comment=comment)
            return item
        # REST resource routes share the same validated catalog operations as
        # older app versions. Permissions and booking protections apply to both.
        parts = path.strip('/').split('/')
        if parts[0] in ('movies', 'services'):
            kind = parts[0]
            if user['role'] != 'admin':
                raise ApiError('Administrator access required.', 403)
            if method == 'POST' and len(parts) == 1:
                item = dict(b)
                item['id'] = ('MOV-' if kind == 'movies' else 'SVC-') + secrets.token_hex(6).upper()
                b, path = dict(kind=kind, item=item), '/admin/catalog'
            elif method in ('PUT', 'DELETE') and len(parts) == 2:
                item_id = unquote(parts[1])
                if not any(x['id'] == item_id for x in s[kind]):
                    raise ApiError('Catalog item not found.', 404)
                if method == 'PUT':
                    if 'id' in b and b['id'] != item_id:
                        raise ApiError('The body ID must match the URL ID.')
                    item = dict(b, id=item_id)
                    b, path = dict(kind=kind, item=item), '/admin/catalog'
                else:
                    b, path = dict(kind=kind, id=item_id), '/admin/delete'
                method = 'POST'
            else:
                raise ApiError('Method not allowed for this catalog route.', 405)
        if method == 'GET' and path == '/admin/state':
            return {k: v for k, v in s.items() if k not in ('users', 'sessions')}
        if method == 'POST' and path == '/admin/catalog':
            kind, item = b.get('kind'), b.get('item')
            if kind not in ('movies', 'services') or not isinstance(item, dict):
                raise ApiError('Invalid catalog item.')
            validate_product(kind, item)
            existing = next((x for x in s[kind] if x['id'] == item['id']), None)
            if existing is not None:
                if kind == 'movies':
                    removed = set(existing['showtimes']) - set(item['showtimes'])
                    if any(x['movie']['id'] == item['id'] and x['status'] in ('confirmed', 'pending_payment') and x['showtime'] in removed for x in s['bookings']):
                        raise ApiError('Cancel affected bookings before removing a booked showtime.', 409)
                existing.clear()
                existing.update(item)
            else:
                s[kind].append(item)
            return item
        if method == 'POST' and path == '/admin/delete':
            kind, item_id = b.get('kind'), b.get('id')
            if kind not in ('movies', 'services', 'reviews'):
                raise ApiError('Invalid collection.')
            if kind == 'movies' and any(x['movie']['id'] == item_id and x['status'] in ('confirmed', 'pending_payment') for x in s['bookings']):
                raise ApiError('Cancel this movie\'s bookings before deleting it.', 409)
            s[kind] = [x for x in s[kind] if x['id'] != item_id]
            return dict(ok=True)
        if method == 'POST' and path == '/admin/status':
            kind = b.get('kind')
            allowed = dict(bookings=['pending_payment', 'confirmed', 'cancelled', 'expired'], orders=['awaiting_payment', 'placed', 'preparing', 'ready', 'completed', 'cancelled'])
            if kind not in allowed or b.get('status') not in allowed[kind]:
                raise ApiError('Invalid status.')
            item = next((x for x in s[kind] if x['id'] == b.get('id')), None)
            if item is None:
                raise ApiError('Record not found.', 404)
            if kind == 'bookings' and item['status'] == 'cancelled' and b['status'] == 'confirmed':
                if not set(item['seats']) <= set(seats()) or set(item['seats']) & taken(item['screening']):
                    raise ApiError('Seats are no longer available.', 409)
                show(dict(movieId=item['movie']['id'], date=item['date'], showtime=item['showtime']))
            target = b['status']
            if kind == 'orders' and item.get('bookingId') and target not in ('awaiting_payment', 'cancelled') and not is_paid(item):
                raise ApiError('The linked booking must be paid before food preparation or collection.', 409)
            if kind == 'orders' and target == 'completed' and item.get('voucher') and not item['voucher'].get('redeemedAt'):
                raise ApiError('Validate the food voucher to complete collection.', 409)
            if kind == 'bookings' and item.get('checkout'):
                if item['status'] == 'expired' and (target != 'expired' or b.get('markPaid')):
                    raise ApiError('Expired reservations cannot be restored or paid.', 409)
                if target in ('pending_payment', 'expired') and target != item['status']:
                    raise ApiError('This booking status cannot be set manually.')
                if target == 'cancelled' and (any(t.get('redeemedAt') for t in item.get('tickets', [])) or
                    any(o.get('voucher', {}).get('redeemedAt') for o in s['orders'] if o.get('bookingId') == item['id'])):
                    raise ApiError('Used tickets or food vouchers cannot be cancelled.', 409)
                if target == 'confirmed' and not is_paid(item) and not b.get('markPaid'):
                    raise ApiError('Record payment before confirming this reservation.')
            if b.get('markPaid'):
                if item['status'] in ('cancelled', 'expired'):
                    raise ApiError('This record cannot be paid.', 409)
                item['paymentStatus'] = 'paid_at_counter'
                if kind == 'bookings':
                    target = 'confirmed'
            item['status'] = target
            if kind == 'bookings':
                if target == 'cancelled':
                    for order in s['orders']:
                        if order.get('bookingId') == item['id'] and order['status'] != 'completed':
                            order['status'] = 'cancelled'
                issue_documents(s, item)
            else:
                if item.get('bookingId') and b.get('markPaid'):
                    raise ApiError('Record payment on the linked booking so seats and food settle together.')
                issue_voucher(item)
            return item
        if method == 'POST' and path == '/admin/cinema':
            rows, columns = b.get('rows'), b.get('columns')
            if type(rows) is not int or type(columns) is not int or not 1 <= rows <= 12 or not 1 <= columns <= 12:
                raise ApiError('Rows and columns must each be between 1 and 12.')
            valid = {f'{chr(65+r)}{c+1}' for r in range(rows) for c in range(columns)}
            if any(not set(x['seats']) <= valid for x in s['bookings'] if x['status'] in ('confirmed', 'pending_payment')) or any(not set(x) <= valid for x in s['blocked'].values()):
                raise ApiError('The new capacity would remove booked or blocked seats.', 409)
            s['cinema'] = dict(rows=rows, columns=columns)
            return s['cinema']
        if method == 'POST' and path == '/admin/seats':
            _, key = show(b)
            blocked = b.get('seats')
            if not isinstance(blocked, list) or any(not isinstance(x, str) for x in blocked) or not set(blocked) <= set(seats()):
                raise ApiError('Invalid seats.')
            booked = {seat for x in s['bookings'] if x['screening'] == key and x['status'] in ('confirmed', 'pending_payment') for seat in x['seats']}
            if set(blocked) & booked:
                raise ApiError('Cancel affected bookings before blocking those seats.', 409)
            s['blocked'][key] = sorted(set(blocked))
            return dict(ok=True)
        raise ApiError('Endpoint not found.', 404)

def validate_product(kind, item):
    fields = ['id', 'title', 'genre', 'duration', 'synopsis'] if kind == 'movies' else ['id', 'name', 'category', 'description', 'size', 'icon', 'color']
    if any(not isinstance(item.get(k), str) or len(item[k]) > 3000 for k in fields):
        raise ApiError('All text fields must be supplied.')
    if not item['id'].strip() or '|' in item['id'] or not item['title' if kind == 'movies' else 'name'].strip():
        raise ApiError('ID and name are required; ID cannot contain |.')
    image = item.get('image', '')
    if not isinstance(image, str) or len(image) > 2048:
        raise ApiError('Invalid image path.')
    if image and not (image.startswith('https://') or
                      (image.startswith('assets/images/') and '..' not in image)):
        raise ApiError('Use an HTTPS picture URL or bundled asset path.')
    price = item.get('price')
    if type(price) not in (int, float) or not 0 <= price <= 100000:
        raise ApiError('Price must be between 0 and 100,000.')
    if kind == 'movies':
        times, colors = item.get('showtimes'), item.get('colors')
        if not isinstance(times, list) or not times or any(not isinstance(t, str) or not t.strip() or '|' in t for t in times) or len(times) != len(set(times)):
            raise ApiError('Supply unique showtimes.')
        if not isinstance(colors, list) or len(colors) < 2 or any(not isinstance(c, str) for c in colors):
            raise ApiError('Supply at least two poster colors.')
        if type(item.get('rating')) not in (int, float) or not 0 <= item['rating'] <= 10:
            raise ApiError('Movie rating must be between 0 and 10.')
    elif type(item.get('available')) is not bool:
        raise ApiError('Availability must be true or false.')

def handler_for(store):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.respond()
        def do_POST(self):
            self.respond()
        def do_PUT(self):
            self.respond()
        def do_DELETE(self):
            self.respond()
        def respond(self):
            status = 200
            try:
                url = urlsplit(self.path)
                length = int(self.headers.get('Content-Length', 0))
                if not 0 <= length <= 100000:
                    raise ApiError('Request too large.', 413)
                body = json.loads(self.rfile.read(length)) if length else {}
                if not isinstance(body, dict):
                    raise ApiError('Expected a JSON object.')
                result = store.request(self.command, url.path, {k: v[0] for k, v in parse_qs(url.query).items()},
                    body, self.headers.get('Authorization', '').removeprefix('Bearer '))
                if self.command == 'POST' and url.path in ('/movies', '/services'):
                    status = 201
                elif self.command == 'DELETE':
                    status = 204
            except ApiError as exc:
                status, result = exc.status, dict(error=exc.message)
            except (ValueError, TypeError, KeyError, AttributeError):
                status, result = 400, dict(error='Invalid request data.')
            except Exception:
                import traceback
                traceback.print_exc()
                status, result = 500, dict(error='Server error. Please try again.')
            payload = b'' if status == 204 else json.dumps(result, allow_nan=False).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(payload)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(payload)
    return Handler

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8001)
    parser.add_argument('--host', default='0.0.0.0')
    parser.add_argument('--db', default=str(ROOT / 'api/movieseat.sqlite3'))
    args = parser.parse_args()
    password = os.environ.get('MOVIESEAT_ADMIN_PASSWORD') or secrets.token_urlsafe(12)
    if not 8 <= len(password) <= 128:
        parser.error('MOVIESEAT_ADMIN_PASSWORD must contain 8-128 characters.')
    first_run = not Path(args.db).exists()
    store = Store(args.db, password)
    if first_run:
        print(f'Administrator: admin@movieseat.local\nInitial password: {password}', flush=True)
    print(f'MovieSeat API listening on {args.host}:{args.port}. Keep this window open.', flush=True)
    ThreadingHTTPServer((args.host, args.port), handler_for(store)).serve_forever()
