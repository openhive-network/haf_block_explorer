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

export const tidyNumber = (x) => {
  if (x) {
    var parts = x.toString().split(".");
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return parts.join(".");
  } else {
    return null;
  }
};
export const calc_reward_fund = (reward_fund) => {
  const result = Number(reward_fund?.reward_balance?.amount) / 1000;
  return result.toFixed(0);
};
export const calc_feed_price = (feed_price) => {
  const result =
    Number(feed_price?.base?.amount) / Number(feed_price?.quote?.amount);
  return result;
};

export const calc_current_supply = (head_block) => {
  const result = Number(head_block?.current_supply?.amount) / 1000;
  return result.toFixed(0);
};
export const calc_current_supply_hbd = (head_block) => {
  const result = Number(head_block?.current_hbd_supply?.amount) / 1000;
  return result.toFixed(0);
};
export const calc_virtual_supply = (head_block) => {
  const result = Number(head_block?.virtual_supply?.amount) / 1000;
  return result.toFixed(0);
};
export const modify_obj_key = (key) => {
  const remove_underscore = key.split("_").join(" ");
  const first_upper_letter =
    remove_underscore.slice(0, 1).toUpperCase() + remove_underscore.slice(1);
  return first_upper_letter;
};
export const calc_reward_fund_to_dol = (reward_fund, feed_price) => {
  const result =
    Number(calc_reward_fund(reward_fund)) * Number(calc_feed_price(feed_price));
  return result.toFixed(0);
};
export const calc_obj_numbers = (key, head_block) => {
  return tidyNumber(Number(head_block[key]?.amount).toFixed(3) / 1000);
};
export const modify_obj_hbd = (key, head_block) => {
  return Number(head_block[key]?.amount).toFixed(3);
};
export const modify_obj_number = (key, head_block) => {
  return head_block[key] !== 0
    ? tidyNumber(Number(head_block[key]))
    : Number(head_block[key]);
};
export const modify_obj_date = (key, head_block) => {
  return head_block[key]?.split("T").join(" ");
};

export const effectiveVests = (user_info) => {
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
};
export const downvotePower = (user_info) => {
  return (
    (user_info?.downvote_manabar?.current_mana /
      ((effectiveVests() / 4) * 1e4)) *
    100
  );
};
export const downvotePowerPct = (user_info) => {
  var pct = (downvotePower(user_info) / 100).toFixed(2);
  if (pct > 100) {
    return (pct = 100.0);
  } else {
    return pct;
  }
};

export const votePower = (user_info) => {
  var secondsago =
    (new Date() - new Date(user_info?.last_vote_time + "Z")) / 1000;
  var vpow = user_info?.voting_power + (10000 * secondsago) / 432000;
  return Math.min(vpow / 10000000).toFixed(2);
  // return Math.min(vpow / 100, 100).toFixed(2);
};

export const calcResourseCredits = (resource_credits) => {
  const res =
    (parseInt(resource_credits?.rc_manabar?.current_mana) /
      parseInt(resource_credits?.max_rc)) *
    100;
  return res.toFixed(2);
};

export const vestsToHive = (vests, vesting_shares, vesting_fund) => {
  const res = (vests / vesting_shares) * vesting_fund * 1000;
  return res.toFixed(3);
};

export const timeDelta = (timestamp, moment) => {
  var now = moment.utc();
  var stamp = moment.utc(timestamp);
  var diff = stamp.diff(now, "minutes");
  return moment.duration(diff, "minutes").humanize(true);
};

export const resourceBudgetComments = (resource_credits) => {
  if (resource_credits?.rc_manabar !== undefined) {
    var cost = 1175937456;
    var available = resource_credits?.rc_manabar?.current_mana / cost;
    if (available >= 1000000) {
      return "1M+";
    } else {
      return available.toFixed(0);
    }
  } else {
    return null;
  }
};

export const resourceBudgetVotes = (resource_credits) => {
  if (resource_credits?.rc_manabar !== undefined) {
    var cost = 109514642;
    var available = resource_credits?.rc_manabar?.current_mana / cost;
    if (available >= 1000000) {
      return "1M+";
    } else {
      return available.toFixed(0);
    }
  } else {
    return null;
  }
};

export const resourceBudgetTransfers = (resource_credits) => {
  if (resource_credits?.rc_manabar !== undefined) {
    var cost = 487237759;
    var available = resource_credits?.rc_manabar?.current_mana / cost;
    if (available >= 1000000) {
      return "1M+";
    } else {
      return available.toFixed(0);
    }
  } else {
    return null;
  }
};

export const resourceBudgetClaimAccounts = (resource_credits) => {
  if (resource_credits?.rc_manabar !== undefined) {
    var cost = 8541343515163;
    var available = resource_credits?.rc_manabar?.current_mana / cost;
    if (available >= 1000000) {
      return "1M+";
    } else {
      return available.toFixed(0);
    }
  } else {
    return null;
  }
};

export const calculateReputation = (reputation) => {
  if (reputation === null || reputation === 0) return reputation;
  let neg = reputation < 0;
  let rep = String(reputation);
  rep = neg ? rep.substring(1) : rep;
  let v = Math.log10((rep > 0 ? rep : -rep) - 10) - 9;
  v = neg ? -v : v;
  return parseInt(v * 9 + 25);
};
