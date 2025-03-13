# Single operation filter
## Testing function
```
DO $$
DECLARE
    i INTEGER;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
	_result json;
BEGIN
    FOR i IN 0..92 LOOP
        start_time := clock_timestamp();
        SELECT * INTO _result
		FROM hafbe_backend.blocksearch_operation_filter(
			    i,
			    NULL, 
			    NULL,
			    'desc', -- noqa: LT01, CP05
			    NULL,
			    100
		); 
        end_time := clock_timestamp();
        RAISE NOTICE 'Time taken for iteration %: % seconds', i, EXTRACT(EPOCH FROM end_time - start_time);
    END LOOP;
END $$;
```

### Result of search through whole range `1-94m` (first page)
```
NOTICE:  Time taken for iteration 0: 0.009230 seconds
NOTICE:  Time taken for iteration 1: 0.008545 seconds
NOTICE:  Time taken for iteration 2: 0.010382 seconds
NOTICE:  Time taken for iteration 3: 0.120998 seconds
NOTICE:  Time taken for iteration 4: 0.135049 seconds
NOTICE:  Time taken for iteration 5: 0.013008 seconds
NOTICE:  Time taken for iteration 6: 0.012916 seconds
NOTICE:  Time taken for iteration 7: 0.028075 seconds
NOTICE:  Time taken for iteration 8: 0.072092 seconds
NOTICE:  Time taken for iteration 9: 0.194624 seconds
NOTICE:  Time taken for iteration 10: 0.044746 seconds
NOTICE:  Time taken for iteration 11: 0.198985 seconds
NOTICE:  Time taken for iteration 12: 0.032822 seconds
NOTICE:  Time taken for iteration 13: 0.194697 seconds
NOTICE:  Time taken for iteration 14: 0.038127 seconds
NOTICE:  Time taken for iteration 15: 0.116141 seconds
NOTICE:  Time taken for iteration 16: 0.000323 seconds
NOTICE:  Time taken for iteration 17: 0.108504 seconds
NOTICE:  Time taken for iteration 18: 0.008021 seconds
NOTICE:  Time taken for iteration 19: 0.008686 seconds
NOTICE:  Time taken for iteration 20: 0.192215 seconds
NOTICE:  Time taken for iteration 21: 0.389563 seconds
NOTICE:  Time taken for iteration 22: 0.014782 seconds
NOTICE:  Time taken for iteration 23: 0.048467 seconds
NOTICE:  Time taken for iteration 24: 0.238865 seconds
NOTICE:  Time taken for iteration 25: 0.203913 seconds
NOTICE:  Time taken for iteration 26: 0.154469 seconds
NOTICE:  Time taken for iteration 27: 0.146621 seconds
NOTICE:  Time taken for iteration 28: 0.088728 seconds
NOTICE:  Time taken for iteration 29: 0.065642 seconds
NOTICE:  Time taken for iteration 30: 0.046883 seconds
NOTICE:  Time taken for iteration 31: 0.039027 seconds
NOTICE:  Time taken for iteration 32: 0.032263 seconds
NOTICE:  Time taken for iteration 33: 0.051939 seconds
NOTICE:  Time taken for iteration 34: 0.057831 seconds
NOTICE:  Time taken for iteration 35: 0.000181 seconds
NOTICE:  Time taken for iteration 36: 0.045091 seconds
NOTICE:  Time taken for iteration 37: 0.000180 seconds
NOTICE:  Time taken for iteration 38: 0.000156 seconds
NOTICE:  Time taken for iteration 39: 0.009138 seconds
NOTICE:  Time taken for iteration 40: 0.033407 seconds
NOTICE:  Time taken for iteration 41: 0.075904 seconds
NOTICE:  Time taken for iteration 42: 0.016605 seconds
NOTICE:  Time taken for iteration 43: 0.030923 seconds
NOTICE:  Time taken for iteration 44: 0.121122 seconds
NOTICE:  Time taken for iteration 45: 0.024306 seconds
NOTICE:  Time taken for iteration 46: 0.231786 seconds
NOTICE:  Time taken for iteration 47: 0.159587 seconds
NOTICE:  Time taken for iteration 48: 0.114201 seconds
NOTICE:  Time taken for iteration 49: 0.210254 seconds
NOTICE:  Time taken for iteration 50: 0.031042 seconds
NOTICE:  Time taken for iteration 51: 0.009531 seconds
NOTICE:  Time taken for iteration 52: 0.008114 seconds
NOTICE:  Time taken for iteration 53: 0.007468 seconds
NOTICE:  Time taken for iteration 54: 0.142677 seconds
NOTICE:  Time taken for iteration 55: 0.023469 seconds
NOTICE:  Time taken for iteration 56: 0.017437 seconds
NOTICE:  Time taken for iteration 57: 0.010179 seconds
NOTICE:  Time taken for iteration 58: 0.370302 seconds
NOTICE:  Time taken for iteration 59: 0.093093 seconds
NOTICE:  Time taken for iteration 60: 0.050660 seconds
NOTICE:  Time taken for iteration 61: 0.008938 seconds
NOTICE:  Time taken for iteration 62: 0.008477 seconds
NOTICE:  Time taken for iteration 63: 0.013203 seconds
NOTICE:  Time taken for iteration 64: 0.008321 seconds
NOTICE:  Time taken for iteration 65: 0.028858 seconds
NOTICE:  Time taken for iteration 66: 0.126872 seconds
NOTICE:  Time taken for iteration 67: 0.010069 seconds
NOTICE:  Time taken for iteration 68: 0.000559 seconds
NOTICE:  Time taken for iteration 69: 0.000531 seconds
NOTICE:  Time taken for iteration 70: 0.024440 seconds
NOTICE:  Time taken for iteration 71: 0.014461 seconds
NOTICE:  Time taken for iteration 72: 0.008047 seconds
NOTICE:  Time taken for iteration 73: 0.005057 seconds
NOTICE:  Time taken for iteration 74: 0.030844 seconds
NOTICE:  Time taken for iteration 75: 0.087083 seconds
NOTICE:  Time taken for iteration 76: 0.163756 seconds
NOTICE:  Time taken for iteration 77: 0.008471 seconds
NOTICE:  Time taken for iteration 78: 0.034900 seconds
NOTICE:  Time taken for iteration 79: 0.000546 seconds
NOTICE:  Time taken for iteration 80: 0.008765 seconds
NOTICE:  Time taken for iteration 81: 0.087395 seconds
NOTICE:  Time taken for iteration 82: 0.357164 seconds
NOTICE:  Time taken for iteration 83: 0.039183 seconds
NOTICE:  Time taken for iteration 84: 0.241734 seconds
NOTICE:  Time taken for iteration 85: 0.008354 seconds
NOTICE:  Time taken for iteration 86: 0.051245 seconds
NOTICE:  Time taken for iteration 87: 0.004459 seconds
NOTICE:  Time taken for iteration 88: 0.008854 seconds
NOTICE:  Time taken for iteration 89: 0.058626 seconds
NOTICE:  Time taken for iteration 90: 0.177098 seconds
NOTICE:  Time taken for iteration 91: 0.168568 seconds
NOTICE:  Time taken for iteration 92: 0.025825 seconds
```

