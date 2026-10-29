import concurrent.futures
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from api_server import Store, ApiError

class BookingFlowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.now = datetime(2026, 10, 27, 0, 0, tzinfo=timezone.utc) # 08:00 Manila
        self.path = Path(self.temp.name) / 'flow.sqlite3'
        self.store = Store(self.path, 'admin-password', clock=lambda: self.now)
        self.admin = self.call('POST', '/login', {'email': 'admin@movieseat.local', 'password': 'admin-password'}, token='')['token']
        self.customer = self.call('POST', '/register', {'email': 'viewer@example.com', 'password': 'viewer-password'}, token='')['token']
        self.other = self.call('POST', '/register', {'email': 'other@example.com', 'password': 'viewer-password'}, token='')['token']
        self.screen = dict(movieId='MOV-001', date='2026-10-27', showtime='10:30 AM', ticketCount=2, seats=['A1','A2'])
    def tearDown(self):
        self.temp.cleanup()
    def call(self, method, path, body=None, token=None, query=None):
        return self.store.request(method, path, query, body, token if token is not None else self.customer)
    def quote(self, food=True, token=None, **changes):
        data = dict(self.screen, items=[dict(id='SVC-001', quantity=2)] if food else [])
        data.update(changes)
        return self.call('POST', '/checkout/quote', data, token)
    def checkout(self, food=True, request_id='checkout-one', token=None):
        quote = self.quote(food, token)
        return self.call('POST', '/checkout', dict(quoteId=quote['quoteId'], requestId=request_id), token)
    def pay(self, booking, outcome='success', attempt='payment-one', method='demo'):
        return self.call('POST', '/bookings/' + booking['id'] + '/payment', dict(method=method, outcome=outcome, attemptId=attempt))
    def test_exact_ticket_count_required(self):
        with self.assertRaises(ApiError): self.quote(ticketCount=3)
        with self.assertRaises(ApiError): self.quote(seats=['A1','A1'])
        with self.assertRaises(ApiError): self.quote(ticketCount=0, seats=[])
        self.assertEqual(self.call('GET', '/bookings'), [])
    def test_combined_total_and_skip_addons(self):
        quote = self.quote()
        self.assertEqual((quote['ticketTotal'], quote['foodTotal'], quote['total']), (560,240,800))
        result = self.checkout(food=False)
        self.assertIsNone(result['order'])
        self.assertEqual(result['booking']['total'],560)
        self.assertEqual(result['booking']['tickets'],[])
    def test_decline_retry_separate_passes_and_persistence(self):
        result = self.checkout()
        booking = result['booking']
        self.assertEqual(result['order']['status'], 'awaiting_payment')
        failed = self.pay(booking, outcome='declined')
        self.assertEqual(failed['booking']['paymentStatus'],'failed')
        self.assertEqual(failed['booking']['tickets'],[])
        self.assertNotIn('voucher', failed['order'])
        result = self.pay(booking, attempt='retry')
        tickets = result['booking']['tickets']
        self.assertEqual(len(tickets), 2)
        self.assertEqual(len({t['token'] for t in tickets}), 2)
        self.assertEqual(result['order']['status'], 'placed')
        self.assertTrue(result['order']['voucher']['token'].startswith('MS-F-'))
        self.assertEqual(self.pay(booking, attempt='retry')['booking']['tickets'], tickets)
        self.store = Store(self.path, 'unused-password', clock=lambda:self.now)
        saved = self.call('GET', '/bookings/' + booking['id'])
        self.assertEqual(saved['booking']['tickets'], tickets)
    def test_checkout_idempotency(self):
        quote = self.quote()
        body = dict(quoteId=quote['quoteId'], requestId='same')
        first = self.call('POST', '/checkout', body)
        second = self.call('POST', '/checkout', body)
        self.assertEqual(first['booking']['id'], second['booking']['id'])
        self.assertEqual(len(self.call('GET','/orders')),1)
    def test_expired_hold_releases_seats_and_cannot_be_paid(self):
        booking = self.checkout()['booking']
        self.now += timedelta(minutes=11)
        query={key:self.screen[key] for key in ['movieId','date','showtime']}
        self.assertNotIn('A1', self.call('GET','/availability',query=query)['taken'])
        self.assertEqual(self.call('GET','/bookings')[0]['status'], 'expired')
        with self.assertRaises(ApiError): self.pay(booking)
        with self.assertRaises(ApiError):
            self.call('POST','/admin/status',dict(kind='bookings',id=booking['id'],status='confirmed',markPaid=True),self.admin)
    def test_concurrent_confirmations_do_not_double_book(self):
        first, second = self.quote(), self.quote(token=self.other)
        def confirm(pair):
            quote,token,request_id=pair
            try: return self.call('POST','/checkout',dict(quoteId=quote['quoteId'],requestId=request_id),token)['booking']['id']
            except ApiError as error: return error.status
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(confirm,[(first,self.customer,'first'),(second,self.other,'second')]))
        self.assertEqual(results.count(409),1)
    def test_changed_prices_and_availability_require_new_review(self):
        quote=self.quote()
        item=self.call('GET','/services')[0]
        item['price']=999
        self.call('PUT','/services/'+item['id'],item,self.admin)
        with self.assertRaises(ApiError): self.call('POST','/checkout',dict(quoteId=quote['quoteId'],requestId='changed'))
        self.assertEqual(self.call('GET','/bookings'),[])
    def test_counter_payment_needs_staff_and_settles_food_together(self):
        booking=self.checkout()['booking']
        waiting=self.pay(booking, method='counter')
        self.assertEqual(waiting['booking']['paymentStatus'],'awaiting_counter')
        self.assertEqual(waiting['booking']['tickets'],[])
        payload=dict(kind='bookings',id=booking['id'],status='pending_payment',markPaid=True)
        with self.assertRaises(ApiError): self.call('POST','/admin/status',payload)
        self.call('POST','/admin/status',payload,self.admin)
        paid=self.call('GET','/bookings/'+booking['id'])
        self.assertEqual(paid['booking']['status'],'confirmed')
        self.assertEqual(len(paid['booking']['tickets']),2)
        self.assertEqual(paid['order']['paymentStatus'],'paid_at_counter')
        self.assertTrue(paid['order']['voucher'])
    def test_admission_then_food_claim_are_single_use(self):
        result=self.pay(self.checkout()['booking'])
        token=result['booking']['tickets'][0]['token']
        voucher=result['order']['voucher']['token']
        with self.assertRaises(ApiError): self.call('POST','/admin/redeem',dict(token=voucher),self.admin)
        self.assertEqual(self.call('POST','/admin/redeem',dict(token=token),self.admin)['seat'],'A1')
        with self.assertRaises(ApiError): self.call('POST','/admin/redeem',dict(token=token),self.admin)
        self.assertEqual(self.call('POST','/admin/redeem',dict(token=voucher),self.admin)['type'],'food')
        with self.assertRaises(ApiError): self.call('POST','/admin/redeem',dict(token=voucher),self.admin)
        with self.assertRaises(ApiError):
            self.call('POST','/admin/status',dict(kind='bookings',id=result['booking']['id'],status='cancelled'),self.admin)
    def test_reviews_unlock_after_admission_and_screening_end(self):
        booking=self.pay(self.checkout(food=False)['booking'])['booking']
        review=dict(movieId='MOV-001',rating=5,comment='Great movie')
        with self.assertRaises(ApiError): self.call('POST','/reviews',review)
        self.call('POST','/admin/redeem',dict(token=booking['tickets'][0]['token']),self.admin)
        with self.assertRaises(ApiError): self.call('POST','/reviews',review)
        self.now+=timedelta(hours=6)
        self.assertTrue(self.call('GET','/review-eligibility',query=dict(movieId='MOV-001'))['eligible'])
        self.assertEqual(self.call('POST','/reviews',review)['rating'],5)
    def test_cancelled_passes_are_invalid(self):
        booking=self.pay(self.checkout()['booking'])['booking']
        self.call('POST','/admin/status',dict(kind='bookings',id=booking['id'],status='cancelled'),self.admin)
        with self.assertRaises(ApiError): self.call('POST','/admin/redeem',dict(token=booking['tickets'][0]['token']),self.admin)
    def test_customer_cannot_read_other_booking_or_redeem_pass(self):
        booking=self.pay(self.checkout()['booking'])['booking']
        with self.assertRaises(ApiError): self.call('GET','/bookings/'+booking['id'],token=self.other)
        with self.assertRaises(ApiError): self.call('POST','/admin/redeem',dict(token=booking['tickets'][0]['token']))
    def test_started_screenings_and_sold_out_food_rejected(self):
        self.now+=timedelta(hours=3)
        with self.assertRaises(ApiError): self.quote()
        self.now-=timedelta(hours=3)
        with self.assertRaises(ApiError): self.quote(items=[dict(id='SVC-006',quantity=1)])
    def test_unpaid_linked_order_cannot_advance_or_be_paid_separately(self):
        order=self.checkout()['order']
        for status in ['preparing','completed']:
            with self.assertRaises(ApiError): self.call('POST','/admin/status',dict(kind='orders',id=order['id'],status=status),self.admin)
        with self.assertRaises(ApiError): self.call('POST','/admin/status',dict(kind='orders',id=order['id'],status='awaiting_payment',markPaid=True),self.admin)

    def test_repeated_failed_attempt_cannot_change_its_outcome(self):
        booking=self.checkout()['booking']
        self.pay(booking,outcome='declined',attempt='same-attempt')
        repeated=self.pay(booking,outcome='success',attempt='same-attempt')
        self.assertEqual(repeated['booking']['paymentStatus'],'failed')
        self.assertEqual(repeated['booking']['tickets'],[])
        self.assertEqual(self.pay(booking,attempt='new-attempt')['booking']['paymentStatus'],'demo_paid')
    def test_parallel_payment_retries_issue_the_same_passes(self):
        booking=self.checkout()['booking']
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda attempt:self.pay(booking,attempt=attempt),['first','second']))
        self.assertEqual(results[0]['booking']['tickets'],results[1]['booking']['tickets'])
        self.assertEqual(results[0]['order']['voucher'],results[1]['order']['voucher'])
    def test_quote_totals_cannot_be_overridden_by_client(self):
        result=self.quote(total=1,ticketTotal=1,foodTotal=0)
        self.assertEqual(result['total'],800)
        with self.assertRaises(ApiError):
            self.call('POST','/checkout',dict(quoteId=result['quoteId'],requestId='stolen'),self.other)

    def test_http_quote_confirmation_payment_retry_and_redemption(self):
        import threading
        import json
        from urllib.request import Request, urlopen
        from api_server import ThreadingHTTPServer, handler_for
        server=ThreadingHTTPServer(('127.0.0.1',0),handler_for(self.store))
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        def send(path,body=None,token=None):
            request=Request(f'http://127.0.0.1:{server.server_port}'+path,
                data=json.dumps(body).encode() if body is not None else None,
                headers={'Content-Type':'application/json','Authorization':'Bearer '+(token or self.customer)})
            with urlopen(request) as result: return json.load(result)
        try:
            quote=send('/checkout/quote',dict(self.screen,items=[dict(id='SVC-001',quantity=1)]))
            confirmed=send('/checkout',dict(quoteId=quote['quoteId'],requestId='http-confirm'))
            booking_id=confirmed['booking']['id']
            self.assertEqual(confirmed['booking']['status'],'pending_payment')
            failed=send('/bookings/'+booking_id+'/payment',dict(method='demo',outcome='declined',attemptId='decline'))
            self.assertEqual(failed['booking']['tickets'],[])
            paid=send('/bookings/'+booking_id+'/payment',dict(method='demo',outcome='success',attemptId='retry'))
            self.assertEqual(len(paid['booking']['tickets']),2)
            self.assertTrue(paid['order']['voucher'])
            admitted=send('/admin/redeem',dict(token=paid['booking']['tickets'][0]['token']),self.admin)
            self.assertEqual(admitted['seat'],'A1')
            claimed=send('/admin/redeem',dict(token=paid['order']['voucher']['token']),self.admin)
            self.assertEqual(claimed['type'],'food')
        finally:
            server.shutdown();server.server_close();thread.join()

if __name__=='__main__': unittest.main()
