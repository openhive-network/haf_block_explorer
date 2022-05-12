import { useContext } from "react";
import { HeadBlockContext } from "./contexts/headBlockContext";
const red_bold = {
  fontWeight: "bold",
  color: "red",
  fontSize: "20px",
};
const green_bold = {
  fontWeight: "bold",
  color: "green",
  fontSize: "20px",
};
const blue_bold = {
  fontWeight: "bold",
  color: "blue",
  fontSize: "20px",
};

const show_details_button = {
  textTransform: "upperCase",
  background: "inherit",
  border: "0px",
  color: "lime",
};

const link_text = { color: "pink", textTransform: "none" };
const boolean = { color: "#34f0c7" };

export default function GetOperations({ value, type, showJson, setShowJson }) {
  const { head_block } = useContext(HeadBlockContext);
  const vesting_fund = Number(head_block?.total_vesting_fund_hive?.amount);
  const vesting_shares = Number(head_block?.total_vesting_shares?.amount);
  // const operation_value = JSON.stringify(type.op.value, null, 2);

  const calculate_hive_hbd = (value) => {
    const res = Number(value) / 1000;
    return res.toFixed(2);
  };

  const calculate_vests = (value) => {
    const res = Number(value) / 1000000;
    return res.toFixed(2);
  };

  const calculateHivePower = (account_vests) => {
    const vest_sum = vesting_fund * (Number(account_vests) / vesting_shares);
    const hive_power = vest_sum / 1000;
    return hive_power.toFixed(2);
  };
  switch (value) {
    case "vote_operation":
      return (
        <p>
          Voter : <span red_bold={red_bold}>{type.op.value.voter}</span>, author
          : <span red_bold={red_bold}>{type.op.value.author}</span>, permlink:{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.op.value.author}/${type.op.value.permlink}`}
              target="_blank"
            >
              {type.op.value.permlink}
            </a>
          </span>
        </p>
      );
      break;
    case "comment_operation":
      return !type.op.value.parent_author || !type.op.value.parent_permlink ? (
        <p>
          Author : <span red_bold={red_bold}>{type.op.value.author} </span>
          authored permlink :
          <span red_bold={red_bold}>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.op.value.author}/${type.op.value.permlink}`}
              target="_blank"
            >
              {type.op.value.permlink}
            </a>
          </span>{" "}
        </p>
      ) : (
        <p>
          Author : <span red_bold={red_bold}>{type.op.value.author}</span>{" "}
          commented{" "}
          <span red_bold={red_bold}>{type.op.value.parent_author}</span>
          's permlink :
          <span red_bold={red_bold}>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.op.value.parent_author}/${type.op.value.parent_permlink}`}
              target="_blank"
            >
              {type.op.value.parent_permlink}
            </a>
          </span>{" "}
        </p>
      );
      break;

    case "transfer_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.from}</span> transfered{" "}
          <span style={blue_bold}>{type.op.value.amount?.amount / 1000}</span>{" "}
          HIVE to <span style={green_bold}>{type.op.value.to}</span>
        </p>
      );
      break;
    case "transfer_to_vesting_operation":
      return (
        <p>
          <span style={blue_bold}>{type.op.value.from}</span> vest{" "}
          <span style={green_bold}> {type.op.value.amount?.amount / 1000}</span>{" "}
          HIVE
        </p>
      );
      break;
    // account withdraw verting_shares (convert to HP) from vesting (show details json)
    case "withdraw_vesting_operation":
      return (
        <p>
          <span style={blue_bold}>{type.op.value.account}</span> withdraw{" "}
          <span style={green_bold}>
            {calculateHivePower(type.op.value.vesting_shares.amount)}
          </span>{" "}
          HP from vesting
        </p>
      );
      break;
    case "limit_order_create_operation":
      return (
        <p>
          <span style={blue_bold}>{type.op.value.owner}</span> wants receive
          amount :{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.op.value.min_to_receive.amount)}
          </span>{" "}
          HIVE in exchange for{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.op.value.amount_to_sell.amount)}
          </span>{" "}
          HBD{" "}
        </p>
      );
      break;
    case "limit_order_cancel_operation":
      return (
        <p>
          <span style={blue_bold}>{type.op.value.owner}</span> cancel order ID :{" "}
          <span style={red_bold}>{type.op.value.orderid}</span>
        </p>
      );
      break;
    case "feed_publish_operation":
      return (
        <p>
          <span style={blue_bold}>{type.op.value.publisher}</span> feed price :
          <span style={red_bold}>
            {" "}
            $
            {Number(type.op.value.exchange_rate.base.amount) /
              Number(type.op.value.exchange_rate.quote.amount)}
          </span>
        </p>
      );
      break;
    case "convert_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.owner}</span> conversion request
          :{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.op.value.amount.amount)} HBD
          </span>{" "}
          to <span style={green_bold}>HIVE</span>
        </p>
      );
      break;
    case "account_create_operation":
      return (
        <p>
          {" "}
          <span style={red_bold}>{type.op.value.creator}</span> create account :{" "}
          <span style={green_bold}>{type.op.value.new_account_name}</span>
        </p>
      );
      break;
    case "account_update_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account}</span> update account
          data
        </p>
      );
      break;
    case "witness_update_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.owner}</span> update witness
        </p>
      );
      break;
    case "account_witness_vote_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account}</span> approve witness{" "}
          <span style={blue_bold}>{type.op.value.witness}</span>
        </p>
      );
      break;
    case "account_witness_proxy_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account}</span> set{" "}
          <span style={blue_bold}>{type.op.value.proxy}</span> as proxy
        </p>
      );
      break;
    case "pow_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.worker_account}</span> found a
          pow
        </p>
      );
      break;
    case "custom_operation":
      return (
        <p>
          {" "}
          <span style={red_bold}>{type.op.value.required_auths}</span> custom
          operation{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "report_over_production_operation":
      return <p> report over production </p>;
      break;
    case "delete_comment_operation":
      return (
        <p>
          {" "}
          <span style={red_bold}>{type.op.value.author}</span> deleted comment
          permlink :{" "}
          <span>
            {" "}
            <a
              style={link_text}
              href={`https://hive.blog/@${type.op.value.author}/${type.op.value.permlink}`}
              target="_blank"
            >
              {type.op.value.permlink}
            </a>
          </span>
        </p>
      );
      break;
    case "custom_json_operation":
      return (
        <p>
          <span style={red_bold}>
            {!type.op.value.required_posting_auths[0]
              ? type.op.value.required_auths[0]
              : type.op.value.required_posting_auths[0]}
          </span>{" "}
          custom operation
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "comment_options_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.author}</span> max payout :{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.max_accepted_payout.amount)}
          </span>{" "}
          ,{" "}
          <span style={blue_bold}>
            {(type.op.value.percent_hbd / 100).toFixed(2)} %
          </span>
          , allow votes :{" "}
          <span style={boolean}>
            {JSON.stringify(type.op.value?.allow_votes)}
          </span>
          , allow curation rewards :{" "}
          <span style={boolean}>
            {JSON.stringify(type.op.value?.allow_curation_rewards)}
          </span>
        </p>
      );
      break;
    case "set_withdraw_vesting_route_operation":
      return (
        <p>
          From <span style={red_bold}>{type.op.value.from_account}</span> to{" "}
          <span style={green_bold}>{type.op.value.to_account}</span> , percent :{" "}
          <span style={blue_bold}>{type.op.value.percent}</span>, auto vest :{" "}
          <span style={boolean}>{JSON.stringify(type.op.value.auto_vest)}</span>{" "}
          ,{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "limit_order_create2_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.owner}</span> limit order create
          2{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "claim_account_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.creator}</span> claim account{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "create_claimed_account_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.creator}</span> claimed new
          account{" "}
          <span style={blue_bold}>{type.op.value.new_account_name}</span>{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "request_account_recovery_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account_to_recover}</span>{" "}
          requested{" "}
          <span style={green_bold}>{type.op.value.recovery_account}</span> for
          account recovery{" "}
        </p>
      );
      break;
    case "recover_account_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account_to_recover}</span>{" "}
          recover account{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "change_recovery_account_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account_to_recover}</span>{" "}
          change recovery account to new account :{" "}
          <span style={blue_bold}>{type.op.value.new_recovery_account}</span>{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "escrow_transfer_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.from}</span> escrow transfer to{" "}
          : <span style={blue_bold}>{type.op.value.to}</span> , agent :{" "}
          <span style={green_bold}>{type.op.value.agent}</span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "escrow_dispute_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.from}</span> escrow dispute to :{" "}
          <span style={blue_bold}>{type.op.value.to}</span> , agent :{" "}
          <span style={green_bold}>{type.op.value.agent}</span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "escrow_release_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.from}</span> escrow release to :{" "}
          <span style={blue_bold}>{type.op.value.to}</span> , agent :{" "}
          <span style={green_bold}>{type.op.value.agent}</span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "pow2_operation":
      return (
        <p>
          <span style={red_bold}>
            {" "}
            {type.op.value.work.value.input.worker_account}
          </span>{" "}
          found a pow
          <button
            onClick={() => setShowJson(!showJson)}
            style={show_details_button}
          >
            Show details
          </button>
        </p>
      );
      break;

    case "escrow_approve_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.from}</span> escrow approve
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "transfer_to_savings_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value?.from}</span> transfer to
          savings :{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.op.value.amount.amount)} HBD
          </span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "transfer_from_savings_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value?.from}</span> transfer from
          savings :{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.op.value.amount.amount)} HBD
          </span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "cancel_transfer_from_savings_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.from}</span> cancel transfer
          from savings
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "custom_binary_operation":
      return (
        <p>
          custom binary{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "decline_voting_rights_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account}</span> decline voting
          rights{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "reset_account_operation":
      return <p>reset account</p>;
      break;
    case "set_reset_account_operation":
      return <p>set reset account</p>;
      break;
    case "claim_reward_balance_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account}</span> claim reward :{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.op.value.reward_hive.amount)} HIVE
          </span>
          ,{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.reward_hbd.amount)} HBD
          </span>
          ,{" "}
          <span style={red_bold}>
            {calculateHivePower(type.op.value.reward_vests.amount)} HP
          </span>
          {/* <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span> */}
        </p>
      );
      break;
    case "delegate_vesting_shares_operation":
      return (
        <p>
          Delegator <span style={red_bold}>{type.op.value.delegator}</span>,
          delegate{" "}
          <span style={green_bold}>
            {calculateHivePower(type.op.value.vesting_shares.amount)} HP
          </span>{" "}
          to <span style={blue_bold}>{type.op.value.delegatee}</span>
        </p>
      );
      break;
    case "account_create_with_delegation_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.creator}</span> create account{" "}
          <span style={blue_bold}>{type.op.value.new_account_name}</span> {""}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "witness_set_properties_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.owner}</span> witness set
          properties
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "account_update2_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account}</span> account update2
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "create_proposal_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.creator}</span> create proposal
          subject : <span style={blue_bold}>{type.op.value.subject}</span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "update_proposal_votes_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.voter}</span> update proposal
          votes
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "remove_proposal_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.proposal_owner}</span> remove
          proposal
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "update_proposal_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.creator}</span> update proposal
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "collateralized_convert_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.owner}</span> collateralized
          convert amount :{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.op.value.amount.amount)} HIVE
          </span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "recurrent_transfer_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.from}</span> recurrent transfer
          to <span style={blue_bold}>{type.op.value.to}</span>, amount :{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.op.value.amount.amount)} HBD
          </span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "fill_convert_request_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.owner}</span> fill convert
          request, amount in :
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.amount_in.amount)} HBD
          </span>{" "}
          , amount out:{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.amount_out.amount)} HIVE
          </span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "author_reward_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.author}</span> author reward :
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.hbd_payout.amount)} HBD
          </span>{" "}
          , amount out:{" "}
          <span style={green_bold}>
            {calculateHivePower(type.op.value.vesting_payout.amount)} HP
          </span>{" "}
          for{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.op.value.author}/${type.op.value.permlink}`}
              target="_blank"
            >
              {type.op.value.permlink}
            </a>
          </span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "curation_reward_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.curator}</span> curation reward{" "}
          <span style={green_bold}>
            {calculateHivePower(type.op.value.reward.amount)} HP
          </span>{" "}
          , comment author :{" "}
          <span style={green_bold}>{type.op.value.comment_author}</span> ,
          comment permlink:{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.op.value.comment_author}/${type.op.value.comment_permlink}`}
              target="_blank"
            >
              {type.op.value.comment_permlink}
            </a>
          </span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "comment_reward_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.author}</span> comment reward{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.payout.amount)} HBD
          </span>{" "}
          permlink:{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.op.value.author}/${type.op.value.permlink}`}
              target="_blank"
            >
              {type.op.value.permlink}
            </a>
          </span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "liquidity_reward_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.owner}</span> liquidity reward{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.payout.amount)} HIVE
          </span>{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "interest_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.owner}</span> collect{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.interest.amount)} HBD
          </span>{" "}
          interest
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "fill_vesting_withdraw_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.from_account}</span> withdraw{" "}
          <span style={green_bold}>
            {calculateHivePower(type.op.value.withdrawn.amount)} HP
          </span>{" "}
          as{" "}
          <span style={blue_bold}>
            {type.op.value.to_account === type.op.value.from_account
              ? `${calculate_hive_hbd(type.op.value.deposited.amount)} HIVE`
              : `${calculateHivePower(type.op.value.deposited.amount)} HP to ${
                  type.op.value.to_account
                }`}
          </span>{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "fill_order_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.current_owner}</span> fill
          order, open owner{" "}
          <span style={green_bold}>{type.op.value.open_owner}</span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "shutdown_witness_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.owner}</span> shutdown witness
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "fill_transfer_from_savings_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.from}</span> fill transfer from
          savings{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.op.value.amount.amount)} HBD
          </span>
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "hardfork_operation":
      return (
        <p>
          Hardfork ID: <span style={red_bold}>{type.op.value.hardfork_id}</span>
        </p>
      );
      break;

    case "comment_payout_update_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.author}</span> comment payout
          update{" "}
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "return_vesting_delegation_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.account}</span> return of{" "}
          <span style={blue_bold}>
            {calculateHivePower(type.op.value.vesting_shares.amount)} HP
          </span>{" "}
          delegation
          <span>
            <button
              onClick={() => setShowJson(!showJson)}
              style={show_details_button}
            >
              Show details
            </button>
          </span>
        </p>
      );
      break;
    case "comment_benefactor_reward_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.benefactor}</span> comment
          benefactor reward :{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.hbd_payout.amount)} HBD
          </span>{" "}
          and{" "}
          <span style={green_bold}>
            {calculateHivePower(type.op.value.vesting_payout.amount)} HP
          </span>{" "}
          for{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.op.value.author}/${type.op.value.permlink}`}
              target="_blank"
            >
              {type.op.value.permlink}
            </a>
          </span>
        </p>
      );
      break;
    case "producer_reward_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.producer}</span> producer reward
          :{" "}
          <span style={green_bold}>
            {calculateHivePower(type.op.value.vesting_shares.amount)} HP
          </span>{" "}
        </p>
      );
      break;
    case "clear_null_account_balance_operation":
      return (
        <p>
          Clear null account balance, total cleared:{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.op.value.total_cleared[0].amount)} HIVE{" "}
          </span>
          ,{" "}
          <span style={blue_bold}>
            {calculate_vests(type.op.value.total_cleared[1].amount)} VESTS{" "}
          </span>
          ,{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.total_cleared[2].amount)} HBD{" "}
          </span>
        </p>
      );
      break;
    case "proposal_pay_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.receiver}</span> receive{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.op.value.payment.amount)} HIVE{" "}
          </span>{" "}
          proposal funding
        </p>
      );
      break;
    case "sps_fund_operation":
      return (
        <p>
          {" "}
          <span style={red_bold}>{type.op.value.fund_account}</span> additional
          fuds{" "}
          <span style={red_bold}>
            {calculate_hive_hbd(type.op.value.additional_funds.amount)} HBD
          </span>
        </p>
      );
      break;
    case "hardfork_hive_operation":
      return (
        <p>
          {" "}
          <span style={red_bold}>{type.op.value.account}</span> hardfork hive{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.op.value, null, 2)}
            </pre>
          </span>
        </p>
      );
      break;
    case "hardfork_hive_restore_operation":
      return (
        <p>
          {" "}
          <span style={red_bold}>{type.op.value.account}</span> hardfork hive
          restore{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.op.value, null, 2)}
            </pre>
          </span>
        </p>
      );
      break;
    case "delayed_voting_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.voter}</span> delayer voting
        </p>
      );
      break;
    case "consolidate_treasury_balance_operation":
      return (
        <p>
          consolidate treasury balance{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.op.value, null, 2)}
            </pre>
          </span>
        </p>
      );
      break;
    case "effective_comment_vote_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.voter}</span> effective comment
          vote{" "}
          <span>
            <pre style={{ color: "#37e8ff" }}>
              {JSON.stringify(type.op.value, null, 2)}
            </pre>
          </span>
        </p>
      );
      break;
    case "ineffective_delete_comment_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.author}</span> ineffective
          delete comment permlink :{" "}
          <span>
            <a
              style={link_text}
              href={`https://hive.blog/@${type.op.value.author}/${type.op.value.permlink}`}
              target="_blank"
            >
              {type.op.value.permlink}
            </a>
          </span>
        </p>
      );
      break;
    case "sps_convert_operation":
      return (
        <p>
          <span style={red_bold}>{type.op.value.fund_account}</span> amount in{" "}
          <span style={blue_bold}>
            {calculate_hive_hbd(type.op.value.hive_amount_in.amount)} HIVE
          </span>
          , amount out{" "}
          <span style={green_bold}>
            {calculate_hive_hbd(type.op.value.hbd_amount_out.amount)} HBD
          </span>
        </p>
      );
      break;
    case "expired_account_notification_operation":
      return <p>Expired account notification</p>;
      break;
    case "changed_recovery_account_operation":
      return (
        <p>
          {" "}
          <span style={red_bold}>{type.op.value.account}</span> change recovery
          account , old account :{" "}
          <span style={blue_bold}>{type.op.value.old_recovery_account}</span>,
          new account :{" "}
          <span style={blue_bold}>{type.op.value.new_recovery_account}</span>
        </p>
      );
      break;
    case "transfer_to_vesting_completed_operation":
      return (
        <>
          <p>
            {" "}
            <span style={red_bold}>{type.op.value.from_account}</span> transfer
            to vesting completed.
          </p>
          <p>
            Hive vested :{" "}
            <span style={blue_bold}>
              {calculate_hive_hbd(type.op.value.hive_vested.amount)} HIVE
            </span>
          </p>
          <p>
            Vesting shares received :{" "}
            <span style={blue_bold}>
              {calculate_vests(type.op.value.vesting_shares_received.amount)}{" "}
              VESTS
            </span>
          </p>
        </>
      );
      break;
    case "pow_reward_operation":
      return (
        <>
          <p>
            <span style={red_bold}>{type.op.value.worker}</span> pow reward{" "}
            <span style={blue_bold}>
              {" "}
              {calculate_hive_hbd(type.op.value.reward.amount)} HIVE
            </span>
          </p>
        </>
      );
      break;
    case "vesting_shares_split_operation":
      return (
        <>
          <p>
            <span style={red_bold}>{type.op.value.owner}</span> vesting shares
            split{" "}
          </p>
          <p>
            Vesting shares before split :{" "}
            <span style={blue_bold}>
              {calculate_vests(
                type.op.value.vesting_shares_before_split.amount
              )}{" "}
              VESTS
            </span>
          </p>
          <p>
            Vesting shares after split :{" "}
            <span style={blue_bold}>
              {calculate_vests(type.op.value.vesting_shares_after_split.amount)}{" "}
              VESTS
            </span>
          </p>
        </>
      );
      break;
    // NO CREATOR VALUE
    case "account_created_operation":
      return (
        <>
          <p>
            Created new account name{" "}
            <span style={red_bold}>{type.op.value.new_account_name}</span>
          </p>
        </>
      );
      break;

    case "fill_collateralized_convert_request_operation":
      return (
        <>
          <p>
            <span style={red_bold}>{type.op.value.owner}</span> fill
            collateralized convert request
          </p>
          <p>
            Amount in:{" "}
            <span style={blue_bold}>
              {calculate_hive_hbd(type.op.value.amount_in.amount)} HIVE
            </span>
          </p>
          <p>
            Amount out:{" "}
            <span style={blue_bold}>
              {calculate_hive_hbd(type.op.value.amount_out.amount)} HBD
            </span>
          </p>

          <p>
            Excess collateral:{" "}
            <span style={blue_bold}>
              {calculate_hive_hbd(type.op.value.excess_collateral.amount)} HIVE
            </span>
          </p>
        </>
      );
      break;
    case "system_warning_operation":
      return (
        <>
          <p>
            System warning message : <br></br>
            <span style={red_bold}>{type.op.value.message}</span>
          </p>
        </>
      );
      break;
    case "fill_recurrent_transfer_operation":
      return (
        <>
          <p>
            <span style={red_bold}>{type.op.value.from}</span> fill recurrent
            transfer to <span style={blue_bold}>{type.op.value.to}</span>
          </p>
          <p>
            Amount :{" "}
            <span style={red_bold}>
              {calculate_hive_hbd(type.op.value.amount.amount)} HIVE
            </span>
          </p>
        </>
      );
      break;
    case "failed_recurrent_transfer_operation":
      return (
        <>
          <p>
            <span style={red_bold}>{type.op.value.from}</span> failed recurrent
            transfer to <span style={blue_bold}>{type.op.value.to}</span>
          </p>
          <p>
            Amount :{" "}
            <span style={red_bold}>
              {calculate_hive_hbd(type.op.value.amount.amount)} HIVE
            </span>
          </p>
        </>
      );
      break;
    case "limit_order_cancelled_operation":
      return (
        <>
          <p>
            <span style={red_bold}>{type.op.value.seller}</span> limit order
            cancelled
          </p>
          <p>
            Amount back :{" "}
            <span style={red_bold}>
              {calculate_hive_hbd(type.op.value.amount_back.amount)} HIVE
            </span>
          </p>
        </>
      );
      break;
    default:
      return "waiting";
  }
}
