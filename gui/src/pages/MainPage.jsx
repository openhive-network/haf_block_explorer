import { useContext } from "react";
import { HeadBlockContext } from "../contexts/headBlockContext";
import { UserProfileContext } from "../contexts/userProfileContext";
import { BlockContext } from "../contexts/blockContext";
import { WitnessContext } from "../contexts/witnessContext";
import { Link } from "react-router-dom";
import { Container, Col, Row } from "react-bootstrap";
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
} from "../functions/calculations";
import OpCard from "../components/operations/OpCard";
import Loader from "../components/loader/Loader";

export default function Main_Page({ setTitle }) {
  // setTitle((document.title = "HAF Blocks"));
  const { witnessData } = useContext(WitnessContext);
  const { setBlockNumber } = useContext(BlockContext);
  const { head_block, head_block_data, reward_fund, feed_price } =
    useContext(HeadBlockContext);
  const { setUserProfile } = useContext(UserProfileContext);
  const current_head_block = head_block.head_block_number;
  const operations_count_per_block = head_block_data?.length;

  const profile_picture = (user) => {
    return `https://images.hive.blog/u/${user}/avatar`;
  };
  const trim_witness_array = witnessData?.slice(0, 20);
  // };
  const head_block_value_styles = {
    textAlign: "right",
    color: "#75ffff",
    margin: "5px",
  };
  const style = {
    color: "#160855",
    fontWeight: "bold",
    fontSize: "18px",
  };
  return (
    <>
      {operations_count_per_block === 0 ? (
        <Loader />
      ) : (
        <Container fluid className="main">
          <Row className="d-flex justify-content-center">
            <Col md={12} lg={3}>
              <div className="head_block_properties">
                <h3>
                  Head Block :{" "}
                  <Link
                    onClick={() => setBlockNumber(current_head_block)}
                    to={`/block/${current_head_block}`}
                  >
                    {current_head_block}
                  </Link>
                </h3>
                <p>
                  Operations per block :{" "}
                  {operations_count_per_block !== 0 &&
                    operations_count_per_block}
                </p>
                <p>
                  Current witness
                  <Link to={`/user/${head_block?.current_witness}`}>
                    <p
                      style={{ textAlign: "right" }}
                      onClick={() =>
                        setUserProfile(head_block?.current_witness)
                      }
                    >
                      <img
                        src={`https://images.hive.blog/u/${head_block.current_witness}/avatar`}
                        style={{
                          width: "40px",
                          height: "40px",
                          margin: "5px",
                          borderRadius: "50%",
                        }}
                      />{" "}
                      {head_block.current_witness}
                    </p>
                  </Link>
                </p>
                <p
                  style={{
                    fontSize: "20px",
                    color: "#e5ff00 ",
                    textAlign: "center",
                  }}
                >
                  Properties{" "}
                </p>
                <ul style={{ listStyle: "none", padding: "0" }}>
                  <li>Feed price </li>
                  <li style={head_block_value_styles}>
                    ${calc_feed_price(feed_price)}/HIVE
                  </li>
                  <li className="head_block_key">Blockchain time</li>
                  <li
                    className="head_block_value"
                    style={head_block_value_styles}
                  >
                    {modify_obj_date("time", head_block)}
                  </li>
                  <li className="head_block_key">Rewards fund</li>
                  <li
                    className="head_block_value"
                    style={head_block_value_styles}
                  >
                    {tidyNumber(calc_reward_fund(reward_fund))} HIVE
                  </li>
                  <li
                    className="head_block_value"
                    style={head_block_value_styles}
                  >
                    $
                    {tidyNumber(
                      calc_reward_fund_to_dol(reward_fund, feed_price)
                    )}
                  </li>
                  <li className="head_block_key">Current Supply</li>
                  <li
                    className="head_block_value"
                    style={head_block_value_styles}
                  >
                    {tidyNumber(calc_current_supply(head_block))} HIVE
                  </li>
                  <li
                    className="head_block_value"
                    style={head_block_value_styles}
                  >
                    {tidyNumber(calc_current_supply_hbd(head_block))} HBD
                  </li>
                  <li className="head_block_key">Virtual Supply</li>
                  <li
                    className="head_block_value"
                    style={head_block_value_styles}
                  >
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
                          <li style={head_block_value_styles}>
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
                        "hbd_interest_rate",
                        "hbd_print_rate",
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
                          <li style={head_block_value_styles}>
                            {modify_obj_number(key, head_block)}
                          </li>
                        </div>
                      );
                    }
                    if (["init_hbd_supply"].includes(key)) {
                      return (
                        <div key={i}>
                          <li>{modify_obj_key(key)}</li>
                          <li style={head_block_value_styles}>
                            {modify_obj_hbd(key, head_block)} HBD
                          </li>
                        </div>
                      );
                    }
                    if (
                      ["current_hbd_supply", "sps_interval_ledger"].includes(
                        key
                      )
                    ) {
                      return (
                        <div key={i}>
                          <li>{modify_obj_key(key)}</li>
                          <li style={head_block_value_styles}>
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
                          <li style={head_block_value_styles}>
                            {calc_obj_numbers(key, head_block)} HIVE
                          </li>
                        </div>
                      );
                    }
                    if (["available_account_subsidies"].includes(key)) {
                      return (
                        <div key={i}>
                          <li>{modify_obj_key(key)}</li>
                          <li style={head_block_value_styles}>
                            {tidyNumber((head_block[key] / 10000).toFixed(0))}
                          </li>
                        </div>
                      );
                    }
                  })}
                </ul>
              </div>
            </Col>
            <Col md={12} lg={6}>
              <p style={style}>Last transactions (3 sec)</p>
              {head_block_data?.map((block, index) => (
                <OpCard block={block} index={index} full_trx={block} />
              ))}
            </Col>

            <Col md={12} lg={3} className="main__top-witness">
              <div className="top-witness__list">
                <h3>Top Witnesses</h3>
                <ol style={{ textAlign: "left" }}>
                  {trim_witness_array?.map((w) => (
                    <div key={w.id}>
                      <li style={{ margin: "10px" }}>
                        <img
                          style={{
                            width: "40px",
                            borderRadius: "50%",
                            margin: "5px",
                          }}
                          src={profile_picture(w.owner)}
                        />
                        <Link to={`/user/${w.owner}`}>{w.owner}</Link>
                      </li>
                    </div>
                  ))}
                </ol>

                <Link to="/witnesses">More details</Link>
              </div>
            </Col>
          </Row>
        </Container>
      )}
    </>
  );
}
