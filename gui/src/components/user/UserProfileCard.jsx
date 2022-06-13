import React, { useContext, useEffect, useState } from "react";
import { ProgressBar } from "react-bootstrap";
import { UserProfileContext } from "../../contexts/userProfileContext";
import {
  effectiveVests,
  downvotePowerPct,
  votePower,
  calcResourseCredits,
  vestsToHive,
  timeDelta,
  resourceBudgetComments,
  resourceBudgetVotes,
  resourceBudgetTransfers,
  resourceBudgetClaimAccounts,
  calculateReputation,
  tidyNumber,
  calculateHivePower,
} from "../../functions/calculations";
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

  useEffect(() => {
    axios.get("https://api.ausbit.dev/rc").then((res) => setCosts(res.data));
  }, []);

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
        <h3>
          {tidyNumber(
            vestsToHive(effectiveVests(user_info), vesting_shares, vesting_fund)
          )}{" "}
          HP
        </h3>
      </div>
      {tidyNumber(
        vestsToHive(
          parseInt(user_info?.vesting_withdraw_rate),
          vesting_shares,
          vesting_fund
        )
      ) === "0.000" ? (
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
              vestsToHive(
                parseInt(user_info?.vesting_withdraw_rate),
                vesting_shares,
                vesting_fund
              )
            )}{" "}
            HIVE <br></br>
          </p>
          <p> {timeDelta(user_info?.next_vesting_withdrawal, moment)}</p>
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
        {votePower(user_info) !== "NaN" && (
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
            <p style={{ margin: "0" }}>{votePower(user_info)} %</p>
            <ProgressBar
              variant="danger"
              style={{ margin: "10px 0 10px 0" }}
              animated
              now={votePower(user_info)}
            />
          </div>
        )}

        {downvotePowerPct(user_info) !== "NaN" && (
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
            <p style={{ margin: "0" }}>{downvotePowerPct(user_info)} %</p>
            <ProgressBar
              variant="danger"
              style={{ margin: "10px 0 10px 0" }}
              animated
              now={downvotePowerPct(user_info)}
            />
          </div>
        )}
        {calcResourseCredits(resource_credits) !== "NaN" && (
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
            <p style={{ margin: "0" }}>
              {calcResourseCredits(resource_credits)} %
            </p>
            <ProgressBar
              variant="danger"
              style={{ margin: "10px 0 10px 0" }}
              animated
              now={calcResourseCredits(resource_credits)}
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
          <li>
            {" "}
            {resourceBudgetComments(resource_credits, costs, tidyNumber)}{" "}
            comments
          </li>
          <li>
            {resourceBudgetVotes(resource_credits, costs, tidyNumber)} votes
          </li>
          <li>
            {resourceBudgetTransfers(resource_credits, costs, tidyNumber)}{" "}
            transfers
          </li>
          <li>
            {resourceBudgetClaimAccounts(resource_credits, costs, tidyNumber)}{" "}
            account claims
          </li>
        </ul>
      </div>
    </div>
  );
}
