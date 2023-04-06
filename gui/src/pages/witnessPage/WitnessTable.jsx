import styles from "./witnessTable.module.css";
import React, { useContext } from "react";
import { tidyNumber } from "../../functions/calculations";
import { WitnessContext } from "../../contexts/witnessContext";
import { AiOutlineUnorderedList } from "react-icons/ai";
import { MdOutlineHistory } from "react-icons/md";
import OverlayTrigger from "react-bootstrap/OverlayTrigger";
import Tooltip from "react-bootstrap/Tooltip";
import { AiOutlineLink } from "react-icons/ai";

const TABLE_HEAD = [
  "rank",
  "witness",
  "votes",
  "voters",
  "block_size",
  "price Feed",
  "bias",
  "feed Age",
  "signing_key",
  "version",
];

export default function WitnessTable({
  handeOpenVotersListTable,
  handleOpenVotesHistoryTable,
  arrowPosition,
  linkToUserProfile,
}) {
  const { witnessData, handleOrderBy } = useContext(WitnessContext);
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

  const trimTime = (time) => {
    if (time?.includes("days") || time?.includes("day")) {
      return time?.split(" ").slice(0, 2).join(" ");
    }
    return time?.split(".")[0];
  };

  return (
    <div className={styles.main}>
      <table className={styles.table}>
        <thead className={styles.table_head}>
          <tr className={styles.table_head_row}>
            {TABLE_HEAD.map((name, i) => (
              <th key={i} className={styles.table_head_col}>
                <button
                  onClick={() => handleOrderBy(name)}
                  style={{
                    border: "none",
                    background: "inherit",
                    color: "#fff",
                  }}
                >
                  {name.toUpperCase()} {arrowPosition(name)}
                </button>
              </th>
            ))}
          </tr>
        </thead>
        <tbody className={styles.table_body}>
          {witnessData?.map((witness, i) => {
            const inactiveWitness =
              witness.signing_key ===
              "STM1111111111111111111111111111111114T1Anm";

            return (
              <tr
                key={witness.witness}
                style={{
                  textDecoration: inactiveWitness ? "line-through" : "none",
                }}
              >
                <td className={styles.rank_col}>{witness.rank}</td>
                <td className={styles.name_col}>
                  {linkToUserProfile(witness.witness)}
                  {witness.url && (
                    <a href={witness.url} target="_blank" rel="noreferrer">
                      <AiOutlineLink />
                    </a>
                  )}
                </td>
                <td className={styles.votes_col}>
                  {witness.votes.toFixed(2)}{" "}
                  <span
                    style={{
                      color:
                        witness?.votes_daily_change > 0 ? "#0fbb2c" : "red",
                    }}
                  >
                    {witness?.votes_daily_change?.toFixed(2)}
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
                        onClick={() => handeOpenVotersListTable(witness)}
                      >
                        <AiOutlineUnorderedList />
                      </button>
                    </OverlayTrigger>
                  </span>
                </td>
                <td className={styles.voters_col}>
                  {witness.voters_num}{" "}
                  <span
                    style={{
                      color:
                        witness.voters_num_daily_change > 0 ? "#0fbb2c" : "red",
                    }}
                  >
                    {witness.voters_num_daily_change}
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
                        onClick={() => handleOpenVotesHistoryTable(witness)}
                      >
                        <MdOutlineHistory />
                      </button>
                    </OverlayTrigger>
                  </span>
                </td>

                <td className={styles.last_block_col}>
                  {tidyNumber(witness.block_size)}
                </td>
                <td className={styles.price_feed_col}>{witness.price_feed}</td>
                <td className={styles.bias_col}> {witness.bias}</td>
                <td className={styles.feed_age_col}>
                  <OverlayTrigger
                    placement="bottom"
                    delay={{ show: 250, hide: 400 }}
                    overlay={
                      <Tooltip id="feed_age-tooltip">
                        {witness.feed_age}
                      </Tooltip>
                    }
                  >
                    <p>{trimTime(witness.feed_age)}</p>
                  </OverlayTrigger>
                </td>
                <td>
                  <OverlayTrigger
                    placement="bottom"
                    delay={{ show: 250, hide: 400 }}
                    overlay={
                      <Tooltip id="signing_key-tooltip">
                        {witness.signing_key}
                      </Tooltip>
                    }
                  >
                    <p>{witness?.signing_key?.slice(0, 20)}</p>
                  </OverlayTrigger>
                </td>
                <td className={styles.version}>{witness.version}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
