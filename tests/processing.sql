-- TODO Run these tests on a freshly created database

CREATE OR REPLACE PROCEDURE hafbe_app.test_add_new_witness_for_account_witness_vote_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"account_witness_vote_operation","value":{"account":"alice","witness":"initminer","approve":true}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 12, now(), 1);
BEGIN
  RAISE NOTICE 'test_add_new_witness_for_account_witness_vote_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'add_new_witness');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_add_new_witness_for_witness_set_properties_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"witness_set_properties_operation","value":{"owner":"holger80","props":[["account_creation_fee","b80b00000000000003535445454d0000"],["key","0295a26f54381a6dba8eb5dc7536e57db267685f9386c714ead9be39a905364a88"]],"extensions":[]}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 42, now(), 1);
BEGIN
  RAISE NOTICE 'test_add_new_witness_for_witness_set_properties_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'add_new_witness');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_add_new_witness_for_witness_update_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"witness_update_operation","value":{"owner":"alice","url":"http://url.html","block_signing_key":"STM5P8syqoj7itoDjbtDvCMCb5W3BNJtUjws9v7TDNZKqBLmp3pQW","props":{"account_creation_fee":{"amount":"10000", "precision":3,"nai":"@@000000021"},"maximum_block_size":131072,"hbd_interest_rate":1000},"fee":{"amount":"0","precision":3,"nai":"@@000000021"}}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 11, now(), 1);
BEGIN
  RAISE NOTICE 'test_add_new_witness_for_witness_update_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'add_new_witness');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_add_new_witness_for_feed_publish_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"feed_publish_operation","value":{"publisher":"initminer","exchange_rate":{"base":{"amount":"1","precision":3,"nai":"@@000000013"},"quote":{"amount":"2","precision":3,"nai":"@@000000021"}}}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 7, now(), 1);
BEGIN
  RAISE NOTICE 'test_add_new_witness_for_feed_publish_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'add_new_witness');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_update_current_witness_for_witness_set_properties_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"witness_set_properties_operation","value":{"owner":"holger80","props":[["account_creation_fee","b80b00000000000003535445454d0000"],["key","0295a26f54381a6dba8eb5dc7536e57db267685f9386c714ead9be39a905364a88"]],"extensions":[]}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 42, now(), 1);
BEGIN
  RAISE NOTICE 'test_update_current_witness_for_witness_set_properties_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'update_current_witness');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_update_current_witness_for_witness_update_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"witness_update_operation","value":{"owner":"alice","url":"http://url.html","block_signing_key":"STM5P8syqoj7itoDjbtDvCMCb5W3BNJtUjws9v7TDNZKqBLmp3pQW","props":{"account_creation_fee":{"amount":"10000", "precision":3,"nai":"@@000000021"},"maximum_block_size":131072,"hbd_interest_rate":1000},"fee":{"amount":"0","precision":3,"nai":"@@000000021"}}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 11, now(), 1);
BEGIN
  RAISE NOTICE 'test_update_current_witness_for_witness_update_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'update_current_witness');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_update_current_witness_for_feed_publish_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"feed_publish_operation","value":{"publisher":"initminer","exchange_rate":{"base":{"amount":"1","precision":3,"nai":"@@000000013"},"quote":{"amount":"2","precision":3,"nai":"@@000000021"}}}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 7, now(), 1);
BEGIN
  RAISE NOTICE 'test_update_current_witness_for_feed_publish_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'update_current_witness');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_update_current_witness_for_pow_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type": "pow_operation","value": {"block_id": "002104af55d5c492c8c134b5a55c89eac8210a86","nonce": "6317456790497374569","props": {"account_creation_fee": {"amount": "1","nai": "@@000000021","precision": 3}, "hbd_interest_rate": 1000,"maximum_block_size": 131072},"work": {"input": "d28a6c6f0fd04548ef12833d3e95acf7690cfb2bc6f6c8cd3b277d2f234bd908","signature": "20bd759200fb6996e141f1968beb3ef7d37a1692f15dc3a6c930388b27ec8691c07e36d3a0f441de10d12b2b1c98ed0816d3c2dfe1c8be1eacfd27fe5f4dd7f07a","work": "0000000c822c37f6a18985b1ef0eac34ae51f9e87d9ce3a8a217c90c7d74d82e", "worker": "STM5DHtHTDTyr3A4uutu6EsnHPfxAfRo9gQoJRT7jAHw4eU4UWRCK"},"worker_account": "badger3143"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 14, now(), 1);
BEGIN
  RAISE NOTICE 'test_update_current_witness_for_pow_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'update_current_witness');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_update_current_witness_for_pow2_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb;
  op_view hafbe_views.witness_prop_op_view;
