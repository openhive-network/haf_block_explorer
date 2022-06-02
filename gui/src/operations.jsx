import { useContext, useState, useEffect } from "react";
import { HeadBlockContext } from "./contexts/headBlockContext";
import {
  calculate_hive_hbd,
  calculate_vests,
  calculateHivePower,
} from "./functions";
import { Card, Col, Row } from "react-bootstrap";
import { Link } from "react-router-dom";

const red_bold = {
  fontWeight: "bold",
  // color: "red",
  fontSize: "15px",
};
const green_bold = {
  fontWeight: "bold",
  // color: "green",
  fontSize: "15px",
};
const blue_bold = {
  fontWeight: "bold",
  // color: "blue",
  fontSize: "15px",
};
const p_styles = {
  margin: "0px",
};
const show_json_button = {
  textTransform: "upperCase",
  background: "inherit",
  border: "0px",
  color: "lime",
};
const show_details_button = {
  textTransform: "upperCase",
  background: "inherit",
  border: "0px",
  color: "red",
};

const img_style = {
  width: "40px",
  height: "40px",
  borderRadius: "50%",
};

const link_text = { color: "pink", textTransform: "none" };
const boolean = { color: "#34f0c7" };

export default function GetOperations({ value, type, full_trx }) {
  const { vesting_fund, vesting_shares } = useContext(HeadBlockContext);
  const keys = Object.keys(type.value);
  const [showJson, setShowJson] = useState(false);
  const [showDetails, setShowDetails] = useState(false);
  const [is_page_trx, set_is_page_trx] = useState(null);
  const trx_page = document.location.href.includes("transaction");

  useEffect(() => {
    if (trx_page === true) {
      set_is_page_trx(false);
    } else {
      set_is_page_trx(true);
    }
  }, [trx_page]);
  // const [showJson, setShowJson] = useState(false);
  // const [showDetails, setShowDetails] = useState(false);
  // const vesting_fund = Number(head_block?.total_vesting_fund_hive?.amount);
  // const vesting_shares = Number(head_block?.total_vesting_shares?.amount);
  // const operation_value = JSON.stringify(type.value, null, 2);

  // const calculate_hive_hbd = (value) => {
  //   const res = Number(value) / 1000;
  //   return res.toFixed(2);
  // };

  // const calculate_vests = (value) => {
  //   const res = Number(value) / 1000000;
  //   return res.toFixed(2);
  // };

  function prettyViewCard() {
    return (
      <Row className="d-flex">
        <Col xs={2} />
        <Col
          xs={8}
          style={{
            marginTop: "20px",
            // display: "flex",
            // flexDirection: "column",
            textAlign: "left",
          }}
        >
          {keys.map((key, i) => (
            <Card key={i}>
              <Card.Body
                style={{
                  // width: "60%",
                  color: "#fcff31",
                  background: "#2C3136",
                  padding: "5px",
                }}
              >
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
        <span>
          <button
            onClick={() => setShowJson(!showJson)}
            style={show_json_button}
          >
            Show JSON
          </button>
          <button
            onClick={() => setShowDetails(!showDetails)}
            style={show_details_button}
          >
            Show details
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
    );
  }
  // const [showJson, setShowJson] = useState(false);

  // const calculateHivePower = (account_vests) => {
  //   const vest_sum = vesting_fund * (Number(account_vests) / vesting_shares);
  //   const hive_power = vest_sum / 1000;
  //   return hive_power.toFixed(2);
  // };
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
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.voter)}</span>,
          author :{" "}
          <span style={red_bold}>{linkToUserAccount(type.value.author)}</span>,
          permlink:{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "comment_operation":
      return !type.value.parent_author || !type.value.parent_permlink ? (
        <p style={p_styles}>
          <span red_bold={red_bold}>
            {linkToUserAccount(type.value.author)}
          </span>
          authored permlink :
          <span red_bold={red_bold}>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </p>
      ) : (
        <p style={p_styles}>
          <span red_bold={red_bold}>
            {linkToUserAccount(type.value.author)}
          </span>{" "}
          commented{" "}
          <span red_bold={red_bold}>
            {linkToUserAccount(type.value.parent_author)}
          </span>
          's permlink :
          <span red_bold={red_bold}>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.value.parent_author}/${type.value.parent_permlink}`}
              target="_blank"
            >
              {type.value.parent_permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "transfer_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
          transfered{" "}
          <span style={blue_bold}>{type.value.amount?.amount / 1000}</span> HIVE
          to <span style={green_bold}>{linkToUserAccount(type.value.to)}</span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "transfer_to_vesting_operation":
      return (
        <p style={p_styles}>
          <span style={blue_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
          vest{" "}
          <span style={green_bold}> {type.value.amount?.amount / 1000}</span>{" "}
          HIVE {more_detailed_view()}
        </p>
      );
    // account withdraw verting_shares (convert to HP) from vesting (show details json)
    case "withdraw_vesting_operation":
      return (
        <p style={p_styles}>
          <span style={blue_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          withdraw{" "}
          <span style={green_bold}>
            {calculateHivePower(
              type.value.vesting_shares.amount,
              vesting_fund,
              vesting_shares
            )}
          </span>{" "}
          HP from vesting {more_detailed_view()}
        </p>
      );
    case "limit_order_create_operation":
      return (
        <p style={p_styles}>
          <span style={blue_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          wants receive amount :{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.value.min_to_receive.amount)}
          </span>{" "}
          HIVE in exchange for{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.value.amount_to_sell.amount)}
          </span>{" "}
          HBD {more_detailed_view()}
        </p>
      );
    case "limit_order_cancel_operation":
      return (
        <p style={p_styles}>
          <span style={blue_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          cancel order ID : <span style={red_bold}>{type.value.orderid}</span>
        </p>
      );
    case "feed_publish_operation":
      return (
        <p style={p_styles}>
          <span style={blue_bold}>
            {linkToUserAccount(type.value.publisher)}
          </span>{" "}
          feed price :
          <span style={red_bold}>
            {" "}
            $
            {Number(type.value.exchange_rate.base.amount) /
              Number(type.value.exchange_rate.quote.amount)}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "convert_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          conversion request :{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          to <span style={green_bold}>HIVE</span> {more_detailed_view()}
        </p>
      );
    case "account_create_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.creator)}</span>{" "}
          create account :{" "}
          <span style={green_bold}>
            {linkToUserAccount(type.value.new_account_name)}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "account_update_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          update account data {more_detailed_view()}
        </p>
      );
    case "witness_update_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          update witness {more_detailed_view()}
        </p>
      );
    case "account_witness_vote_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          approve witness{" "}
          <span style={blue_bold}>{linkToUserAccount(type.value.witness)}</span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "account_witness_proxy_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          set <span style={blue_bold}>{type.value.proxy}</span> as proxy{" "}
          {more_detailed_view()}
        </p>
      );
    case "pow_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.worker_account)}
          </span>{" "}
          found a pow {more_detailed_view()}
        </p>
      );
    case "custom_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.required_auths)}
          </span>{" "}
          custom operation{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "report_over_production_operation":
      return (
        <p style={p_styles}> report over production {more_detailed_view()} </p>
      );
    case "delete_comment_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.author)}</span>{" "}
          deleted comment permlink :{" "}
          <span>
            {" "}
            <a
              style={link_text}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "custom_json_operation":
      return (
        <>
          <span style={red_bold}>
            {!type?.value.required_posting_auths[0]
              ? linkToUserAccount(type?.value.required_auths[0])
              : linkToUserAccount(type?.value.required_posting_auths[0])}
          </span>{" "}
          custom json operation
          {more_detailed_view()}
        </>
      );
    case "comment_options_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.author)}</span>{" "}
          max payout :{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.max_accepted_payout.amount)}
          </span>{" "}
          ,{" "}
          <span style={blue_bold}>
            {(type.value.percent_hbd / 100).toFixed(2)} %
          </span>
          , allow votes :{" "}
          <span style={boolean}>{JSON.stringify(type.value?.allow_votes)}</span>
          , allow curation rewards :{" "}
          <span style={boolean}>
            {JSON.stringify(type.value?.allow_curation_rewards)}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "set_withdraw_vesting_route_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.from_account)}
          </span>{" "}
          to{" "}
          <span style={green_bold}>
            {linkToUserAccount(type.value.to_account)}
          </span>{" "}
          , percent : <span style={blue_bold}>{type.value.percent}</span>, auto
          vest :{" "}
          <span style={boolean}>{JSON.stringify(type.value.auto_vest)}</span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "limit_order_create2_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          limit order create 2 {more_detailed_view()}
        </p>
      );
    case "claim_account_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.creator)}</span>{" "}
          claim account {more_detailed_view()}
        </p>
      );
    case "create_claimed_account_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.creator)}</span>{" "}
          claimed new account{" "}
          <span style={blue_bold}>
            {linkToUserAccount(type.value.new_account_name)}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "request_account_recovery_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.account_to_recover)}
          </span>{" "}
          requested{" "}
          <span style={green_bold}>
            {linkToUserAccount(type.value.recovery_account)}
          </span>{" "}
          for account recovery {more_detailed_view()}
        </p>
      );
    case "recover_account_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.account_to_recover)}
          </span>{" "}
          recover account {more_detailed_view()}
        </p>
      );
    case "change_recovery_account_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.account_to_recover)}
          </span>{" "}
          change recovery account to new account :{" "}
          <span style={blue_bold}>
            {linkToUserAccount(type.value.new_recovery_account)}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "escrow_transfer_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
          escrow transfer to :{" "}
          <span style={blue_bold}>{linkToUserAccount(type.value.to)}</span> ,
          agent :{" "}
          <span style={green_bold}>{linkToUserAccount(type.value.agent)}</span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "escrow_dispute_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
          escrow dispute to :{" "}
          <span style={blue_bold}>{linkToUserAccount(type.value.to)}</span> ,
          agent :{" "}
          <span style={green_bold}>{linkToUserAccount(type.value.agent)}</span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "escrow_release_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
          escrow release to :{" "}
          <span style={blue_bold}>{linkToUserAccount(type.value.to)}</span> ,
          agent :{" "}
          <span style={green_bold}>{linkToUserAccount(type.value.agent)}</span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "pow2_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {" "}
            {linkToUserAccount(type.value.work.value.input.worker_account)}
          </span>{" "}
          found a pow {more_detailed_view()}
        </p>
      );
    case "escrow_approve_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
          escrow approve {more_detailed_view()}
        </p>
      );
    case "transfer_to_savings_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value?.from)}</span>{" "}
          transfer to savings :{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "transfer_from_savings_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value?.from)}</span>{" "}
          transfer from savings :{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "cancel_transfer_from_savings_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
          cancel transfer from savings {more_detailed_view()}
        </p>
      );
    case "custom_binary_operation":
      return <p style={p_styles}>Custom binary {more_detailed_view()}</p>;
    case "decline_voting_rights_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          decline voting rights {more_detailed_view()}
        </p>
      );
    case "reset_account_operation":
      return <p style={p_styles}>reset account</p>;
    case "set_reset_account_operation":
      return <p style={p_styles}>set reset account</p>;
    case "claim_reward_balance_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          claim reward :{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.value.reward_hive.amount)} HIVE
          </span>
          ,{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.reward_hbd.amount)} HBD
          </span>
          ,{" "}
          <span style={red_bold}>
            {calculateHivePower(
              type.value.reward_vests.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "delegate_vesting_shares_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.delegator)}
          </span>{" "}
          delegate{" "}
          <span style={green_bold}>
            {calculateHivePower(
              type.value.vesting_shares.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          to{" "}
          <span style={blue_bold}>
            {linkToUserAccount(type.value.delegatee)}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "account_create_with_delegation_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.creator)}</span>{" "}
          create account{" "}
          <span style={blue_bold}>
            {linkToUserAccount(type.value.new_account_name)}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "witness_set_properties_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          witness set properties {more_detailed_view()}
        </p>
      );
    case "account_update2_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          account update2 {more_detailed_view()}
        </p>
      );
    case "create_proposal_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.creator)}</span>{" "}
          create proposal subject :{" "}
          <span style={blue_bold}>{type.value.subject}</span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "update_proposal_votes_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.voter)}</span>{" "}
          update proposal votes {more_detailed_view()}
        </p>
      );
    case "remove_proposal_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.proposal_owner)}
          </span>{" "}
          remove proposal {more_detailed_view()}
        </p>
      );
    case "update_proposal_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.creator)}</span>{" "}
          update proposal {more_detailed_view()}
        </p>
      );
    case "collateralized_convert_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          collateralized convert amount :{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HIVE
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "recurrent_transfer_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
          recurrent transfer to{" "}
          <span style={blue_bold}>{linkToUserAccount(type.value.to)}</span>,
          amount :{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "fill_convert_request_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          fill convert request, amount in :
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.amount_in.amount)} HBD
          </span>{" "}
          , amount out:{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.amount_out.amount)} HIVE
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "author_reward_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.author)}</span>{" "}
          author reward :
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.hbd_payout.amount)} HBD
          </span>{" "}
          , amount out:{" "}
          <span style={green_bold}>
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
              style={link_text}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "curation_reward_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.curator)}</span>{" "}
          curation reward{" "}
          <span style={green_bold}>
            {calculateHivePower(
              type.value.reward.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          , comment author :{" "}
          <span style={green_bold}>
            {linkToUserAccount(type.value.comment_author)}
          </span>{" "}
          , comment permlink:{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.value.comment_author}/${type.value.comment_permlink}`}
              target="_blank"
            >
              {type.value.comment_permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "comment_reward_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.author)}</span>{" "}
          comment reward{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.payout.amount)} HBD
          </span>{" "}
          permlink:{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "liquidity_reward_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          liquidity reward{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.payout.amount)} HIVE
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "interest_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          collect{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.interest.amount)} HBD
          </span>{" "}
          interest {more_detailed_view()}
        </p>
      );
    case "fill_vesting_withdraw_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.from_account)}
          </span>{" "}
          withdraw{" "}
          <span style={green_bold}>
            {calculateHivePower(
              type.value.withdrawn.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          as{" "}
          <span style={blue_bold}>
            {type.value.to_account === type.value.from_account
              ? `${calculate_hive_hbd(type.value.deposited.amount)} HIVE`
              : `${calculateHivePower(
                  type.value.deposited.amount,
                  vesting_fund,
                  vesting_shares
                )} HP to ${linkToUserAccount(type.value.to_account)}`}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "fill_order_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.current_owner)}
          </span>{" "}
          fill order, open owner{" "}
          <span style={green_bold}>
            {linkToUserAccount(type.value.open_owner)}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "shutdown_witness_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
          shutdown witness {more_detailed_view()}
        </p>
      );
    case "fill_transfer_from_savings_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
          fill transfer from savings{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.value.amount.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "hardfork_operation":
      return (
        <p style={p_styles}>
          Hardfork ID: <span style={red_bold}>{type.value.hardfork_id}</span>{" "}
          {more_detailed_view()}
        </p>
      );

    case "comment_payout_update_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.author)}</span>{" "}
          comment payout update {more_detailed_view()}
        </p>
      );
    case "return_vesting_delegation_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          return of{" "}
          <span style={blue_bold}>
            {calculateHivePower(
              type.value.vesting_shares.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          delegation {more_detailed_view()}
        </p>
      );
    case "comment_benefactor_reward_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.benefactor)}
          </span>{" "}
          comment benefactor reward :{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.hbd_payout.amount)} HBD
          </span>{" "}
          and{" "}
          <span style={green_bold}>
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
              style={link_text}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "producer_reward_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.producer)}</span>{" "}
          producer reward :{" "}
          <span style={green_bold}>
            {calculateHivePower(
              type.value.vesting_shares.amount,
              vesting_fund,
              vesting_shares
            )}{" "}
            HP
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "clear_null_account_balance_operation":
      return (
        <p style={p_styles}>
          Clear null account balance, total cleared:{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.value.total_cleared[0].amount)} HIVE{" "}
          </span>
          ,{" "}
          <span style={blue_bold}>
            {calculate_vests(type?.value?.total_cleared[1]?.amount)} VESTS{" "}
          </span>
          ,{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.value?.total_cleared[2]?.amount)} HBD{" "}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "proposal_pay_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.receiver)}</span>{" "}
          receive{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.value.payment.amount)} HIVE{" "}
          </span>{" "}
          proposal funding {more_detailed_view()}
        </p>
      );
    case "sps_fund_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.fund_account)}
          </span>{" "}
          additional fuds{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.value.additional_funds.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "hardfork_hive_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          hardfork hive{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.value, null, 2)}
            </pre>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "hardfork_hive_restore_operation":
      return (
        <p style={p_styles}>
          {" "}
          <span style={red_bold}>
            {linkToUserAccount(type.value.account)}
          </span>{" "}
          hardfork hive restore{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.value, null, 2)}
            </pre>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "delayed_voting_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.voter)}</span>{" "}
          delayer voting {more_detailed_view()}
        </p>
      );
    case "consolidate_treasury_balance_operation":
      return (
        <p style={p_styles}>
          Consolidate treasury balance{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.value, null, 2)}
            </pre>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "effective_comment_vote_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.voter)}</span>{" "}
          effective comment vote {more_detailed_view()}
        </p>
      );
    case "ineffective_delete_comment_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.author)}</span>{" "}
          ineffective delete comment permlink :{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.value.author}/${type.value.permlink}`}
              target="_blank"
            >
              {type.value.permlink}
            </a>
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "sps_convert_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>
            {linkToUserAccount(type.value.fund_account)}
          </span>{" "}
          amount in{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.value.hive_amount_in.amount)} HIVE
          </span>
          , amount out{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.value.hbd_amount_out.amount)} HBD
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "expired_account_notification_operation":
      return <p style={p_styles}>Expired account notification</p>;
    case "changed_recovery_account_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.account)}</span>{" "}
          change recovery account , old account :{" "}
          <span style={blue_bold}>
            {linkToUserAccount(type.value.old_recovery_account)}
          </span>
          , new account :{" "}
          <span style={blue_bold}>
            {linkToUserAccount(type.value.new_recovery_account)}
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "transfer_to_vesting_completed_operation":
      return (
        <>
          <p style={p_styles}>
            {" "}
            <span style={red_bold}>
              {linkToUserAccount(type.value.from_account)}
            </span>{" "}
            transfer to vesting completed.
          </p>
          <p style={p_styles}>
            Hive vested :{" "}
            <span style={blue_bold}>
              {calculate_hive_hbd(type.value.hive_vested.amount)} HIVE
            </span>
          </p>
          <p style={p_styles}>
            Vesting shares received :{" "}
            <span style={blue_bold}>
              {calculate_vests(type.value.vesting_shares_received.amount)} VESTS
            </span>
          </p>{" "}
          {more_detailed_view()}
        </>
      );
    case "pow_reward_operation":
      return (
        <p style={p_styles}>
          <span style={red_bold}>{linkToUserAccount(type.value.worker)}</span>{" "}
          pow reward{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.value.reward.amount)} HIVE
          </span>{" "}
          {more_detailed_view()}
        </p>
      );
    case "vesting_shares_split_operation":
      return (
        <>
          <p style={p_styles}>
            <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
            vesting shares split{" "}
          </p>
          <p style={p_styles}>
            Vesting shares before split :{" "}
            <span style={blue_bold}>
              {calculate_vests(type.value.vesting_shares_before_split.amount)}{" "}
              VESTS
            </span>
          </p>
          <p style={p_styles}>
            Vesting shares after split :{" "}
            <span style={blue_bold}>
              {calculate_vests(type.value.vesting_shares_after_split.amount)}{" "}
              VESTS
            </span>{" "}
            <span>
              <button
                onClick={() => setShowJson(!showJson)}
                style={show_json_button}
              >
                Show JSON
              </button>
              <button
                onClick={() => setShowDetails(!showDetails)}
                style={show_details_button}
              >
                Show details
              </button>
            </span>
            <div hidden={!showJson}>
              <pre>{JSON.stringify(full_trx, null, 2)} </pre>
            </div>
            <div hidden={!showDetails}>{prettyViewCard()}</div>
          </p>
        </>
      );
    // NO CREATOR VALUE
    case "account_created_operation":
      return (
        <>
          <p style={p_styles}>
            Created new account name{" "}
            <span style={red_bold}>
              {linkToUserAccount(type.value.new_account_name)}
            </span>{" "}
            <span>
              <button
                onClick={() => setShowJson(!showJson)}
                style={show_json_button}
              >
                Show JSON
              </button>
              <button
                onClick={() => setShowDetails(!showDetails)}
                style={show_details_button}
              >
                Show details
              </button>
            </span>
            <div hidden={!showJson}>
              <pre>{JSON.stringify(full_trx, null, 2)} </pre>
            </div>
            <div hidden={!showDetails}>{prettyViewCard()}</div>
          </p>
        </>
      );

    case "fill_collateralized_convert_request_operation":
      return (
        <>
          <p style={p_styles}>
            <span style={red_bold}>{linkToUserAccount(type.value.owner)}</span>{" "}
            fill collateralized convert request
          </p>
          <p style={p_styles}>
            Amount in:{" "}
            <span style={blue_bold}>
              {calculate_hive_hbd(type.value.amount_in.amount)} HIVE
            </span>
          </p>
          <p style={p_styles}>
            Amount out:{" "}
            <span style={blue_bold}>
              {calculate_hive_hbd(type.value.amount_out.amount)} HBD
            </span>
          </p>
          <p style={p_styles}>
            Excess collateral:{" "}
            <span style={blue_bold}>
              {calculate_hive_hbd(type.value.excess_collateral.amount)} HIVE
            </span>
          </p>{" "}
          {more_detailed_view()}
        </>
      );
    case "system_warning_operation":
      return (
        <>
          <p style={p_styles}>
            System warning message : <br></br>
            <span style={red_bold}>{type.value.message}</span>
          </p>{" "}
          {more_detailed_view()}
        </>
      );
    case "fill_recurrent_transfer_operation":
      return (
        <>
          <p style={p_styles}>
            <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
            fill recurrent transfer to{" "}
            <span style={blue_bold}>{linkToUserAccount(type.value.to)}</span>
          </p>
          <p style={p_styles}>
            Amount :{" "}
            <span style={red_bold}>
              {calculate_hive_hbd(type.value.amount.amount)} HIVE
            </span>
          </p>{" "}
          {more_detailed_view()}
        </>
      );
    case "failed_recurrent_transfer_operation":
      return (
        <>
          <p style={p_styles}>
            <span style={red_bold}>{linkToUserAccount(type.value.from)}</span>{" "}
            failed recurrent transfer to{" "}
            <span style={blue_bold}>{linkToUserAccount(type.value.to)}</span>
          </p>
          <p style={p_styles}>
            Amount :{" "}
            <span style={red_bold}>
              {calculate_hive_hbd(type.value.amount.amount)} HIVE
            </span>
          </p>{" "}
          {more_detailed_view()}
        </>
      );
    case "limit_order_cancelled_operation":
      return (
        <>
          <p style={p_styles}>
            <span style={red_bold}>{linkToUserAccount(type.value.seller)}</span>{" "}
            limit order cancelled
          </p>
          <p style={p_styles}>
            Amount back :{" "}
            <span style={red_bold}>
              {calculate_hive_hbd(type.value.amount_back.amount)} HIVE
            </span>
          </p>{" "}
          {more_detailed_view()}
        </>
      );
    default:
  }
}