### Result of search through range `42m-68m` (last page)

```
NOTICE:  Time taken for iteration 0: 0.056651 seconds
NOTICE:  Time taken for iteration 1: 0.028613 seconds
NOTICE:  Time taken for iteration 2: 0.035830 seconds
NOTICE:  Time taken for iteration 3: 0.078801 seconds
NOTICE:  Time taken for iteration 4: 0.151977 seconds
NOTICE:  Time taken for iteration 5: 0.041962 seconds
NOTICE:  Time taken for iteration 6: 0.043785 seconds
NOTICE:  Time taken for iteration 7: 0.040385 seconds
NOTICE:  Time taken for iteration 8: 0.079772 seconds
NOTICE:  Time taken for iteration 9: 0.393120 seconds
NOTICE:  Time taken for iteration 10: 0.075483 seconds
NOTICE:  Time taken for iteration 11: 0.257022 seconds
NOTICE:  Time taken for iteration 12: 0.059853 seconds
NOTICE:  Time taken for iteration 13: 0.076613 seconds
NOTICE:  Time taken for iteration 14: 0.000177 seconds
NOTICE:  Time taken for iteration 15: 0.029421 seconds
NOTICE:  Time taken for iteration 16: 0.000139 seconds
NOTICE:  Time taken for iteration 17: 0.146654 seconds
NOTICE:  Time taken for iteration 18: 0.013203 seconds
NOTICE:  Time taken for iteration 19: 0.025985 seconds
NOTICE:  Time taken for iteration 20: 0.151852 seconds
NOTICE:  Time taken for iteration 21: 0.001158 seconds
NOTICE:  Time taken for iteration 22: 0.041198 seconds
NOTICE:  Time taken for iteration 23: 0.087013 seconds
NOTICE:  Time taken for iteration 24: 0.267526 seconds
NOTICE:  Time taken for iteration 25: 0.131839 seconds
NOTICE:  Time taken for iteration 26: 0.077889 seconds
NOTICE:  Time taken for iteration 27: 0.089480 seconds
NOTICE:  Time taken for iteration 28: 0.098777 seconds
NOTICE:  Time taken for iteration 29: 0.100291 seconds
NOTICE:  Time taken for iteration 30: 0.000187 seconds
NOTICE:  Time taken for iteration 31: 0.037089 seconds
NOTICE:  Time taken for iteration 32: 0.060783 seconds
NOTICE:  Time taken for iteration 33: 0.103696 seconds
NOTICE:  Time taken for iteration 34: 0.161953 seconds
NOTICE:  Time taken for iteration 35: 0.000268 seconds
NOTICE:  Time taken for iteration 36: 0.000878 seconds
NOTICE:  Time taken for iteration 37: 0.000135 seconds
NOTICE:  Time taken for iteration 38: 0.000122 seconds
NOTICE:  Time taken for iteration 39: 0.030853 seconds
NOTICE:  Time taken for iteration 40: 0.023737 seconds
NOTICE:  Time taken for iteration 41: 0.000142 seconds
NOTICE:  Time taken for iteration 42: 0.042654 seconds
NOTICE:  Time taken for iteration 43: 0.063681 seconds
NOTICE:  Time taken for iteration 44: 0.313565 seconds
NOTICE:  Time taken for iteration 45: 0.087564 seconds
NOTICE:  Time taken for iteration 46: 0.002471 seconds
NOTICE:  Time taken for iteration 47: 0.003128 seconds
NOTICE:  Time taken for iteration 48: 0.128499 seconds
NOTICE:  Time taken for iteration 49: 0.293296 seconds
NOTICE:  Time taken for iteration 50: 0.080366 seconds
NOTICE:  Time taken for iteration 51: 0.035445 seconds
NOTICE:  Time taken for iteration 52: 0.008139 seconds
NOTICE:  Time taken for iteration 53: 0.007801 seconds
NOTICE:  Time taken for iteration 54: 0.000142 seconds
NOTICE:  Time taken for iteration 55: 0.059516 seconds
NOTICE:  Time taken for iteration 56: 0.037847 seconds
NOTICE:  Time taken for iteration 57: 0.048795 seconds
NOTICE:  Time taken for iteration 58: 0.000152 seconds
NOTICE:  Time taken for iteration 59: 0.164149 seconds
NOTICE:  Time taken for iteration 60: 0.000696 seconds
NOTICE:  Time taken for iteration 61: 0.017130 seconds
NOTICE:  Time taken for iteration 62: 0.056380 seconds
NOTICE:  Time taken for iteration 63: 0.027428 seconds
NOTICE:  Time taken for iteration 64: 0.008282 seconds
NOTICE:  Time taken for iteration 65: 0.217959 seconds
NOTICE:  Time taken for iteration 66: 0.220251 seconds
NOTICE:  Time taken for iteration 67: 0.011328 seconds
NOTICE:  Time taken for iteration 68: 0.000151 seconds
NOTICE:  Time taken for iteration 69: 0.000507 seconds
NOTICE:  Time taken for iteration 70: 0.052062 seconds
NOTICE:  Time taken for iteration 71: 0.318914 seconds
NOTICE:  Time taken for iteration 72: 0.008576 seconds
NOTICE:  Time taken for iteration 73: 0.000146 seconds
NOTICE:  Time taken for iteration 74: 0.071491 seconds
NOTICE:  Time taken for iteration 75: 0.047915 seconds
NOTICE:  Time taken for iteration 76: 0.033868 seconds
NOTICE:  Time taken for iteration 77: 0.008516 seconds
NOTICE:  Time taken for iteration 78: 0.000141 seconds
NOTICE:  Time taken for iteration 79: 0.000124 seconds
NOTICE:  Time taken for iteration 80: 0.022216 seconds
NOTICE:  Time taken for iteration 81: 0.058349 seconds
NOTICE:  Time taken for iteration 82: 0.189656 seconds
NOTICE:  Time taken for iteration 83: 0.166732 seconds
NOTICE:  Time taken for iteration 84: 0.231221 seconds
NOTICE:  Time taken for iteration 85: 0.034454 seconds
NOTICE:  Time taken for iteration 86: 0.127181 seconds
NOTICE:  Time taken for iteration 87: 0.007460 seconds
NOTICE:  Time taken for iteration 88: 0.009465 seconds
NOTICE:  Time taken for iteration 89: 0.033969 seconds
NOTICE:  Time taken for iteration 90: 0.003827 seconds
NOTICE:  Time taken for iteration 91: 0.061055 seconds
NOTICE:  Time taken for iteration 92: 0.000778 seconds
```
### Example result (filtered by `op_type_id = 1`)
```
{
   "total_blocks":100,
   "total_pages":10,
   "block_range":{
      "from":1,
      "to":94019635
   },
   "blocks_result":[
      {
         "block_num":94019635,
         "created_at":"2025-03-10T17:55:33",
         "producer_account":"themarkymark",
         "producer_reward":"488192643",
         "trx_count":14,
         "hash":"059aa0330a1c51ce2a573e6126f47a5edbf9cabf",
         "prev":"059aa032666966efda69bd18dd500d9dfb31ee12",
         "operations":[
            {
               "op_type_id":1,
               "op_count":1
            }
         ]
      },
      {
         "block_num":94019634,
         "created_at":"2025-03-10T17:55:30",
         "producer_account":"abit",
         "producer_reward":"488192644",
         "trx_count":19,
         "hash":"059aa032666966efda69bd18dd500d9dfb31ee12",
         "prev":"059aa0319a710ae3a6958e92714abdd96d4d175e",
         "operations":[
            {
               "op_type_id":1,
               "op_count":1
            }
         ]
      },
      {
         "block_num":94019633,
         "created_at":"2025-03-10T17:55:27",
         "producer_account":"arcange",
         "producer_reward":"488192646",
         "trx_count":25,
         "hash":"059aa0319a710ae3a6958e92714abdd96d4d175e",
         "prev":"059aa030d749916be156539dca3ad2e062c91adb",
         "operations":[
            {
               "op_type_id":1,
               "op_count":2
            }
         ]
      },
      {
         "block_num":94019631,
         "created_at":"2025-03-10T17:55:21",
         "producer_account":"therealwolf",
         "producer_reward":"488192649",
         "trx_count":31,
         "hash":"059aa02f8a1caa6b0d7d6736a03c610891dd50da",
         "prev":"059aa02efc3215fc8804d49a75157e20bf8b788c",
         "operations":[
            {
               "op_type_id":1,
               "op_count":1
            }
         ]
      },
      {
         "block_num":94019630,
         "created_at":"2025-03-10T17:55:18",
         "producer_account":"stoodkev",
         "producer_reward":"488192650",
         "trx_count":16,
         "hash":"059aa02efc3215fc8804d49a75157e20bf8b788c",
         "prev":"059aa02d712e1a50f624ef81f3aa477baf5de736",
         "operations":[
            {
               "op_type_id":1,
               "op_count":1
            }
         ]
      },
      {
         "block_num":94019629,
         "created_at":"2025-03-10T17:55:15",
         "producer_account":"gtg",
         "producer_reward":"488192651",
         "trx_count":27,
         "hash":"059aa02d712e1a50f624ef81f3aa477baf5de736",
         "prev":"059aa02c5cf0dc059f511bbea850a32d7d15ca72",
         "operations":[
            {
               "op_type_id":1,
               "op_count":1
            }
         ]
      },
      {
         "block_num":94019626,
         "created_at":"2025-03-10T17:55:06",
         "producer_account":"emrebeyler",
         "producer_reward":"488192656",
         "trx_count":38,
         "hash":"059aa02a9a1518d33da1285352a57dc4121545f0",
         "prev":"059aa0290801e16c5168faad830a07b1ebe12a1d",
         "operations":[
            {
               "op_type_id":1,
               "op_count":2
            }
         ]
      },
      {
         "block_num":94019625,
         "created_at":"2025-03-10T17:55:03",
         "producer_account":"steempeak",
         "producer_reward":"488192657",
         "trx_count":40,
         "hash":"059aa0290801e16c5168faad830a07b1ebe12a1d",
         "prev":"059aa02863abea807f6c16be0e51084700113eeb",
         "operations":[
            {
               "op_type_id":1,
               "op_count":1
            }
         ]
      },
      {
         "block_num":94019622,
         "created_at":"2025-03-10T17:54:54",
         "producer_account":"therealwolf",
         "producer_reward":"488192661",
         "trx_count":31,
         "hash":"059aa0267851d9e4cb421c61ff517d5cdecfbfea",
         "prev":"059aa02546397f8069cb64adad76a4cce142bc15",
         "operations":[
            {
               "op_type_id":1,
               "op_count":2
            }
         ]
      },
      {
         "block_num":94019618,
         "created_at":"2025-03-10T17:54:42",
         "producer_account":"quochuy",
         "producer_reward":"488192667",
         "trx_count":21,
         "hash":"059aa0220f2ea60a410894448cbe43530a54bc3e",
         "prev":"059aa021109cc984f215cc74ee39cb36713d6399",
         "operations":[
            {
               "op_type_id":1,
               "op_count":2
            }
         ]
      }
   ]
}
```
### Result of search through whole range `1-94m` (first page WITH filter by account)

