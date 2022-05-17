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

// import hive from "@hiveio/hive-js";

export default function UserProfileCard({ handleShow, user }) {
  const { user_info, resource_credits } = useContext(UserProfileContext);
  const { vesting_fund, vesting_shares } = useContext(HeadBlockContext);
  const profile_picture = `https://images.hive.blog/u/${user}/avatar`;
  const user_vesting_shares =
    Number(user_info?.vesting_shares.split("VESTS")[0]) * 1000000;
  const [rep, setRep] = useState([]);
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "reputation_api.get_account_reputations",
        params: { account_lower_bound: user },
        id: 1,
      },
    }).then((res) =>
      setRep(res.data.result.reputations.map((r) => parseInt(r.reputation)))
    );
  }, [user]);

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
      (user_info?.downvote_manabar.current_mana /
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
      (parseInt(resource_credits?.rc_manabar.current_mana) /
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
          {tidyNumber(vestsToHive(parseInt(user_info?.vesting_withdraw_rate)))}{" "}
          HIVE <br></br>
        </p>
        <p> {timeDelta(user_info?.next_vesting_withdrawal)}</p>
      </div>
      <div className="user-currency-amount justify-content-center">
        <ul
          style={{
            padding: "0",
            display: "flex",
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
      </div>
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
        <p>100</p>
      </div>
      <div className="more-details d-flex justify-content-center">
        <Button
          onClick={handleShow}
          style={{ width: "70%", color: "white", fontSize: "20px" }}
          variant="danger"
        >
          More info
        </Button>
      </div>
    </div>
  );
}
