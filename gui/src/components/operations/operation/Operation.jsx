import { useContext, useState, useEffect } from "react";
import { HeadBlockContext } from "../../../contexts/headBlockContext";
import {
  calculate_hive_hbd,
  calculate_vests,
  calculateHivePower,
} from "../../../functions/calculations";
import { Card, Col, Row } from "react-bootstrap";
import { Link } from "react-router-dom";
import styles from "./operation.module.css";

export default function Operation({ value, type, full_trx }) {
  const { vesting_fund, vesting_shares } = useContext(HeadBlockContext);
  const keys = Object.keys(type.value);
  const [showJson, setShowJson] = useState(false);
  const [showDetails, setShowDetails] = useState(true);
  const [is_page_trx, set_is_page_trx] = useState(null);
  const trx_page = document.location.href.includes("transaction");

  useEffect(() => {
    if (trx_page === true) {
      set_is_page_trx(false);
    } else {
      set_is_page_trx(true);
    }
  }, [trx_page]);

  function prettyViewCard() {
    return (
      <Row className="d-flex">
        <Col xs={2} />
        <Col xs={8} className={styles.prettyCard}>
          {keys.map((key, i) => (
            <Card key={i}>
              <Card.Body className={styles.prettyCardBody}>
                <Row>
                  <Col xs={6}>{key}</Col>
                  <Col xs={6}>{JSON.stringify(type.value[key])}</Col>
                </Row>
              </Card.Body>
            </Card>
          ))}
        </Col>
        <Col xs={2} />
      </Row>
    );
  }

  function more_detailed_view() {
    return (
      <>
        {trx_page === false && (
          <>
            <span>
              {!full_trx.trx_id && (
                <button
                  onClick={() => setShowJson(!showJson)}
                  className={styles.jsonButton}
                >
                  json
                </button>
              )}
              <button
                onClick={() => setShowDetails(!showDetails)}
                className={styles.detailsButton}
              >
                details
              </button>
            </span>

            <div
              style={{ marginTop: "20px", textAlign: "left" }}
              hidden={is_page_trx === false ? false : !showJson}
            >
              <pre style={{ color: "#3aff33" }}>
                {JSON.stringify(full_trx, null, 2)}{" "}
              </pre>
            </div>
            <div hidden={is_page_trx === false ? false : !showDetails}>
              {prettyViewCard()}
            </div>
          </>
        )}
      </>
    );
  }

  function linkToUserAccount(user) {
    return (
      <>
        <Link
          style={{ textDecoration: "none", color: "red" }}
          to={`/user/${user}`}
        >
          {user}
        </Link>
      </>
    );
  }

  switch (value) {
    case "vote_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.voter)}
          </span>
          , author :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.author)}
          </span>
          , permlink:{" "}
          <span>
            <a
              className={styles.link}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
              rel="noreferrer"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "comment_operation":
      return !type.value.parent_author || !type.value.parent_permlink ? (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.author)}
          </span>{" "}
          authored permlink :{" "}
          <span className={styles.bold}>
            <a
              className={styles.link}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
              rel="noreferrer"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </div>
      ) : (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.author)}
          </span>{" "}
          commented{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.parent_author)}
          </span>
          's permlink :
          <span className={styles.bold}>
            <a
              className={styles.link}
              href={`https://hive.blog/@${type.value.parent_author}/${type.value.parent_permlink}`}
              target="_blank"
              rel="noreferrer"
            >
              {type.value.parent_permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "transfer_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from)}
          </span>{" "}
          transfered{" "}
          <span className={styles.bold}>
            {type.value.amount?.amount / 1000}
          </span>{" "}
          HIVE to{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.to)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "transfer_to_vesting_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from)}
          </span>{" "}
          vest{" "}
          <span className={styles.bold}>
            {" "}
            {type.value.amount?.amount / 1000}
          </span>{" "}
          HIVE {more_detailed_view()}
        </div>
      );
    // account withdraw verting_shares (convert to HP) from vesting (show details json)
    case "withdraw_vesting_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          withdraw{" "}
          <span className={styles.bold}>
            {calculateHivePower(
              type.value.vesting_shares.amount,
              vesting_fund,
              vesting_shares
            )}
          </span>{" "}
          HP from vesting {more_detailed_view()}
        </div>
      );
    case "limit_order_create_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          wants receive amount :{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.min_to_receive.amount)}
          </span>{" "}
          HIVE in exchange for{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.amount_to_sell.amount)}
          </span>{" "}
          HBD {more_detailed_view()}
        </div>
      );
    case "limit_order_cancel_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          cancel order ID :{" "}
          <span className={styles.bold}>{type.value.orderid}</span>
        </div>
      );
    case "feed_publish_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.publisher)}
          </span>{" "}
          feed price :
          <span className={styles.bold}>
            {" "}
            $
            {Number(type.value.exchange_rate.base.amount) /
              Number(type.value.exchange_rate.quote.amount)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "convert_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          conversion request :{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          to <span className={styles.bold}>HIVE</span> {more_detailed_view()}
        </div>
      );
    case "account_create_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.creator)}
          </span>{" "}
          create account :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.new_account_name)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "account_update_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          update account data {more_detailed_view()}
        </div>
      );
    case "witness_update_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          update witness {more_detailed_view()}
        </div>
      );
    case "account_witness_vote_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          approve witness{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.witness)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "account_witness_proxy_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          set <span className={styles.bold}>{type.value.proxy}</span> as proxy{" "}
          {more_detailed_view()}
        </div>
      );
    case "pow_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.worker_account)}
          </span>{" "}
          found a pow {more_detailed_view()}
        </div>
      );
    case "custom_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.required_auths)}
          </span>{" "}
          custom operation {more_detailed_view()}
        </div>
      );
    case "report_over_production_operation":
      return <div> report over production {more_detailed_view()} </div>;
    case "delete_comment_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.author)}
          </span>{" "}
          deleted comment permlink :{" "}
          <span>
            {" "}
            <a
              className={styles.link}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
              rel="noreferrer"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "custom_json_operation":
      return (
        <div>
          <span className={styles.bold}>
            {!type?.value.required_posting_auths[0]
              ? linkToUserAccount(type?.value.required_auths[0])
              : linkToUserAccount(type?.value.required_posting_auths[0])}
          </span>{" "}
          custom json operation
          {more_detailed_view()}
        </div>
      );
    case "comment_options_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.author)}
          </span>{" "}
          max payout :{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.max_accepted_payout.amount)}
          </span>{" "}
          ,{" "}
          <span className={styles.bold}>
            {(type.value.percent_hbd / 100).toFixed(2)} %
          </span>
          , allow votes :{" "}
          <span className={styles.boolean}>
            {JSON.stringify(type.value?.allow_votes)}
          </span>
          , allow curation rewards :{" "}
          <span className={styles.boolean}>
            {JSON.stringify(type.value?.allow_curation_rewards)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "set_withdraw_vesting_route_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from_account)}
          </span>{" "}
          to{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.to_account)}
          </span>{" "}
          , percent : <span className={styles.bold}>{type.value.percent}</span>,
          auto vest :{" "}
          <span className={styles.boolean}>
            {JSON.stringify(type.value.auto_vest)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "limit_order_create2_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          limit order create 2 {more_detailed_view()}
        </div>
      );
    case "claim_account_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.creator)}
          </span>{" "}
          claim account {more_detailed_view()}
        </div>
      );
    case "create_claimed_account_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.creator)}
          </span>{" "}
          claimed new account{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.new_account_name)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "request_account_recovery_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account_to_recover)}
          </span>{" "}
          requested{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.recovery_account)}
          </span>{" "}
          for account recovery {more_detailed_view()}
        </div>
      );
    case "recover_account_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account_to_recover)}
          </span>{" "}
          recover account {more_detailed_view()}
        </div>
      );
    case "change_recovery_account_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account_to_recover)}
          </span>{" "}
          change recovery account to new account :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.new_recovery_account)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "escrow_transfer_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from)}
          </span>{" "}
          escrow transfer to :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.to)}
          </span>{" "}
          , agent :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.agent)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "escrow_dispute_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from)}
          </span>{" "}
          escrow dispute to :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.to)}
          </span>{" "}
          , agent :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.agent)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "escrow_release_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from)}
          </span>{" "}
          escrow release to :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.to)}
          </span>{" "}
          , agent :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.agent)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "pow2_operation":
      return (
        <div>
          <span className={styles.bold}>
            {" "}
            {linkToUserAccount(type.value.work.value.input.worker_account)}
          </span>{" "}
          found a pow {more_detailed_view()}
        </div>
      );
    case "escrow_approve_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from)}
          </span>{" "}
          escrow approve {more_detailed_view()}
        </div>
      );
    case "transfer_to_savings_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value?.from)}
          </span>{" "}
          transfer to savings :{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "transfer_from_savings_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value?.from)}
          </span>{" "}
          transfer from savings :{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "cancel_transfer_from_savings_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from)}
          </span>{" "}
          cancel transfer from savings {more_detailed_view()}
        </div>
      );
    case "custom_binary_operation":
      return <div>Custom binary {more_detailed_view()}</div>;
    case "decline_voting_rights_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          decline voting rights {more_detailed_view()}
        </div>
      );
    case "reset_account_operation":
      return <p className={styles.text}>reset account</p>;
    case "set_reset_account_operation":
      return <p className={styles.text}>set reset account</p>;
    case "claim_reward_balance_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          claim reward :{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.reward_hive.amount)} HIVE
          </span>
          ,{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.reward_hbd.amount)} HBD
          </span>
          ,{" "}
          <span className={styles.bold}>
            {calculateHivePower(
              type.value.reward_vests.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "delegate_vesting_shares_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.delegator)}
          </span>{" "}
          delegate{" "}
          <span className={styles.bold}>
            {calculateHivePower(
              type.value.vesting_shares.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          to{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.delegatee)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "account_create_with_delegation_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.creator)}
          </span>{" "}
          create account{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.new_account_name)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "witness_set_properties_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          witness set properties {more_detailed_view()}
        </div>
      );
    case "account_update2_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          account update2 {more_detailed_view()}
        </div>
      );
    case "create_proposal_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.creator)}
          </span>{" "}
          create proposal subject :{" "}
          <span className={styles.bold}>{type.value.subject}</span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "update_proposal_votes_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.voter)}
          </span>{" "}
          update proposal votes {more_detailed_view()}
        </div>
      );
    case "remove_proposal_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.proposal_owner)}
          </span>{" "}
          remove proposal {more_detailed_view()}
        </div>
      );
    case "update_proposal_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.creator)}
          </span>{" "}
          update proposal {more_detailed_view()}
        </div>
      );
    case "collateralized_convert_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          collateralized convert amount :{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HIVE
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "recurrent_transfer_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from)}
          </span>{" "}
          recurrent transfer to{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.to)}
          </span>
          , amount :{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "fill_convert_request_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          fill convert request, amount in :
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.amount_in.amount)} HBD
          </span>{" "}
          , amount out:{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.amount_out.amount)} HIVE
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "author_reward_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.author)}
          </span>{" "}
          author reward :
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.hbd_payout.amount)} HBD
          </span>{" "}
          , amount out:{" "}
          <span className={styles.bold}>
            {calculateHivePower(
              type.value.vesting_payout.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          for{" "}
          <span>
            <a
              className={styles.link}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
              rel="noreferrer"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "curation_reward_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.curator)}
          </span>{" "}
          curation reward{" "}
          <span className={styles.bold}>
            {calculateHivePower(
              type.value.reward.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          , comment author :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.comment_author)}
          </span>{" "}
          , comment permlink:{" "}
          <span>
            <a
              className={styles.link}
              href={`https://hive.blog/@${type.value.comment_author}/${type.value.comment_permlink}`}
              target="_blank"
              rel="noreferrer"
            >
              {type.value.comment_permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "comment_reward_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.author)}
          </span>{" "}
          comment reward{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.payout.amount)} HBD
          </span>{" "}
          permlink:{" "}
          <span>
            <a
              className={styles.link}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
              rel="noreferrer"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "liquidity_reward_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          liquidity reward{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.payout.amount)} HIVE
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "interest_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          collect{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.interest.amount)} HBD
          </span>{" "}
          interest {more_detailed_view()}
        </div>
      );
    case "fill_vesting_withdraw_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from_account)}
          </span>{" "}
          withdraw{" "}
          <span className={styles.bold}>
            {calculateHivePower(
              type.value.withdrawn.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          as{" "}
          <span className={styles.bold}>
            {type.value.to_account === type.value.from_account
              ? `${calculate_hive_hbd(type.value.deposited.amount)} HIVE`
              : `${calculateHivePower(
                  type.value.deposited.amount,
                  vesting_fund,
                  vesting_shares
                )} HP to ${linkToUserAccount(type.value.to_account)}`}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "fill_order_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.current_owner)}
          </span>{" "}
          fill order, open owner{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.open_owner)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "shutdown_witness_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.owner)}
          </span>{" "}
          shutdown witness {more_detailed_view()}
        </div>
      );
    case "fill_transfer_from_savings_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.from)}
          </span>{" "}
          fill transfer from savings{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "hardfork_operation":
      return (
        <div>
          Hardfork ID:{" "}
          <span className={styles.bold}>{type.value.hardfork_id}</span>{" "}
          {more_detailed_view()}
        </div>
      );

    case "comment_payout_update_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.author)}
          </span>{" "}
          comment payout update {more_detailed_view()}
        </div>
      );
    case "return_vesting_delegation_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          return of{" "}
          <span className={styles.bold}>
            {calculateHivePower(
              type.value.vesting_shares.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          delegation {more_detailed_view()}
        </div>
      );
    case "comment_benefactor_reward_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.benefactor)}
          </span>{" "}
          comment benefactor reward :{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.hbd_payout.amount)} HBD
          </span>{" "}
          and{" "}
          <span className={styles.bold}>
            {calculateHivePower(
              type.value.vesting_payout.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          for{" "}
          <span>
            <a
              className={styles.link}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
              rel="noreferrer"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "producer_reward_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.producer)}
          </span>{" "}
          producer reward :{" "}
          <span className={styles.bold}>
            {calculateHivePower(
              type.value.vesting_shares.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "clear_null_account_balance_operation":
      return (
        <div>
          Clear null account balance, total cleared:{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.total_cleared[0].amount)} HIVE{" "}
          </span>
          ,{" "}
          <span className={styles.bold}>
            {calculate_vests(type?.value?.total_cleared[1]?.amount)} VESTS{" "}
          </span>
          ,{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value?.total_cleared[2]?.amount)} HBD{" "}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "proposal_pay_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.receiver)}
          </span>{" "}
          receive{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.payment.amount)} HIVE{" "}
          </span>{" "}
          proposal funding {more_detailed_view()}
        </div>
      );
    case "sps_fund_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.fund_account)}
          </span>{" "}
          additional fuds{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.additional_funds.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "hardfork_hive_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          hardfork hive{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.value, null, 2)}
            </pre>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "hardfork_hive_restore_operation":
      return (
        <div>
          {" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          hardfork hive restore{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.value, null, 2)}
            </pre>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "delayed_voting_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.voter)}
          </span>{" "}
          delayer voting {more_detailed_view()}
        </div>
      );
    case "consolidate_treasury_balance_operation":
      return (
        <div>
          Consolidate treasury balance{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.value, null, 2)}
            </pre>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "effective_comment_vote_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.voter)}
          </span>{" "}
          effective comment vote {more_detailed_view()}
        </div>
      );
    case "ineffective_delete_comment_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.author)}
          </span>{" "}
          ineffective delete comment permlink :{" "}
          <span>
            <a
              className={styles.link}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
              rel="noreferrer"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "sps_convert_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.fund_account)}
          </span>{" "}
          amount in{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.hive_amount_in.amount)} HIVE
          </span>
          , amount out{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.hbd_amount_out.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "expired_account_notification_operation":
      return <p className={styles.text}>Expired account notification</p>;
    case "changed_recovery_account_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          change recovery account , old account :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.old_recovery_account)}
          </span>
          , new account :{" "}
          <span className={styles.bold}>
            {linkToUserAccount(type.value.new_recovery_account)}
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "transfer_to_vesting_completed_operation":
      return (
        <div>
          <div>
            {" "}
            <span className={styles.bold}>
              {linkToUserAccount(type.value.from_account)}
            </span>{" "}
            transfer to vesting completed.
          </div>
          <div>
            Hive vested :{" "}
            <span className={styles.bold}>
              {calculate_hive_hbd(type.value.hive_vested.amount)} HIVE
            </span>
          </div>
          <div>
            Vesting shares received :{" "}
            <span className={styles.bold}>
              {calculate_vests(type.value.vesting_shares_received.amount)} VESTS
            </span>
          </div>{" "}
          {more_detailed_view()}
        </div>
      );
    case "pow_reward_operation":
      return (
        <div>
          <span className={styles.bold}>
            {linkToUserAccount(type.value.worker)}
          </span>{" "}
          pow reward{" "}
          <span className={styles.bold}>
            {calculate_hive_hbd(type.value.reward.amount)} HIVE
          </span>{" "}
          {more_detailed_view()}
        </div>
      );
    case "vesting_shares_split_operation":
      return (
        <div>
          <div>
            <span className={styles.bold}>
              {linkToUserAccount(type.value.owner)}
            </span>{" "}
            vesting shares split{" "}
          </div>
          <div>
            Vesting shares before split :{" "}
            <span className={styles.bold}>
              {calculate_vests(type.value.vesting_shares_before_split.amount)}{" "}
              VESTS
            </span>
          </div>
          <div>
            Vesting shares after split :{" "}
            <span className={styles.bold}>
              {calculate_vests(type.value.vesting_shares_after_split.amount)}{" "}
              VESTS
            </span>{" "}
            {more_detailed_view()}
          </div>
        </div>
      );
    // NO CREATOR VALUE
    case "account_created_operation":
      return (
        <div>
          <div>
            Created new account name{" "}
            <span className={styles.bold}>
              {linkToUserAccount(type.value.new_account_name)}
            </span>{" "}
            {more_detailed_view()}
          </div>
        </div>
      );

    case "fill_collateralized_convert_request_operation":
      return (
        <div>
          <div>
            <span className={styles.bold}>
              {linkToUserAccount(type.value.owner)}
            </span>{" "}
            fill collateralized convert request
          </div>
          <div>
            Amount in:{" "}
            <span className={styles.bold}>
              {calculate_hive_hbd(type.value.amount_in.amount)} HIVE
            </span>
          </div>
          <div>
            Amount out:{" "}
            <span className={styles.bold}>
              {calculate_hive_hbd(type.value.amount_out.amount)} HBD
            </span>
          </div>
          <div>
            Excess collateral:{" "}
            <span className={styles.bold}>
              {calculate_hive_hbd(type.value.excess_collateral.amount)} HIVE
            </span>
          </div>{" "}
          {more_detailed_view()}
        </div>
      );
    case "system_warning_operation":
      return (
        <div>
          <div>
            System warning message : <br></br>
            <span className={styles.bold}>{type.value.message}</span>
          </div>{" "}
          {more_detailed_view()}
        </div>
      );
    case "fill_recurrent_transfer_operation":
      return (
        <div>
          <div>
            <span className={styles.bold}>
              {linkToUserAccount(type.value.from)}
            </span>{" "}
            fill recurrent transfer to{" "}
            <span className={styles.bold}>
              {linkToUserAccount(type.value.to)}
            </span>
          </div>
          <div>
            Amount :{" "}
            <span className={styles.bold}>
              {calculate_hive_hbd(type.value.amount.amount)} HIVE
            </span>
          </div>{" "}
          {more_detailed_view()}
        </div>
      );
    case "failed_recurrent_transfer_operation":
      return (
        <div>
          <div>
            <span className={styles.bold}>
              {linkToUserAccount(type.value.from)}
            </span>{" "}
            failed recurrent transfer to{" "}
            <span className={styles.bold}>
              {linkToUserAccount(type.value.to)}
            </span>
          </div>
          <div>
            Amount :{" "}
            <span className={styles.bold}>
              {calculate_hive_hbd(type.value.amount.amount)} HIVE
            </span>
          </div>{" "}
          {more_detailed_view()}
        </div>
      );
    case "limit_order_cancelled_operation":
      return (
        <div>
          <div>
            <span className={styles.bold}>
              {linkToUserAccount(type.value.seller)}
            </span>{" "}
            limit order cancelled
          </div>
          <div>
            Amount back :{" "}
            <span className={styles.bold}>
              {calculate_hive_hbd(type.value.amount_back.amount)} HIVE
            </span>
          </div>{" "}
          {more_detailed_view()}
        </div>
      );
    default:
      return null;
  }
}
