// Smoke test: verify all endpoints respond under minimal load
import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { BASE_URL, headers, TEST_DATA } from './config.js';

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    http_req_failed: ['rate==0'],
    http_req_duration: ['p(95)<5000'],
  },
};

function jsonPost(endpoint, body) {
  return http.post(`${BASE_URL}/rpc/${endpoint}`,
    body ? JSON.stringify(body) : null,
    body ? { headers } : {});
}

export default function () {
  group('other', () => {
    let res = http.get(`${BASE_URL}/`);
    check(res, { 'root returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_hafbe_version');
    check(res, { 'version returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_hafbe_last_synced_block');
    check(res, { 'last synced block returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_input_type', { 'input-value': 'blocktrades' });
    check(res, { 'input type returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_latest_blocks');
    check(res, { 'latest blocks returns 200': (r) => r.status === 200 });
  });

  group('witnesses', () => {
    let res = jsonPost('get_witnesses');
    check(res, { 'witnesses returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_witness', { 'account-name': 'blocktrades' });
    check(res, { 'witness returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_witness_votes_history', { 'account-name': 'blocktrades' });
    check(res, { 'witness votes history returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_witness_voters', { 'account-name': 'blocktrades' });
    check(res, { 'witness voters returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_witness_voters_num', { 'account-name': 'blocktrades' });
    check(res, { 'witness voters num returns 200': (r) => r.status === 200 });
  });

  group('accounts', () => {
    let res = jsonPost('get_account', { 'account-name': 'blocktrades' });
    check(res, { 'account returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_account_authority', { 'account-name': 'blocktrades' });
    check(res, { 'account authority returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_comment_operations', {
      'account-name': 'blocktrades',
      'permlink': TEST_DATA.permlinks.blocktrades,
    });
    check(res, { 'comment operations returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_comment_permlinks', { 'account-name': 'blocktrades' });
    check(res, { 'comment permlinks returns 200': (r) => r.status === 200 });
  });

  group('block-numbers', () => {
    let res = jsonPost('get_block_by_op', { 'account-name': 'blocktrades' });
    check(res, { 'block by op returns 200': (r) => r.status === 200 });
    sleep(0.1);

    res = jsonPost('get_account_proxies_power', { 'account-name': 'blocktrades' });
    check(res, { 'proxies power returns 200': (r) => r.status === 200 });
  });

  group('transactions', () => {
    const res = jsonPost('get_transaction_statistics');
    check(res, { 'transaction statistics returns 200': (r) => r.status === 200 });
  });
}
