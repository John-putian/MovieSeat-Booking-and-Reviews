import concurrent.futures
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from datetime import datetime, timezone, timedelta
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from api_server import Store, ApiError, handler_for, ThreadingHTTPServer

class CinemaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = Path(self.temp.name) / 'cinema.sqlite3'
        self.store = Store(self.db, 'admin-pass-123')
        self.admin = self.call('POST', '/login', dict(email='admin@movieseat.local', password='admin-pass-123'))['token']
        self.customer = self.call('POST', '/register', dict(email='customer@example.com', password='customer-pass'))['token']
        self.other = self.call('POST', '/register', dict(email='other@example.com', password='customer-pass'))['token']
        self.day = datetime.now(timezone(timedelta(hours=8))).date().isoformat()
        self.screen = dict(movieId='MOV-001', date=self.day, showtime='10:30 AM')
    def tearDown(self):
        self.temp.cleanup()
    def call(self, method, path, body=None, token='', query=None):
        return self.store.request(method, path, query, body, token)
    def book(self, request_id='one', seats=None, token=None, **extra):
        return self.call('POST', '/bookings', dict(**self.screen, seats=seats or ['A1'],
            requestId=request_id, payment='counter', **extra), token or self.customer)
    def test_catalog_is_json_array_and_login_is_real(self):
        self.assertEqual(len(self.call('GET', '/movies.json')), 8)
        self.assertEqual(len(self.call('GET', '/services.json')), 12)
        with self.assertRaises(ApiError):
            self.call('POST', '/login', dict(email='customer@example.com', password='wrong-password'))
    def test_role_and_session_enforced(self):
        for token in ['', self.customer]:
            with self.assertRaises(ApiError):
                self.call('GET', '/admin/state', token=token)
        self.call('POST', '/logout', token=self.customer)
        with self.assertRaises(ApiError):
            self.call('GET', '/bookings', token=self.customer)
    def test_booking_persists_and_history_is_private(self):
        booking = self.book(total=1)
        self.assertEqual(booking['total'], 280)
        self.store = Store(self.db, 'unused-password')
        self.assertEqual(self.call('GET', '/bookings', token=self.customer)[0]['id'], booking['id'])
        self.assertEqual(self.call('GET', '/bookings', token=self.other), [])
        taken = self.call('GET', '/availability', token=self.other, query=self.screen)['taken']
        self.assertIn('A1', taken)
    def test_idempotent_booking(self):
        self.assertEqual(self.book()['id'], self.book()['id'])
        self.assertEqual(len(self.call('GET', '/bookings', token=self.customer)), 1)
    def test_concurrent_seat_conflict(self):
        def attempt(index):
            try:
                return self.book(str(index), token=[self.customer, self.other][index])['id']
            except ApiError as e:
                return e.status
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, [0, 1]))
        self.assertEqual(results.count(409), 1)
    def test_cancellation_releases_seat_and_restore_detects_conflict(self):
        first = self.book()
        self.call('POST', '/admin/status', dict(kind='bookings', id=first['id'], status='cancelled'), self.admin)
        self.book('two', token=self.other)
        with self.assertRaises(ApiError):
            self.call('POST', '/admin/status', dict(kind='bookings', id=first['id'], status='confirmed'), self.admin)
    def test_capacity_and_blocked_seats(self):
        self.call('POST', '/admin/seats', dict(**self.screen, seats=['A1']), self.admin)
        with self.assertRaises(ApiError): self.book()
        self.call('POST', '/admin/seats', dict(**self.screen, seats=[]), self.admin)
        self.book(seats=['H8'])
        with self.assertRaises(ApiError):
            self.call('POST', '/admin/cinema', dict(rows=4, columns=4), self.admin)
        self.call('POST', '/admin/cinema', dict(rows=9, columns=8), self.admin)
        self.assertEqual(len(self.call('GET', '/availability', token=self.customer, query=self.screen)['seats']), 72)
    def test_orders_use_server_prices_and_persist(self):
        payload = dict(requestId='order-1', items=[dict(id='SVC-001', quantity=2, price=1)])
        order = self.call('POST', '/orders', payload, self.customer)
        self.assertEqual(order['total'], 240)
        self.assertEqual(order['id'], self.call('POST', '/orders', payload, self.customer)['id'])
        self.call('POST', '/admin/status', dict(kind='orders', id=order['id'], status='ready', markPaid=True), self.admin)
        saved = self.call('GET', '/orders', token=self.customer)[0]
        self.assertEqual(saved['status'], 'ready')
        self.assertEqual(saved['paymentStatus'], 'paid_at_counter')
    def test_unavailable_order_rejected(self):
        with self.assertRaises(ApiError):
            self.call('POST', '/orders', dict(requestId='bad', items=[dict(id='SVC-006', quantity=1)]), self.customer)
    def test_review_upsert_and_moderation(self):
        self.store.clock = lambda: datetime.fromisoformat(self.day + 'T00:00:00+00:00')
        booking = self.call('POST', '/bookings', dict(**self.screen, seats=['A1'], requestId='review-ticket', payment='demo'), self.customer)
        self.call('POST', '/admin/redeem', dict(token=booking['tickets'][0]['token']), self.admin)
        self.store.clock = lambda: datetime.fromisoformat(self.day + 'T06:00:00+00:00')
        payload = dict(movieId='MOV-001', rating=4, comment='Great movie')
        first = self.call('POST', '/reviews', payload, self.customer)
        payload.update(rating=5)
        self.assertEqual(self.call('POST', '/reviews', payload, self.customer)['id'], first['id'])
        self.assertEqual(len(self.call('GET', '/reviews', token=self.customer, query=dict(movieId='MOV-001'))), 1)
        self.call('POST', '/admin/delete', dict(kind='reviews', id=first['id']), self.admin)
        self.assertEqual(self.call('GET', '/reviews', token=self.customer, query=dict(movieId='MOV-001')), [])
    def test_catalog_management_protects_bookings(self):
        self.book()
        movie = self.call('GET', '/movies.json')[0]
        movie['showtimes'] = ['9:00 PM']
        with self.assertRaises(ApiError):
            self.call('POST', '/admin/catalog', dict(kind='movies', item=movie), self.admin)
        with self.assertRaises(ApiError):
            self.call('POST', '/admin/delete', dict(kind='movies', id=movie['id']), self.admin)
        item = self.call('GET', '/services.json')[0]
        item.update(price=135, available=False)
        self.call('POST', '/admin/catalog', dict(kind='services', item=item), self.admin)
        self.assertFalse(self.call('GET', '/services.json')[0]['available'])
    def test_rest_catalog_permissions_and_missing_records(self):
        product = self.call('GET', '/services')[0]
        for method, path in [('POST', '/services'), ('PUT', '/services/SVC-001'), ('DELETE', '/services/SVC-001')]:
            with self.assertRaises(ApiError) as error:
                self.call(method, path, product, self.customer)
            self.assertEqual(error.exception.status, 403)
        for method in ['PUT', 'DELETE']:
            with self.assertRaises(ApiError) as error:
                self.call(method, '/services/missing', product, self.admin)
            self.assertEqual(error.exception.status, 404)

    def test_rest_updates_and_deletes_protect_booked_movies(self):
        self.book()
        movie = self.call('GET', '/movies')[0]
        movie['showtimes'] = ['9:00 PM']
        for method, body in [('PUT', movie), ('DELETE', None)]:
            with self.assertRaises(ApiError) as error:
                self.call(method, '/movies/MOV-001', body, self.admin)
            self.assertEqual(error.exception.status, 409)
        movie['showtimes'] = ['10:30 AM']
        movie['id'] = 'wrong-id'
        with self.assertRaises(ApiError):
            self.call('PUT', '/movies/MOV-001', movie, self.admin)

    def test_rest_crud_over_http(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler_for(self.store))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f'http://127.0.0.1:{server.server_port}'
        def send(method, path, body=None):
            request = Request(base + path, method=method,
                data=json.dumps(body).encode() if body is not None else None,
                headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + self.admin})
            with urlopen(request) as response:
                data = response.read()
                return response.status, json.loads(data) if data else None
        try:
            for collection in ['movies', 'services']:
                template = self.call('GET', '/' + collection)[0]
                template.pop('id')
                status, created = send('POST', '/' + collection, template)
                self.assertEqual(status, 201)
                self.assertTrue(created['id'])
                created['price'] = 321.5
                path = '/' + collection + '/' + created['id']
                status, updated = send('PUT', path, created)
                self.assertEqual(status, 200)
                self.assertEqual(updated['price'], 321.5)
                self.store = Store(self.db, 'unused-password')
                self.assertTrue(any(x['id'] == created['id'] and x['price'] == 321.5
                    for x in self.call('GET', '/' + collection)))
                self.assertEqual(send('DELETE', path), (204, None))
                self.assertFalse(any(x['id'] == created['id'] for x in self.call('GET', '/' + collection)))
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_actual_http_transport_and_authentication(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler_for(self.store))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            with urlopen(base + '/movies.json') as response:
                self.assertEqual(len(json.load(response)), 8)
            request = Request(base + '/orders', data=json.dumps(dict(requestId='http', items=[dict(id='SVC-005', quantity=1)])).encode(),
                headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + self.customer})
            with urlopen(request) as response:
                self.assertEqual(json.load(response)['total'], 40)
            with self.assertRaises(HTTPError) as error:
                urlopen(base + '/admin/state')
            self.assertEqual(error.exception.code, 401)
        finally:
            server.shutdown(); server.server_close(); thread.join()

if __name__ == '__main__':
    unittest.main()
