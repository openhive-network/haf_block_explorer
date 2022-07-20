import styles from "./witnessTable.module.css";
import React, { useContext, useState } from "react";
import { tidyNumber } from "../../functions/calculations";
import { WitnessContext } from "../../contexts/witnessContext";
import moment from "moment";
import { sort } from "../../functions/witness_page_func";
import { AiOutlineUnorderedList } from "react-icons/ai";
import { MdOutlineHistory } from "react-icons/md";
import OverlayTrigger from "react-bootstrap/OverlayTrigger";
import Tooltip from "react-bootstrap/Tooltip";

const TABLE_HEAD = [
  "Rank",
  "Name",
  "Votes",
  "Voters",
  "Missed",
  "Last Block",
  "APR",
  "Price Feed",
  "Bias",
  "Feed Age",
  "Account Fee",
  "Block Size",
  "Version",
];

export default function WitnessTable({
  handleOpenVotersListTable,
  handleOpenVotesHistoryTable,
}) {
  const { witnessData } = useContext(WitnessContext);
  const [count, setCount] = useState(1);
  const click = (name) => {
    setCount(count + 1);
    sort(name, count, witnessData);
  };

  const renderVotersTooltip = (props) => (
    <Tooltip id="list-tooltip" {...props}>
      Show Voters
    </Tooltip>
  );
  const renderHistoryTooltip = (props) => (
    <Tooltip id="history-tooltip" {...props}>
      Show Votes History
    </Tooltip>
  );

  return (
    <div className={styles.main}>
      <table className={styles.table}>
        <thead className={styles.table_head}>
          <tr className={styles.table_head_row}>
            {TABLE_HEAD.map((name, i) => (
              <th key={i} className={styles.table_head_col}>
                <button
                  onClick={() => click(name)}
                  style={{
                    border: "none",
                    background: "inherit",
                    color: "#fff",
                  }}
                >
                  {name} &#8645;
                </button>
              </th>
            ))}
          </tr>
        </thead>
        <tbody className={styles.table_body}>
          {witnessData?.map((witness, i) => {
            return (
              <tr key={witness.id}>
                <td className={styles.rank_col}>{i + 1}</td>
                <td className={styles.name_col}>{witness.owner}</td>
                <td className={styles.votes_col}>
                  {tidyNumber(Math.round(witness.votes / 1000000 / 1000000))}{" "}
                  <span style={{ color: "#0fbb2c" }}>+- 99</span>
                </td>
                <td className={styles.voters_col}>
                  {" "}
                  9999{" "}
                  <span
                    style={{
                      color: "red",
                    }}
                  >
                    -+ 99
                  </span>
                  <span style={styles.list_icon}>
                    <OverlayTrigger
                      placement="bottom"
                      delay={{ show: 250, hide: 400 }}
                      overlay={renderVotersTooltip}
                    >
                      <button
                        style={{
                          border: "none",
                          background: "inherit",
                        }}
                        onClick={handleOpenVotersListTable}
                      >
                        <AiOutlineUnorderedList />
                      </button>
                    </OverlayTrigger>
                  </span>
                  <span style={styles.list_icon}>
                    <OverlayTrigger
                      placement="bottom"
                      delay={{ show: 250, hide: 400 }}
                      overlay={renderHistoryTooltip}
                    >
                      <button
                        style={{
                          border: "none",
                          background: "inherit",
                        }}
                        onClick={handleOpenVotesHistoryTable}
                      >
                        <MdOutlineHistory />
                      </button>
                    </OverlayTrigger>
                  </span>
                </td>
                <td className={styles.missed_col}>
                  {tidyNumber(witness.total_missed)}
                </td>
                <td className={styles.last_block_col}>
                  {tidyNumber(witness.last_confirmed_block_num)}
                </td>
                <td className={styles.apr_col}>
                  {Number(witness.props.hbd_interest_rate) / 100}%
                </td>
                <td className={styles.price_feed_col}>
                  {witness.hbd_exchange_rate.base.split("HBD")[0]}
                </td>
                <td className={styles.bias_col}> ??? %</td>
                <td className={styles.feed_age_col}>
                  {moment(witness.last_hbd_exchange_update).fromNow()}
                </td>
                <td className={styles.ac_free_col}>
                  {witness.props.account_creation_fee}
                </td>
                <td className={styles.block_size}>
                  {tidyNumber(witness.props.maximum_block_size)}
                </td>
                <td className={styles.version}>
                  {witness.hardfork_version_vote}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
