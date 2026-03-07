// Shared configuration for k6 performance tests

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export const DEFAULT_THRESHOLDS = {
  http_req_duration: ['p(95)<2000', 'p(99)<5000'],
  http_req_failed: ['rate<0.01'],
};

export const headers = { 'Content-Type': 'application/json' };

// Test data matching the 5M block CI dataset
// Block explorer uses CSV-generated data in JMeter; here we hardcode representative values
export const TEST_DATA = {
  accounts: ['blocktrades', 'dantheman', 'ned', 'steemit', 'smooth'],
  blockNums: [1000000, 2000000, 3000000, 4000000, 5000000],
  inputValues: ['blocktrades', 'dantheman', '1000000'],
  permlinks: {
    blocktrades: 'blocktrades-witness-report-for-3rd-week-of-august',
  },
};