```
NOTICE:  Time taken for iteration 0: 0.218380 seconds
NOTICE:  Time taken for iteration 1: 0.197098 seconds
NOTICE:  Time taken for iteration 2: 0.630500 seconds
NOTICE:  Time taken for iteration 3: 0.422088 seconds
NOTICE:  Time taken for iteration 4: 0.128676 seconds
NOTICE:  Time taken for iteration 5: 0.117920 seconds
NOTICE:  Time taken for iteration 6: 0.057328 seconds
NOTICE:  Time taken for iteration 7: 0.153587 seconds
NOTICE:  Time taken for iteration 8: 0.473743 seconds
NOTICE:  Time taken for iteration 9: 0.440741 seconds
NOTICE:  Time taken for iteration 10: 0.050405 seconds
NOTICE:  Time taken for iteration 11: 0.046762 seconds
NOTICE:  Time taken for iteration 12: 0.249562 seconds
NOTICE:  Time taken for iteration 13: 0.281660 seconds
NOTICE:  Time taken for iteration 14: 0.001717 seconds
NOTICE:  Time taken for iteration 15: 0.023873 seconds
NOTICE:  Time taken for iteration 16: 0.000502 seconds
NOTICE:  Time taken for iteration 17: 0.208441 seconds
NOTICE:  Time taken for iteration 18: 0.495686 seconds
NOTICE:  Time taken for iteration 19: 0.232596 seconds
NOTICE:  Time taken for iteration 20: 0.026997 seconds
NOTICE:  Time taken for iteration 21: 0.000755 seconds
NOTICE:  Time taken for iteration 22: 0.385411 seconds
NOTICE:  Time taken for iteration 23: 0.239139 seconds
NOTICE:  Time taken for iteration 24: 0.019345 seconds
NOTICE:  Time taken for iteration 25: 0.000716 seconds
NOTICE:  Time taken for iteration 26: 0.000328 seconds
NOTICE:  Time taken for iteration 27: 0.000311 seconds
NOTICE:  Time taken for iteration 28: 0.000307 seconds
NOTICE:  Time taken for iteration 29: 0.000303 seconds
NOTICE:  Time taken for iteration 30: 0.000300 seconds
NOTICE:  Time taken for iteration 31: 0.000299 seconds
NOTICE:  Time taken for iteration 32: 0.234179 seconds
NOTICE:  Time taken for iteration 33: 0.289978 seconds
NOTICE:  Time taken for iteration 34: 0.000748 seconds
NOTICE:  Time taken for iteration 35: 0.000334 seconds
NOTICE:  Time taken for iteration 36: 0.000320 seconds
NOTICE:  Time taken for iteration 37: 0.000316 seconds
NOTICE:  Time taken for iteration 38: 0.000308 seconds
NOTICE:  Time taken for iteration 39: 0.090567 seconds
NOTICE:  Time taken for iteration 40: 0.244078 seconds
NOTICE:  Time taken for iteration 41: 0.000750 seconds
NOTICE:  Time taken for iteration 42: 0.000513 seconds
NOTICE:  Time taken for iteration 43: 0.001936 seconds
NOTICE:  Time taken for iteration 44: 0.001394 seconds
NOTICE:  Time taken for iteration 45: 0.133040 seconds
NOTICE:  Time taken for iteration 46: 0.000854 seconds
NOTICE:  Time taken for iteration 47: 0.000551 seconds
NOTICE:  Time taken for iteration 48: 0.061535 seconds
NOTICE:  Time taken for iteration 49: 0.008009 seconds
NOTICE:  Time taken for iteration 50: 0.203821 seconds
NOTICE:  Time taken for iteration 51: 0.178345 seconds
NOTICE:  Time taken for iteration 52: 0.135134 seconds
NOTICE:  Time taken for iteration 53: 0.026255 seconds
NOTICE:  Time taken for iteration 54: 0.000707 seconds
NOTICE:  Time taken for iteration 55: 0.043052 seconds
NOTICE:  Time taken for iteration 56: 0.170011 seconds
NOTICE:  Time taken for iteration 57: 0.035094 seconds
NOTICE:  Time taken for iteration 58: 0.000757 seconds
NOTICE:  Time taken for iteration 59: 0.047738 seconds
NOTICE:  Time taken for iteration 60: 0.000750 seconds
NOTICE:  Time taken for iteration 61: 0.081902 seconds
NOTICE:  Time taken for iteration 62: 0.126860 seconds
NOTICE:  Time taken for iteration 63: 0.145517 seconds
NOTICE:  Time taken for iteration 64: 1.877310 seconds
NOTICE:  Time taken for iteration 65: 0.000755 seconds
NOTICE:  Time taken for iteration 66: 0.233531 seconds
NOTICE:  Time taken for iteration 67: 0.000795 seconds
NOTICE:  Time taken for iteration 68: 0.000349 seconds
NOTICE:  Time taken for iteration 69: 0.000331 seconds
NOTICE:  Time taken for iteration 70: 0.008623 seconds
NOTICE:  Time taken for iteration 71: 0.000385 seconds
NOTICE:  Time taken for iteration 72: 0.210289 seconds
NOTICE:  Time taken for iteration 73: 0.000746 seconds
NOTICE:  Time taken for iteration 74: 0.000350 seconds
NOTICE:  Time taken for iteration 75: 0.000341 seconds
NOTICE:  Time taken for iteration 76: 0.032360 seconds
NOTICE:  Time taken for iteration 77: 0.083639 seconds
NOTICE:  Time taken for iteration 78: 0.080244 seconds
NOTICE:  Time taken for iteration 79: 0.001108 seconds
NOTICE:  Time taken for iteration 80: 0.038905 seconds
NOTICE:  Time taken for iteration 81: 0.040819 seconds
NOTICE:  Time taken for iteration 82: 0.000899 seconds
NOTICE:  Time taken for iteration 83: 0.003829 seconds
NOTICE:  Time taken for iteration 84: 0.003139 seconds
NOTICE:  Time taken for iteration 85: 0.047917 seconds
NOTICE:  Time taken for iteration 86: 0.164504 seconds
NOTICE:  Time taken for iteration 87: 0.001103 seconds
NOTICE:  Time taken for iteration 88: 0.004979 seconds
NOTICE:  Time taken for iteration 89: 0.000401 seconds
NOTICE:  Time taken for iteration 90: 0.000339 seconds
NOTICE:  Time taken for iteration 91: 0.106461 seconds
NOTICE:  Time taken for iteration 92: 0.000993 seconds
```

