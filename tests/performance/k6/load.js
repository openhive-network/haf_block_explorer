// Load test: sustained traffic across all endpoints
import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { BASE_URL, DEFAULT_THRESHOLDS, headers, TEST_DATA } from './config.js';

const DURATION = __ENV.DURATION || '2m';
const VUS = parseInt(__ENV.VUS || '10');

export const options = {
  stages: [
    { duration: '30s', target: VUS },
    { duration: DURATION, target: VUS },
    { duration: '15s', target: 0 },
  ],
  thresholds: DEFAULT_THRESHOLDS,
};

function randomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function jsonPost(endpoint, body) {
  return http.post(`${BASE_URL}/rpc/${endpoint}`,
    body ? JSON.stringify(body) : null,
    body ? { headers } : {});
}

export default function () {
  const account = randomItem(TEST_DATA.accounts);

  group('other', () => {
    jsonPost('get_hafbe_version');
    jsonPost('get_latest_blocks');
    jsonPost('get_input_type', { 'input-value': randomItem(TEST_DATA.inputValues) });
  });

  group('witnesses', () => {
    jsonPost('get_witnesses');
    jsonPost('get_witness', { 'account-name': account });
    jsonPost('get_witness_voters', { 'account-name': account });
  });

  group('accounts', () => {
    jsonPost('get_account', { 'account-name': account });
    jsonPost('get_account_authority', { 'account-name': account });
    const res = jsonPost('get_comment_permlinks', { 'account-name': account });
    check(res, { 'status 200': (r) => r.status === 200 });
  });

  group('block-numbers', () => {
    jsonPost('get_block_by_op', { 'account-name': account });
  });

  sleep(0.5);
}
