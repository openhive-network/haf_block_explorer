import { useContext } from "react";
import { Col } from "react-bootstrap";
import { Link } from "react-router-dom";
import { BlockContext } from "../../contexts/blockContext";
import { HeadBlockContext } from "../../contexts/headBlockContext";
import { UserProfileContext } from "../../contexts/userProfileContext";
import {
  tidyNumber,
  calc_reward_fund_to_dol,
  calc_feed_price,
  calc_reward_fund,
  calc_current_supply,
  calc_current_supply_hbd,
  calc_virtual_supply,
  modify_obj_key,
  calc_obj_numbers,
  modify_obj_hbd,
  modify_obj_number,
  modify_obj_date,
} from "../../functions/calculations";
import styles from "./headBlockCard.module.css";

export default function HeadBlockCard({ profile_picture }) {
  const { setBlockNumber } = useContext(BlockContext);
  const { head_block, head_block_data, reward_fund, feed_price } =
    useContext(HeadBlockContext);
  const { setUserProfile } = useContext(UserProfileContext);
  const current_head_block = head_block.head_block_number;
  const operations_count_per_block = head_block_data?.length;

  return (
    <Col md={12} lg={3}>
      <div className={styles.headBlockProperties}>
        <h3>
          Head Block :{" "}
          <Link
            className={styles.link}
            onClick={() => setBlockNumber(current_head_block)}
            to={`/block/${current_head_block}`}
          >
            {tidyNumber(current_head_block)}
          </Link>
        </h3>
        <p>
          Operations per block :{" "}
          {operations_count_per_block !== 0 && operations_count_per_block}
        </p>
        <p>Current witness</p>
        <p className={styles.headBlockValue}>
          <Link
            className={styles.link}
            to={`/user/${head_block?.current_witness}`}
          >
            <span onClick={() => setUserProfile(head_block?.current_witness)}>
              <img
                src={profile_picture(head_block?.current_witness)}
                alt="head block witness profile avatar"
              />{" "}
              {head_block.current_witness}
            </span>
          </Link>
        </p>
        <p className={styles.properties}>Properties </p>
        <ul>
          <li>Feed price </li>
          <li className={styles.headBlockValue}>
            ${calc_feed_price(feed_price)}/HIVE
          </li>
          <li>Blockchain time</li>
          <li className={styles.headBlockValue}>
            {modify_obj_date("time", head_block)}
          </li>
          <li>Rewards fund</li>
          <li className={styles.headBlockValue}>
            {tidyNumber(calc_reward_fund(reward_fund))} HIVE
          </li>
          <li className={styles.headBlockValue}>
            ${tidyNumber(calc_reward_fund_to_dol(reward_fund, feed_price))}
          </li>
          <li>Current Supply</li>
          <li className={styles.headBlockValue}>
            {tidyNumber(calc_current_supply(head_block))} HIVE
          </li>
          <li className={styles.headBlockValue}>
            {tidyNumber(calc_current_supply_hbd(head_block))} HBD
          </li>
          <li>Virtual Supply</li>
          <li className={styles.headBlockValue}>
            {tidyNumber(calc_virtual_supply(head_block))} HIVE
          </li>

          {Object.keys(head_block).map((key, i) => {
            if (
              [
                "next_daily_maintenance_time",
                "next_maintenance_time",
                "last_budget_time",
              ].includes(key)
            ) {
              return (
                <div key={i}>
                  <li>{modify_obj_key(key)}</li>{" "}
                  <li className={styles.headBlockValue}>
                    {modify_obj_date(key, head_block)}
                  </li>
                </div>
              );
            }
            if (
              [
                "hbd_stop_percent",
                "hbd_start_percent",
                "last_irreversible_block_num",
                "required_actions_partition_percent",
                "content_reward_percent",
                "vesting_reward_percent",
                "sps_fund_percent",
                "current_remove_threshold",
                "early_voting_seconds",
                "mid_voting_seconds",
                "max_consecutive_recurrent_transfer_failures",
                "max_recurrent_transfer_end_date",
                "min_recurrent_transfers_recurrence",
                "max_open_recurrent_transfers",
                "downvote_pool_percent",
              ].includes(key)
            ) {
              return (
                <div key={i}>
                  <li>{modify_obj_key(key)}</li>{" "}
                  <li className={styles.headBlockValue}>
                    {modify_obj_number(key, head_block)}
                  </li>
                </div>
              );
            }
            if (["hbd_interest_rate", "hbd_print_rate"].includes(key)) {
              return (
                <div key={i}>
                  <li>{modify_obj_key(key)}</li>{" "}
                  <li className={styles.headBlockValue}>
                    {`${head_block[key] / 100}%`}
                  </li>
                </div>
              );
            }
            if (["init_hbd_supply"].includes(key)) {
              return (
                <div key={i}>
                  <li>{modify_obj_key(key)}</li>
                  <li className={styles.headBlockValue}>
                    {modify_obj_hbd(key, head_block)} HBD
                  </li>
                </div>
              );
            }
            if (["current_hbd_supply", "sps_interval_ledger"].includes(key)) {
              return (
                <div key={i}>
                  <li>{modify_obj_key(key)}</li>
                  <li className={styles.headBlockValue}>
                    {calc_obj_numbers(key, head_block)} HBD
                  </li>
                </div>
              );
            }
            if (
              [
                "total_vesting_fund_hive",
                "pending_rewarded_vesting_hive",
              ].includes(key)
            ) {
              return (
                <div key={i}>
                  <li>{modify_obj_key(key)}</li>
                  <li className={styles.headBlockValue}>
                    {calc_obj_numbers(key, head_block)} HIVE
                  </li>
                </div>
              );
            }
            if (["available_account_subsidies"].includes(key)) {
              return (
                <div key={i}>
                  <li>{modify_obj_key(key)}</li>
                  <li className={styles.headBlockValue}>
                    {tidyNumber((head_block[key] / 10000).toFixed(0))}
                  </li>
                </div>
              );
            } else return "";
          })}
        </ul>
      </div>
    </Col>
  );
}
