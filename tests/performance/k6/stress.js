// Stress test: push the API beyond normal load to find breaking points
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { BASE_URL, headers, TEST_DATA } from './config.js';

const errorRate = new Rate('errors');
const MAX_VUS = parseInt(__ENV.MAX_VUS || '100');

export const options = {
  stages: [
    { duration: '30s', target: Math.floor(MAX_VUS * 0.25) },
    { duration: '1m', target: Math.floor(MAX_VUS * 0.5) },
    { duration: '2m', target: MAX_VUS },
    { duration: '2m', target: MAX_VUS },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<10000'],
    errors: ['rate<0.10'],
  },
};

function randomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function jsonPost(endpoint, body) {
  return http.post(`${BASE_URL}/rpc/${endpoint}`,
    body ? JSON.stringify(body) : null,
    body ? { headers } : {});
}

// Weighted endpoint selection simulating realistic traffic
const ENDPOINTS = [
  { weight: 20, fn: () => jsonPost('get_account', { 'account-name': randomItem(TEST_DATA.accounts) }) },
  { weight: 15, fn: () => jsonPost('get_witnesses') },
  { weight: 15, fn: () => jsonPost('get_witness', { 'account-name': randomItem(TEST_DATA.accounts) }) },
  { weight: 10, fn: () => jsonPost('get_latest_blocks') },
  { weight: 10, fn: () => jsonPost('get_comment_permlinks', { 'account-name': randomItem(TEST_DATA.accounts) }) },
  { weight: 10, fn: () => jsonPost('get_witness_voters', { 'account-name': randomItem(TEST_DATA.accounts) }) },
  { weight: 5, fn: () => jsonPost('get_input_type', { 'input-value': randomItem(TEST_DATA.inputValues) }) },
  { weight: 5, fn: () => jsonPost('get_block_by_op', { 'account-name': randomItem(TEST_DATA.accounts) }) },
  { weight: 5, fn: () => jsonPost('get_transaction_statistics') },
  { weight: 5, fn: () => jsonPost('get_hafbe_version') },
];

const WEIGHTED = [];
for (const ep of ENDPOINTS) {
  for (let i = 0; i < ep.weight; i++) WEIGHTED.push(ep.fn);
}

export default function () {
  const fn = WEIGHTED[Math.floor(Math.random() * WEIGHTED.length)];
  const res = fn();
  check(res, { 'not server error': (r) => r.status < 500 });
  errorRate.add(res.status >= 500);
  sleep(0.1 + Math.random() * 0.3);
}
