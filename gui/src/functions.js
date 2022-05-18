import axios from "axios";

//User profile history pagination #2

export const userPagination = (
  userProfile,
  startPagintation,
  setUser_profile_data,
  limit,
  filter
) => {
  if (userProfile !== "") {
    axios({
      method: "post",
      url: "http://192.168.5.118:3002/rpc/get_ops_by_account",
      headers: { "Content-Type": "application/json" },
      data: {
        _account: userProfile,
        _start: startPagintation,
        _limit: limit,
        _filter: filter,
      },
    }).then((res) => setUser_profile_data(res.data));
  }
};

export const calculate_hive_hbd = (value) => {
  const res = Number(value) / 1000;
  return res.toFixed(2);
};

export const calculate_vests = (value) => {
  const res = Number(value) / 1000000;
  return res.toFixed(2);
};

export const calculateHivePower = (
  account_vests,
  vesting_fund,
  vesting_shares
) => {
  const vest_sum = vesting_fund * (Number(account_vests) / vesting_shares);
  const hive_power = vest_sum / 1000;
  return hive_power.toFixed(2);
};

// export const effectiveVests=()=>
//   if (user_info !== undefined && user_info !== null) {
//     return (
//       parseInt(user_info.vesting_shares) +
//       parseInt(user_info.received_vesting_shares) -
//       parseInt(user_info.delegated_vesting_shares) -
//       parseInt(user_info.vesting_withdraw_rate)
//     );
//   } else {
//     return null;
//   }

// export const downvotePower=()=>

//     (user_info?.downvote_manabar.current_mana /
//       ((effectiveVests() / 4) * 1e4)) *
//     100

// export const downvotePowerPct=()=>
//   var pct = (downvotePower() / 100).toFixed(2);
//   if (pct > 100) {
//     return (pct = 100.0);
//   } else {
//     return pct;
//   }

// export const votePower=()=>
//   var secondsago =
//     (new Date() - new Date(user_info?.last_vote_time + "Z")) / 1000;
//   var vpow = user_info?.voting_power + (10000 * secondsago) / 432000;
//   return Math.min(vpow / 100, 100).toFixed(2);

// export const calcResourseCredits=()=>
//   const res =
//     (parseInt(resource_credits?.rc_manabar.current_mana) /
//       parseInt(resource_credits?.max_rc)) *
//     100;
//   return res.toFixed(2);

// export const vestsToHive=(v=>ets) {
//   const res = (vests / vesting_shares) * vesting_fund * 1000;
//   return res.toFixed(3);
// }

export const tidyNumber = (x) => {
  if (x) {
    var parts = x.toString().split(".");
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return parts.join(".");
  } else {
    return null;
  }
};

// export const timeDelta=(t=>iestamp) {
//   var now = moment.utc();
//   var stamp = moment.utc(timestamp);
//   var diff = stamp.diff(now, "minutes");
//   return moment.duration(diff, "minutes").humanize(true);
// }
// export const resourceBudgetComments=()=>
//   if (resource_credits.rc_manabar !== undefined) {
//     var cost = 1175937456;
//     if (costs !== null) {
//       cost = costs.comment;
//     }
//     var available = resource_credits.rc_manabar.current_mana / cost;
//     if (available >= 1000000) {
//       return "1M+";
//     } else {
//       return tidyNumber(available.toFixed(0));
//     }
//   } else {
//     return null;
//   }
// }
// export const resourceBudgetVotes=()=>
//   if (resource_credits.rc_manabar !== undefined) {
//     var cost = 109514642;
//     if (costs !== null) {
//       cost = costs.vote;
//     }
//     var available = resource_credits.rc_manabar.current_mana / cost;
//     if (available >= 1000000) {
//       return "1M+";
//     } else {
//       return tidyNumber(available.toFixed(0));
//     }
//   } else {
//     return null;
//   }
// }
// export const resourceBudgetTransfers=()=>
//   if (resource_credits.rc_manabar !== undefined) {
//     var cost = 487237759;
//     if (costs !== null) {
//       cost = costs.transfer;
//     }
//     var available = resource_credits.rc_manabar.current_mana / cost;
//     if (available >= 1000000) {
//       return "1M+";
//     } else {
//       return tidyNumber(available.toFixed(0));
//     }
//   } else {
//     return null;
//   }
// }

// export const resourceBudgetClaimAccounts=()=>
//   if (resource_credits.rc_manabar !== undefined) {
//     var cost = 8541343515163;
//     if (costs !== null) {
//       cost = costs.claim_account;
//     }
//     var available = resource_credits.rc_manabar.current_mana / cost;
//     if (available >= 1000000) {
//       return "1M+";
//     } else {
//       return tidyNumber(available.toFixed(0));
//     }
//   } else {
//     return null;
//   }
// }