BEGIN
  RAISE NOTICE 'test_update_current_witness_for_pow2_operation';
  op := '{"type": "pow2_operation","value": {"props": {"account_creation_fee": {"amount": "1","nai": "@@000000021","precision": 3},"hbd_interest_rate": 1000,"maximum_block_size": 131072},"work": {"type": "pow2","value": {"input": {"nonce": "2363830237862599931","prev_block": "003ead0c90b0cd80e9145805d303957015c50ef1","worker_account": "thedao"},"pow_summary": 3878270667}}}}';
  op_view := ('witness', op::jsonb, op::hive.operation, 1, 30, now(), 1);
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'update_current_witness');

  op := '{"type": "pow2_operation","value": {"props": {"account_creation_fee": {"amount": "2","nai": "@@000000021","precision": 3},"hbd_interest_rate": 1000,"maximum_block_size": 131070},"work": {"type": "equihash_pow","value": {"proof": {"n": 7, "k": 8, "seed": "x"}, "prev_block":"003ead0c90b0cd80e9145805d303957015c50ef0", "pow_summary":1}}}}';
  op_view := ('witness', op::jsonb, op::hive.operation, 1, 30, now(), 1);
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'update_current_witness');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_a_for_account_witness_vote_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"account_witness_vote_operation","value":{"account":"alice","witness":"initminer","approve":true}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 12, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_a_for_account_witness_vote_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_a');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_a_for_account_witness_proxy_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"account_witness_proxy_operation","value":{"account":"initminer","proxy":"alice"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 13, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_a_for_account_witness_proxy_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_a');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_a_for_proxy_cleared_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"proxy_cleared_operation","value":{"account":"lafona5","proxy":"lafona"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 91, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_a_for_proxy_cleared_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_a');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_a_for_expired_account_notification_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"expired_account_notification_operation","value":{"account":"spiritrider"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 75, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_a_for_expired_account_notification_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_a');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_a_for_declined_voting_rights_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"declined_voting_rights_operation","value":{"account":"lafona5"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 92, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_a_for_declined_voting_rights_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_a');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_account_create_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"account_create_operation","value":{"fee":{"amount":"0","precision":3,"nai":"@@000000021"},"creator":"initminer","new_account_name":"dan","owner":{"weight_threshold":1,"account_auths":[],"key_auths": [["STM5vYywCazmCT3XSRhxoPPHEznNJqQHzSDnGsGYTKR6VkU88E1gH",1]]},"active":{"weight_threshold":1,"account_auths":[],"key_auths":[["STM5vYywCazmCT3XSRhxoPPHEznNJqQHzSDnGsGYTKR6VkU88E1gH",1]]},"posting": {"weight_threshold":1,"account_auths":[],"key_auths":[["STM5vYywCazmCT3XSRhxoPPHEznNJqQHzSDnGsGYTKR6VkU88E1gH",1]]},"memo_key":"STM5vYywCazmCT3XSRhxoPPHEznNJqQHzSDnGsGYTKR6VkU88E1gH","json_metadata":"{}"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 9, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_account_create_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_create_claimed_account_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"create_claimed_account_operation","value":{"creator":"alice8ah","new_account_name":"ben8ah","owner":{"weight_threshold":1,"account_auths":[],"key_auths":[["STM7NVJSvcpYMSVkt1mzJ7uo8Ema7uwsuSypk9wjNjEK9cDyN6v3S",1]]},"active": {"weight_threshold":1,"account_auths":[],"key_auths":[["STM7NVJSvcpYMSVkt1mzJ7uo8Ema7uwsuSypk9wjNjEK9cDyN6v3S",1]]},"posting":{"weight_threshold":1,"account_auths":[],"key_auths":[["STM7F7N2n8RYwoBkS3rCtwDkaTdnbkctCm3V3fn2cDvdx988XMNZv", 1]]},"memo_key":"STM7F7N2n8RYwoBkS3rCtwDkaTdnbkctCm3V3fn2cDvdx988XMNZv","json_metadata":"{}","extensions":[]}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 23, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_create_claimed_account_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_account_created_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type": "account_created_operation","value": {"creator": "steem","initial_delegation": {"amount": "0","nai": "@@000000037","precision": 6},"initial_vesting_shares": {"amount": "11541527333","nai": "@@000000037","precision": 6},"new_account_name": "jevt"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 80, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_account_created_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_account_create_with_delegation_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"account_create_with_delegation_operation","value":{"fee":{"amount":"0","precision":3,"nai":"@@000000021"},"delegation":{"amount":"100000000000000","precision":6,"nai":"@@000000037"},"creator":"initminer","new_account_name":"edgar0ah","owner":{"weight_threshold":1,"account_auths":[],"key_auths":[["STM8R8maxJxeBMR3JYmap1n3Pypm886oEUjLYdsetzcnPDFpiq3pZ",1]]},"active":{"weight_threshold":1,"account_auths":[], "key_auths":[["STM8R8maxJxeBMR3JYmap1n3Pypm886oEUjLYdsetzcnPDFpiq3pZ",1]]},"posting":{"weight_threshold":1,"account_auths":[],"key_auths":[["STM8ZCsvwKqttXivgPyJ1MYS4q1r3fBZJh3g1SaBxVbfsqNcmnvD3",1]]},"memo_key": "STM8ZCsvwKqttXivgPyJ1MYS4q1r3fBZJh3g1SaBxVbfsqNcmnvD3","json_metadata":"{}","extensions":[]}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 41, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_account_create_with_delegation_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_pow_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type": "pow_operation","value": {"block_id": "002104af55d5c492c8c134b5a55c89eac8210a86","nonce": "6317456790497374569","props": {"account_creation_fee": {"amount": "1","nai": "@@000000021","precision": 3}, "hbd_interest_rate": 1000,"maximum_block_size": 131072},"work": {"input": "d28a6c6f0fd04548ef12833d3e95acf7690cfb2bc6f6c8cd3b277d2f234bd908","signature": "20bd759200fb6996e141f1968beb3ef7d37a1692f15dc3a6c930388b27ec8691c07e36d3a0f441de10d12b2b1c98ed0816d3c2dfe1c8be1eacfd27fe5f4dd7f07a","work": "0000000c822c37f6a18985b1ef0eac34ae51f9e87d9ce3a8a217c90c7d74d82e", "worker": "STM5DHtHTDTyr3A4uutu6EsnHPfxAfRo9gQoJRT7jAHw4eU4UWRCK"},"worker_account": "badger3143"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 14, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_pow_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_pow2_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb;
  op_view hafbe_views.witness_prop_op_view;
BEGIN
  RAISE NOTICE 'test_process_op_c_for_pow2_operation';
  op := '{"type": "pow2_operation","value": {"props": {"account_creation_fee": {"amount": "1","nai": "@@000000021","precision": 3},"hbd_interest_rate": 1000,"maximum_block_size": 131072},"work": {"type": "pow2","value": {"input": {"nonce": "2363830237862599931","prev_block": "003ead0c90b0cd80e9145805d303957015c50ef1","worker_account": "thedao"},"pow_summary": 3878270667}}}}';
  op_view := ('witness', op::jsonb, op::hive.operation, 1, 30, now(), 1);
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');

  op := '{"type": "pow2_operation","value": {"props": {"account_creation_fee": {"amount": "2","nai": "@@000000021","precision": 3},"hbd_interest_rate": 1000,"maximum_block_size": 131070},"work": {"type": "equihash_pow","value": {"proof": {"n": 7, "k": 8, "seed": "x"}, "prev_block":"003ead0c90b0cd80e9145805d303957015c50ef0", "pow_summary":1}}}}';
  op_view := ('witness', op::jsonb, op::hive.operation, 1, 30, now(), 1);
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_changed_recovery_account_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type": "changed_recovery_account_operation","value": {"account": "barrie","new_recovery_account": "boombastic_new","old_recovery_account": "boombastic_old"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 76, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_changed_recovery_account_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_recover_account_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type": "recover_account_operation","value": {"account_to_recover": "gtg","extensions": [],"new_owner_authority": {"account_auths": [],"key_auths": [["STM5RLQ1Jh8Kf56go3xpzoodg4vRsgCeWhANXoEXrYH7bLEwSVyjh",1]],"weight_threshold": 1},"recent_owner_authority": {"account_auths": [],"key_auths": [["STM5F9tCbND6zWPwksy1rEN24WjPiQWSU2vwGgegQVjAcYDe1zTWi",1]],"weight_threshold": 1}}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 25, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_recover_account_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_decline_voting_rights_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"decline_voting_rights_operation","value":{"account":"initminer","decline":true}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 36, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_decline_voting_rights_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_comment_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type": "comment_operation", "value": {"author": "tattoodjay", "body": "This is a cross post of [@tattoodjay/wednesday-walk-in-buttonwood-park](/hive-194913/@tattoodjay/wednesday-walk-in-buttonwood-park) by @tattoodjay.<br><br>A walk around Buttonwood Park", "json_metadata": "{\"app\":\"peakd/2023.2.2\",\"tags\":[\"cross-post\"],\"image\":[],\"original_author\":\"tattoodjay\", \"original_permlink\":\"wednesday-walk-in-buttonwood-park\"}", "parent_author": "", "parent_permlink": "hive-155530", "permlink": "wednesday-walk-in-buttonwood-park-hive-155530", "title": "Wednesday Walk in Buttonwood Park"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 1, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_comment_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_op_c_for_effective_comment_vote_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type": "effective_comment_vote_operation","value": {"author": "blocktrades","pending_payout": {"amount": "13419166","nai": "@@000000013","precision": 3},"permlink": "tax-issues-facing-us-based-cryptocurrency- holders-and-miners-intro-and-irs-guidelines","rshares": "29885796722307","total_vote_weight": "38751835134587","voter": "berniesanders","weight": "2523154605731"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 72, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_op_c_for_effective_comment_vote_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_op_c');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_vote_op_for_account_witness_vote_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"account_witness_vote_operation","value":{"account":"alice","witness":"initminer","approve":true}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 12, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_vote_op_for_account_witness_vote_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_vote_op');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_proxy_op_for_account_witness_proxy_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"account_witness_proxy_operation","value":{"account":"initminer","proxy":"alice"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 13, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_proxy_op_for_account_witness_proxy_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_proxy_op');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_proxy_op_for_proxy_cleared_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"proxy_cleared_operation","value":{"account":"lafona5","proxy":"lafona"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 91, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_proxy_op_for_proxy_cleared_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_proxy_op');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_expired_account_for_expired_account_notification_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"expired_account_notification_operation","value":{"account":"spiritrider"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 75, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_expired_account_for_expired_account_notification_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_expired_account');
END;
$BODY$
;

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_expired_account_for_declined_voting_rights_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"declined_voting_rights_operation","value":{"account":"lafona5"}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 92, now(), 1);
BEGIN
  RAISE NOTICE 'test_process_expired_account_for_declined_voting_rights_operation';
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'process_expired_account');
END;
$BODY$
;

