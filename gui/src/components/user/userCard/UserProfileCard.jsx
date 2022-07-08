import React, { useContext, useEffect, useState } from "react";
import { ProgressBar } from "react-bootstrap";
import { UserProfileContext } from "../../../contexts/userProfileContext";
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
} from "../../../functions/calculations";
import { HeadBlockContext } from "../../../contexts/headBlockContext";
import moment from "moment";
import axios from "axios";
import styles from "./userCard.module.css";

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
    <div className={styles.userCardContainer}>
      <div className={styles.nameContainer}>
        <div className={styles.userPictureContainer}>
          <img
            className={styles.userPicture}
            src={profile_picture}
            alt="user avarar"
          />
        </div>
        <div className={styles.username}>
          <p>{user}</p>
        </div>
      </div>
      <div className={styles.voteWeightContainer}>
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
        <div className={styles.voteWeightContainer}>
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

      <div className={styles.currencyContainer}>
        <ul className={styles.currencyUL}>
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
      <div>
        {votePower(user_info) !== "NaN" && (
          <div className={styles.votingPowerContainer}>
            <p className={styles.votingPowerText}>Voting Power</p>
            <p>{votePower(user_info)} %</p>
            <ProgressBar
              className={styles.votingPowerBar}
              variant="danger"
              animated
              now={votePower(user_info)}
            />
          </div>
        )}

        {downvotePowerPct(user_info) !== "NaN" && (
          <div className={styles.votingPowerContainer}>
            <p className={styles.downvotePowerText}>Downvote Power</p>
            <p>{downvotePowerPct(user_info)} %</p>
            <ProgressBar
              variant="danger"
              className={styles.votingPowerBar}
              animated
              now={downvotePowerPct(user_info)}
            />
          </div>
        )}
        {calcResourseCredits(resource_credits) !== "NaN" && (
          <div className={styles.votingPowerContainer}>
            <p className={styles.RCText}>Resource Credits</p>
            <p>{calcResourseCredits(resource_credits)} %</p>
            <ProgressBar
              variant="danger"
              className={styles.votingPowerBar}
              animated
              now={calcResourseCredits(resource_credits)}
            />
          </div>
        )}
      </div>
      {!user_info?.reputation ? (
        ""
      ) : (
        <div className={styles.reputationContainer}>
          <p>Reputation</p>
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
