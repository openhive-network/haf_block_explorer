import React, { useContext, useEffect, useState } from "react";
import { Button, ProgressBar } from "react-bootstrap";
import { UserProfileContext } from "../../contexts/userProfileContext";
import {
  calculate_hive_hbd,
  calculate_vests,
  calculateHivePower,
} from "../../functions";
import { HeadBlockContext } from "../../contexts/headBlockContext";
import moment from "moment";
import axios from "axios";



export default function UserProfileCard({ user }) {
  const { user_info, resource_credits } = useContext(UserProfileContext);
  const { vesting_fund, vesting_shares } = useContext(HeadBlockContext);
  const [costs, setCosts] = useState(null);
  const profile_picture = `https://images.hive.blog/u/${user}/avatar`;
  const user_vesting_shares =
    Number(user_info?.vesting_shares?.split("VESTS")[0]) * 1000000;

  function effectiveVests() {
    if (user_info !== undefined && user_info !== null) {
      return (
        parseInt(user_info.vesting_shares) +
        parseInt(user_info.received_vesting_shares) -
        parseInt(user_info.delegated_vesting_shares) -
        parseInt(user_info.vesting_withdraw_rate)
      );
    } else {
      return null;
    }
  }
  function downvotePower() {
    return (
      (user_info?.downvote_manabar?.current_mana /
        ((effectiveVests() / 4) * 1e4)) *
      100
    );
  }
  function downvotePowerPct() {
    var pct = (downvotePower() / 100).toFixed(2);
    if (pct > 100) {
      return (pct = 100.0);
    } else {
      return pct;
    }
  }

  function votePower() {
    var secondsago =
      (new Date() - new Date(user_info?.last_vote_time + "Z")) / 1000;
    var vpow = user_info?.voting_power + (10000 * secondsago) / 432000;
    return Math.min(vpow / 100, 100).toFixed(2);
  }

  function calcResourseCredits() {
    const res =
      (parseInt(resource_credits?.rc_manabar?.current_mana) /
        parseInt(resource_credits?.max_rc)) *
      100;
    return res.toFixed(2);
  }

  function vestsToHive(vests) {
    const res = (vests / vesting_shares) * vesting_fund * 1000;
    return res.toFixed(3);
  }

  function tidyNumber(x) {
    if (x) {
      var parts = x.toString().split(".");
      parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
      return parts.join(".");
    } else {
      return null;
    }
  }

  function timeDelta(timestamp) {
    var now = moment.utc();
    var stamp = moment.utc(timestamp);
    var diff = stamp.diff(now, "minutes");
    return moment.duration(diff, "minutes").humanize(true);
  }

  useEffect(() => {
    axios.get("https://api.ausbit.dev/rc").then((res) => setCosts(res.data));
  }, []);
  function resourceBudgetComments() {
    if (resource_credits?.rc_manabar !== undefined) {
      var cost = 1175937456;
      if (costs !== null) {
        cost = costs.comment;
      }
      var available = resource_credits?.rc_manabar?.current_mana / cost;
      if (available >= 1000000) {
        return "1M+";
      } else {
        return tidyNumber(available.toFixed(0));
      }
    } else {
      return null;
    }
  }
  function resourceBudgetVotes() {
    if (resource_credits?.rc_manabar !== undefined) {
      var cost = 109514642;
      if (costs !== null) {
        cost = costs.vote;
      }
      var available = resource_credits?.rc_manabar?.current_mana / cost;
      if (available >= 1000000) {
        return "1M+";
      } else {
        return tidyNumber(available.toFixed(0));
      }
    } else {
      return null;
    }
  }
  function resourceBudgetTransfers() {
    if (resource_credits?.rc_manabar !== undefined) {
      var cost = 487237759;
      if (costs !== null) {
        cost = costs.transfer;
      }
      var available = resource_credits?.rc_manabar?.current_mana / cost;
      if (available >= 1000000) {
        return "1M+";
      } else {
        return tidyNumber(available.toFixed(0));
      }
    } else {
      return null;
    }
  }

  function resourceBudgetClaimAccounts() {
    if (resource_credits?.rc_manabar !== undefined) {
      var cost = 8541343515163;
      if (costs !== null) {
        cost = costs.claim_account;
      }
      var available = resource_credits?.rc_manabar?.current_mana / cost;
      if (available >= 1000000) {
        return "1M+";
      } else {
        return tidyNumber(available.toFixed(0));
      }
    } else {
      return null;
    }
  }
  function calculateReputation(reputation) {
    if (reputation == null) return reputation;
    let neg = reputation < 0;
    let rep = String(reputation);
    rep = neg ? rep.substring(1) : rep;
    let v = Math.log10((rep > 0 ? rep : -rep) - 10) - 9;
    v = neg ? -v : v;
    return parseInt(v * 9 + 25);
  }

  return (
    <div
      className="user-info-div"
      style={{
        // height: "400px",
        minWidth: "300px",
        // border: "5px solid black",
        borderRadius: "20px",
        background: "#2C3136",
        color: "#fff",
        padding: "30px",
      }}
    >
      <div
        className="user-pic-name"
        style={{
          display: "flex",
          marginBottom: "20px",
        }}
      >
        <div
          className="user-pic"
          style={{
            width: "70px",
            height: "70px",
            border: "4px solid red",
            borderRadius: "50%",
            // margin: "20px",
          }}
        >
          <img
            style={{ width: "62px", borderRadius: "50%" }}
            src={profile_picture}
            alt="user picture"
          />
        </div>
        <div className="username" style={{ margin: "20px 0 0 20px" }}>
          <p style={{ fontSize: "20px", textTransform: "capitalize" }}>
            {user}
          </p>
        </div>
      </div>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          flexDirection: "column",
        }}
        className="user-vote-weight"
      >
        <p>Vote Weight</p>
        <h3>{tidyNumber(vestsToHive(effectiveVests()))} HP</h3>
      </div>
      {tidyNumber(vestsToHive(parseInt(user_info?.vesting_withdraw_rate))) ===
      "0.000" ? (
        " "
      ) : (
        <div
          style={{
            display: "flex",
            alignItems: "center",
            flexDirection: "column",
          }}
          className="user-vote-weight"
        >
          <p>
            Next power down :{" "}
            {tidyNumber(
              vestsToHive(parseInt(user_info?.vesting_withdraw_rate))
            )}{" "}
            HIVE <br></br>
          </p>
          <p> {timeDelta(user_info?.next_vesting_withdrawal)}</p>
        </div>
      )}

      <div className="user-currency-amount justify-content-center text-center">
        <ul
          style={{
            padding: "0",
            // display: "flex",
            listStyle: "none",
            justifyContent: "space-around",
          }}
        >
          <li>{tidyNumber(user_info?.hbd_balance)}</li>
          <li>{tidyNumber(user_info?.balance)}</li>
          <li>
            {tidyNumber(
              calculateHivePower(
                user_vesting_shares,
                vesting_fund,
                vesting_shares
              )
            )}{" "}
            HP
          </li>
        </ul>
      </div>
      <div className="power-by-proc">
        {votePower() !== "NaN" && (
          <div
            style={{
              // marginTop: "20px",
              width: "100%",
              textAlign: "center",
            }}
            className="voting-power"
          >
            <p
              style={{
                color: "green",
                fontWeight: "bold",
                margin: "0",
              }}
            >
              Voting Power
            </p>
            <p style={{ margin: "0" }}>{votePower()} %</p>
            <ProgressBar
              variant="danger"
              style={{ margin: "10px 0 10px 0" }}
              animated
              now={votePower()}
            />
          </div>
        )}

        {downvotePowerPct() !== "NaN" && (
          <div
            style={{
              // marginTop: "20px",
              width: "100%",
              textAlign: "center",
            }}
            className="downvote-power"
          >
            <p style={{ color: "blue", fontWeight: "bold", margin: "0" }}>
              Downvote Power
            </p>
            <p style={{ margin: "0" }}>{downvotePowerPct()} %</p>
            <ProgressBar
              variant="danger"
              style={{ margin: "10px 0 10px 0" }}
              animated
              now={downvotePowerPct()}
            />
          </div>
        )}
        {calcResourseCredits() !== "NaN" && (
          <div
            style={{
              // marginTop: "20px",
              width: "100%",
              textAlign: "center",
            }}
            className="resource-credits"
          >
            <p style={{ color: "red", fontWeight: "bold", margin: "0" }}>
              Resource Credits
            </p>
            <p style={{ margin: "0" }}>{calcResourseCredits()} %</p>
            <ProgressBar
              variant="danger"
              style={{ margin: "10px 0 10px 0" }}
              animated
              now={calcResourseCredits()}
            />
          </div>
        )}
      </div>
      {!user_info?.reputation ? (
        ""
      ) : (
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            fontWeight: "bold",
            marginTop: "20px",
          }}
          className="reputation "
        >
          <p style={{ margin: "0" }}>Reputation</p>
          <p>{calculateReputation(user_info?.reputation)}</p>
        </div>
      )}

      <div>
        <p>Enough credits for aproximately</p>
        <ul>
          <li> {resourceBudgetComments()} comments</li>
          <li>{resourceBudgetVotes()} votes</li>
          <li>{resourceBudgetTransfers()} transfers</li>
          <li>{resourceBudgetClaimAccounts()} account claims</li>
        </ul>
      </div>
      <div className="more-details d-flex justify-content-center">
        {/* <Button
          onClick={handleShow}
          style={{ width: "70%", color: "white", fontSize: "20px" }}
          variant="danger"
        >
          More info
        </Button> */}
      </div>
    </div>
  );
}