CALL hive.appproc_context_detach(ARRAY['hafbe_app', 'btracker_app']);
CALL hafbe_app.test_add_new_witness_for_account_witness_vote_operation();
CALL hafbe_app.test_add_new_witness_for_witness_set_properties_operation();
CALL hafbe_app.test_add_new_witness_for_witness_update_operation();
CALL hafbe_app.test_add_new_witness_for_feed_publish_operation();
CALL hafbe_app.test_update_current_witness_for_witness_set_properties_operation();
CALL hafbe_app.test_update_current_witness_for_witness_update_operation();
CALL hafbe_app.test_update_current_witness_for_feed_publish_operation();
CALL hafbe_app.test_update_current_witness_for_pow_operation();
CALL hafbe_app.test_update_current_witness_for_pow2_operation();
CALL hafbe_app.test_process_op_a_for_account_witness_vote_operation();
CALL hafbe_app.test_process_op_a_for_account_witness_proxy_operation();
CALL hafbe_app.test_process_op_a_for_proxy_cleared_operation();
CALL hafbe_app.test_process_op_a_for_expired_account_notification_operation();
CALL hafbe_app.test_process_op_a_for_declined_voting_rights_operation();
CALL hafbe_app.test_process_op_c_for_account_create_operation();
CALL hafbe_app.test_process_op_c_for_create_claimed_account_operation();
CALL hafbe_app.test_process_op_c_for_account_created_operation();
CALL hafbe_app.test_process_op_c_for_account_create_with_delegation_operation();
CALL hafbe_app.test_process_op_c_for_pow_operation();
CALL hafbe_app.test_process_op_c_for_pow2_operation();
CALL hafbe_app.test_process_op_c_for_changed_recovery_account_operation();
CALL hafbe_app.test_process_op_c_for_recover_account_operation();
CALL hafbe_app.test_process_op_c_for_decline_voting_rights_operation();
CALL hafbe_app.test_process_op_c_for_comment_operation();
CALL hafbe_app.test_process_op_c_for_effective_comment_vote_operation();
CALL hafbe_app.test_process_vote_op_for_account_witness_vote_operation();
CALL hafbe_app.test_process_proxy_op_for_account_witness_proxy_operation();
CALL hafbe_app.test_process_proxy_op_for_proxy_cleared_operation();
CALL hafbe_app.test_process_expired_account_for_expired_account_notification_operation();
CALL hafbe_app.test_process_expired_account_for_declined_voting_rights_operation();
CALL hive.appproc_context_attach(ARRAY['hafbe_app', 'btracker_app'], 0);