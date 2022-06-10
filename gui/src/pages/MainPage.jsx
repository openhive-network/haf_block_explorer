import { useContext } from "react";
import { HeadBlockContext } from "../contexts/headBlockContext";
import { UserProfileContext } from "../contexts/userProfileContext";
import { BlockContext } from "../contexts/blockContext";
import { WitnessContext } from "../contexts/witnessContext";
import { Link } from "react-router-dom";
import { Container, Col, Row } from "react-bootstrap";
import { tidyNumber } from "../functions";
import OpCard from "../components/OpCard";
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
  const calc_reward_fund_to_dol = () => {
    const result = calc_reward_fund() * calc_feed_price();
    return result.toFixed(0);
  };

  const calc_feed_price = () => {
    const result =
      Number(feed_price?.base?.amount) / Number(feed_price?.quote?.amount);
    return result;
  };

  const calc_reward_fund = () => {
    const result = Number(reward_fund?.reward_balance?.amount) / 1000;
    return result.toFixed(0);
  };

  const calc_current_supply = () => {
    const result = Number(head_block?.current_supply?.amount) / 1000;
    return result.toFixed(0);
  };
  const calc_current_supply_hbd = () => {
    const result = Number(head_block?.current_hbd_supply?.amount) / 1000;
    return result.toFixed(0);
  };
  const calc_virtual_supply = () => {
    const result = Number(head_block?.virtual_supply?.amount) / 1000;
    return result.toFixed(0);
  };

  const head_block_value_styles = {
    textAlign: "right",
    color: "#75ffff",
    margin: "5px",
  };
  const modify_obj_key = (key) => {
    const remove_underscore = key.split("_").join(" ");
    const first_upper_letter =
      remove_underscore.slice(0, 1).toUpperCase() + remove_underscore.slice(1);
    return first_upper_letter;
  };

  const calc_obj_numbers = (key) => {
    return tidyNumber(Number(head_block[key]?.amount).toFixed(3) / 1000);
  };
  const modify_obj_hbd = (key) => {
    return Number(head_block[key]?.amount).toFixed(3);
  };
  const modify_obj_number = (key) => {
    const result =
      head_block[key] !== 0
        ? tidyNumber(Number(head_block[key]))
        : Number(head_block[key]);
    return result;
  };
  const modify_obj_date = (key) => {
    return head_block[key]?.split("T").join(" ");
  };
  return (
    <>
      {/* {operations_count_per_block === 0 ? (
        <Loader/>
      ) : ( */}
      <Container fluid className="main">
        <Row className="d-flex justify-content-center">
          <Col>
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
                {operations_count_per_block !== 0 && operations_count_per_block}
              </p>
              <p>
                Current witness
                <Link to={`/user/${head_block?.current_witness}`}>
                  <p
                    style={{ textAlign: "right" }}
                    onClick={() => setUserProfile(head_block?.current_witness)}
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
                  ${calc_feed_price()}/HIVE
                </li>
                <li className="head_block_key">Blockchain time</li>
                <li
                  className="head_block_value"
                  style={head_block_value_styles}
                >
                  {modify_obj_date("time")}
                </li>
                <li className="head_block_key">Rewards fund</li>
                <li
                  className="head_block_value"
                  style={head_block_value_styles}
                >
                  {tidyNumber(calc_reward_fund())} HIVE
                </li>
                <li
                  className="head_block_value"
                  style={head_block_value_styles}
                >
                  $ {tidyNumber(calc_reward_fund_to_dol())}
                </li>
                <li className="head_block_key">Current Supply</li>
                <li
                  className="head_block_value"
                  style={head_block_value_styles}
                >
                  {tidyNumber(calc_current_supply())} HIVE
                </li>
                <li
                  className="head_block_value"
                  style={head_block_value_styles}
                >
                  {tidyNumber(calc_current_supply_hbd())} HBD
                </li>
                <li className="head_block_key">Virtual Supply</li>
                <li
                  className="head_block_value"
                  style={head_block_value_styles}
                >
                  {tidyNumber(calc_virtual_supply())} HIVE
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
                      <>
                        {" "}
                        <li>{modify_obj_key(key)}</li>{" "}
                        <li style={head_block_value_styles}>
                          {modify_obj_date(key)}
                        </li>
                      </>
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
                      <>
                        <li>{modify_obj_key(key)}</li>{" "}
                        <li style={head_block_value_styles}>
                          {modify_obj_number(key)}
                        </li>
                      </>
                    );
                  }
                  if (["init_hbd_supply"].includes(key)) {
                    return (
                      <>
                        <li>{modify_obj_key(key)}</li>
                        <li style={head_block_value_styles}>
                          {modify_obj_hbd(key)} HBD
                        </li>
                      </>
                    );
                  }
                  if (
                    ["current_hbd_supply", "sps_interval_ledger"].includes(key)
                  ) {
                    return (
                      <>
                        <li>{modify_obj_key(key)}</li>
                        <li style={head_block_value_styles}>
                          {calc_obj_numbers(key)} HBD
                        </li>
                      </>
                    );
                  }
                  if (
                    [
                      "total_vesting_fund_hive",
                      "pending_rewarded_vesting_hive",
                    ].includes(key)
                  ) {
                    return (
                      <>
                        <li>{modify_obj_key(key)}</li>
                        <li style={head_block_value_styles}>
                          {calc_obj_numbers(key)} HIVE
                        </li>
                      </>
                    );
                  }
                  if (["available_account_subsidies"].includes(key)) {
                    return (
                      <>
                        <li>{modify_obj_key(key)}</li>
                        <li style={head_block_value_styles}>
                          {tidyNumber((head_block[key] / 1000).toFixed(0))}
                        </li>
                      </>
                    );
                  }
                })}
              </ul>
            </div>
          </Col>
          <Col xs={12} sm={7}>
            <p>Last Transactions (3 sec)</p>
            {head_block_data?.map((block, index) => (
              <OpCard block={block} index={index} full_trx={block} />
            ))}
          </Col>

          <Col
            // xs={12}
            // sm={2}
            className="main__top-witness"
          >
            <div className="top-witness__list">
              <h3>Top Witnesses</h3>
              <ol style={{ textAlign: "left" }}>
                {trim_witness_array?.map((w, i) => (
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
                ))}
              </ol>

              <Link to="/witnesses">More details</Link>
            </div>
          </Col>
        </Row>
      </Container>
      {/* )} */}
    </>
  );
}