seems like operation 64 is the slowest (almost 2s) but the rest is around 0.2s

### query benchmarks

```
explain analyze
SELECT * FROM hafbe_backend.blocksearch_no_filter(NULL,NULL,'desc',NULL,100)
--Execution Time: 5.724 ms

--next page
explain analyze
SELECT * FROM hafbe_backend.blocksearch_no_filter(NULL,NULL,'desc',940973,100)
--Execution Time: 8.442 ms

--random page
explain analyze
SELECT * FROM hafbe_backend.blocksearch_no_filter(NULL,NULL,'desc',2416,100)
--Execution Time: 42.682 ms

--last page
explain analyze
SELECT * FROM hafbe_backend.blocksearch_no_filter(NULL,NULL,'desc',1,100)
--Execution Time: 21.648 ms

--default by range
explain analyze
SELECT * FROM hafbe_backend.blocksearch_no_filter(42000000,68000000,'desc',NULL,100)
--Execution Time: 32.494 ms
---------------------------------------------------------------------------------------------------------------------
-- easy to find op
explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(1,NULL,NULL,'desc',NULL,100)
--Execution Time: 14.150 ms

-- easy to find op
explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(0,79000000,81000000,'desc',NULL,100)
--Execution Time: 53.800 ms

-- easy to find op next range
explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(0,79000000,80998956,'desc',NULL,100)
--Execution Time: 40.264 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(64,NULL,NULL,'desc',NULL,100)
--Execution Time: 10.554 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(40,NULL,NULL,'desc',NULL,100)
--Execution Time: 84.417 ms

--hard to find op
explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(27,NULL,NULL,'desc',NULL,100)
--Execution Time: 304.895 ms

--hard to find op by range
explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(27,47000000,49000000,'desc',NULL,100)
--Execution Time: 52.181 ms

--hard to find op
explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(21,NULL,NULL,'desc',NULL,100)
--Execution Time: 377.065 ms

--last page of hard to find op
explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(21,NULL,NULL,'desc',1,100)
--Execution Time: 220.870 ms

--next range of pages for hard to find op
explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(21,NULL,26688363,'desc',NULL,100)
--Execution Time: 111.089 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(29,NULL,NULL,'desc',NULL,100)
--Execution Time: 161.126 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_single_op(29,NULL,NULL,'desc',1,100)
--Execution Time: 103.504 ms
---------------------------------------------------------------------------------------------------------------------
--easy group of ops
explain analyze
SELECT * FROM hafbe_backend.blocksearch_multi_op(ARRAY[1,0],NULL,NULL,'desc',NULL,100)
--Execution Time: 8.352 ms

--hard group of ops
explain analyze
SELECT * FROM hafbe_backend.blocksearch_multi_op(ARRAY[89,27,29,21,54],NULL,NULL,'desc',NULL,100)
--Execution Time: 55.247 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_multi_op(ARRAY[51,52,53],NULL,NULL,'desc',NULL,100)
--Execution Time: 10.643 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_multi_op(ARRAY[51,52,53],NULL,94099389,'desc',NULL,100)
--Execution Time: 10.643 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_multi_op(ARRAY[51,52,53,68],NULL,94099389,'desc',1,100)
--Execution Time: 8.223 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_multi_op(ARRAY[51,52,53],20000000,30000000,'desc',NULL,100)
--Execution Time: 31.324 ms
---------------------------------------------------------------------------------------------------------------------
--hard account
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account('arcange',20000000,30000000,'desc',NULL,100)
--Execution Time: 4258.280 ms

--big account default
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account('actifit',NULL,NULL,'desc',NULL,100)
--Execution Time: 31.354 ms

--big account
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account('gtg',20000000,30000000,'desc',NULL,100)
--Execution Time: 611.485 ms

--small account
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account('small.minion',20000000,30000000,'desc',NULL,100)
--Execution Time: 27.769 ms

--small account
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account('small.minion',NULL, NULL,'desc',NULL,100)
--Execution Time: 11.961 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_account('miosha',NULL, NULL,'desc',NULL,100)
--Execution Time: 12.324 ms

--iterate through newly generated pages
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account('miosha',NULL, 93426075,'desc',NULL,100)
--Execution Time: 84.207 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_account('andablackwidow',NULL, NULL,'desc',NULL,100)
--Execution Time: 36.667 ms

--last page
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account('andablackwidow',NULL, NULL,'desc',1,100)
--Execution Time: 110.154 ms
---------------------------------------------------------------------------------------------------------------------
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_op(1,'blocktrades',NULL,NULL,'desc',NULL,100)
--Execution Time: 160.900 ms

--last page
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_op(1,'blocktrades',NULL,94100194,'desc',1,100)
--Execution Time: 158.257 ms

--next iteration
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_op(1,'blocktrades',NULL,72190361,'desc',NULL,100)
--Execution Time: 171.391 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_op(40,'blocktrades',NULL,NULL,'desc',NULL,100)
--Execution Time: 140.736 ms

--last page
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_op(40,'blocktrades',NULL,94100228,'desc',1,100)
--Execution Time: 249.074 ms

--next iteration
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_op(40,'blocktrades',NULL,40476940,'desc',NULL,100)
--Execution Time: 239.365 ms

--by range
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_op(53,'blocktrades',20000000,30000000,'desc',NULL,100)
--Execution Time: 117.658 ms
---------------------------------------------------------------------------------------------------------------------

explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_multi_op(ARRAY[0,1],'blocktrades',NULL,NULL,'desc',NULL,100)
--Execution Time: 183.349 ms

--last page
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_multi_op(ARRAY[0,1],'blocktrades',NULL,94100283,'desc',1,100)
--Execution Time: 182.454 ms

--next iteration
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_multi_op(ARRAY[0,1],'blocktrades',NULL,91109731,'desc',NULL,100)
--Execution Time: 277.440 ms

--by range
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_multi_op(ARRAY[0,1],'blocktrades',20000000,30000000,'desc',NULL,100)
--Execution Time: 214.100 ms

--empty
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_multi_op(ARRAY[89,27,29,21,54],'blocktrades',NULL,NULL,'desc',NULL,100)
--Execution Time: 1.121 ms

--reward ops
explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_multi_op(ARRAY[51,52,53],'blocktrades',NULL,NULL,'desc',NULL,100)
--Execution Time: 123.735 ms
---------------------------------------------------------------------------------------------------------------------


------------- by key-value -------------
explain analyze
SELECT * FROM hafbe_backend.blocksearch_key_value(
	1,NULL,NULL,'desc',NULL,100,
	ARRAY['blocktrades','blocktrades-witness-report-for-3rd-week-of-august'],
	'[["value","author"],["value","permlink"]]'::json
)
--Execution Time: 23.852 ms

explain analyze
SELECT * FROM hafbe_backend.blocksearch_key_value(
	0,NULL,NULL,'desc',NULL,100,
	ARRAY['arcange','hive-finance-202503-en'],
	'[["value","author"],["value","permlink"]]'::json
)
--Execution Time: 200.847 ms

--next iteration
explain analyze
SELECT * FROM hafbe_backend.blocksearch_key_value(
	0,NULL,93782633,'desc',NULL,100,
	ARRAY['arcange','hive-finance-202503-en'],
	'[["value","author"],["value","permlink"]]'::json
)
--Execution Time: 75.035 ms

--custom json
explain analyze
SELECT * FROM hafbe_backend.blocksearch_key_value(
	18,NULL,NULL,'desc',NULL,100,
	ARRAY['follow'],
	'[["value","id"]]'::json
)
--Execution Time: 86.876 ms
---------------------------------------------------------------------------------------------------------------------

explain analyze
SELECT * FROM hafbe_backend.blocksearch_account_key_value(
	1,'blocktrades',NULL,NULL,'desc',NULL,100,
	ARRAY['blocktrades','blocktrades-witness-report-for-3rd-week-of-august'],
	'[["value","author"],["value","permlink"]]'::json
	)
--Execution Time: 37.002 ms


```