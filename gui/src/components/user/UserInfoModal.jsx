import React, { useContext } from "react";
import { UserProfileContext } from "../../contexts/userProfileContext";
import HighlightedJSON from "../HighlightedJSON";
import { Row, Col, Button } from "react-bootstrap";
import { Modal, Typography, Box } from "@mui/material";

export default function UserInfoModal({ showUserModal, handleClose, user }) {
  // const center = {
  //   display: "flex",
  //   width: "100%",
  //   justifyContent: "center",
  //   padding: "15px 0 0 0",
  // };

  const { user_info } = useContext(UserProfileContext);
  const user_info_to_json = JSON.stringify(user_info, null, 2);
  const isObject = (obj) => obj != null && obj.constructor.name === "Object";
  function getKeys(obj, keepObjKeys, skipArrays, keys = [], scope = []) {
    if (Array.isArray(obj)) {
      if (!skipArrays) scope.push("[" + obj.length + "]");
      obj.forEach(
        (o) => getKeys(o, keepObjKeys, skipArrays, keys, scope),
        keys
      );
    } else if (isObject(obj)) {
      Object.keys(obj).forEach((k) => {
        if ((!Array.isArray(obj[k]) && !isObject(obj[k])) || keepObjKeys) {
          let path = scope.concat(k).join(".").replace(/\.\[/g, "[");
          if (!keys.includes(path)) keys.push(path);
        }
        getKeys(obj[k], keepObjKeys, skipArrays, keys, scope.concat(k));
      }, keys);
    }
    return keys;
  }
  const keys = getKeys(user_info, true, true);
  console.log(user_info);
  // console.log(user_info[getKeys(user_info, true, true)]);
  let values = [];
  for (let i = 0; i < keys.length; i++) {
    values.push(user_info[keys[i]]);
  }
  const style = {
    width: "50%",
    overflow: "auto",
    height: "800px",
  };

  // const {
  //   id,
  //   name,
  //   proxy,
  //   previous_owner_update,
  //   last_owner_update,
  //   last_account_update,
  //   created,
  //   mined,
  //   recovery_account,
  //   last_account_recovery,
  //   reset_account,
  //   comment_count,
  //   lifetime_vote_count,
  //   post_count,
  //   can_vote,
  //   voting_power,
  //   balance,
  //   savings_balance,
  //   hbd_balance,
  //   hbd_seconds,
  //   hbd_seconds_last_update,
  //   hbd_last_interest_payment,
  //   savings_hbd_balance,
  //   savings_hbd_seconds,
  //   savings_hbd_seconds_last_update,
  //   savings_hbd_last_interest_payment,
  //   savings_withdraw_requests,
  //   reward_hbd_balance,
  //   reward_hive_balance,
  //   reward_vesting_balance,
  //   reward_vesting_hive,
  //   vesting_shares,
  //   delegated_vesting_shares,
  //   received_vesting_shares,
  //   vesting_withdraw_rate,
  //   post_voting_power,
  //   next_vesting_withdrawal,
  //   withdrawn,
  //   to_withdraw,
  //   withdraw_routes,
  //   pending_transfers,
  //   curation_rewards,
  //   posting_rewards,
  //   proxied_vsf_votes,
  //   witnesses_voted_for,
  //   last_post,
  //   last_root_post,
  //   last_vote_time,
  //   post_bandwidth,
  //   pending_claimed_accounts,
  //   governance_vote_expiration_ts,
  //   delayed_votes,
  //   open_recurrent_transfers,
  //   vesting_balance,
  //   reputation,
  //   transfer_history,
  //   market_history,
  //   post_history,
  //   vote_history,
  //   other_history,
  //   tags_usage,
  //   guest_bloggers,
  // } = user_info;
  return (
    // <Modal show={showUserModal} onHide={handleClose}>
    //   <Modal.Header closeButton>
    //     <Modal.Title>Modal heading</Modal.Title>
    //   </Modal.Header>
    //   <Modal.Body>
    //     <Row>
    //       <Col xs={2}>
    //         {keys?.map((key) => {
    //           const hasDot = key.match(/\.(?=[A-Za-z])/g);

    //           return (
    //             <>
    //               {hasDot === null && (
    //                 <ul>
    //                   <li>{JSON.stringify(key)}</li>
    //                 </ul>
    //               )}
    //             </>
    //           );
    //         })}
    //       </Col>

    //       <Col xs={2}>
    //         {values?.map((value) => {
    //           console.log(value);
    //           return (
    //             <>
    //               {value != "undefined" && (
    //                 <ul>
    //                   <li>{JSON.stringify(value)}</li>
    //                 </ul>
    //               )}
    //             </>
    //           );
    //         })}
    //       </Col>
    //     </Row>
    //   </Modal.Body>
    //   <Modal.Footer>
    //     <Button variant="secondary" onClick={handleClose}>
    //       Close
    //     </Button>
    //     <Button variant="primary" onClick={handleClose}>
    //       Save Changes
    //     </Button>
    //   </Modal.Footer>
    // </Modal>
    <div style={style} hidden={showUserModal}>
      <Row>
        <Button onClick={handleClose}>Close</Button>
      </Row>
      <Row>
        <Col xs={2}></Col>

        <Col xs={2}>
          {values?.map((value) => {
            return (
              <>
                {value != "undefined" && (
                  <ul>
                    <li>{JSON.stringify(value)}</li>
                  </ul>
                )}
              </>
            );
          })}
        </Col>
      </Row>
    </div>
    // <div
    //   onClick={() => setShowUserModal(true)}
    //   hidden={showUserModal}
    //   style={{
    //     zIndex: "3",
    //     display: "flex",
    //     justifyContent: "center",
    //     alignItems: "center",
    //     position: "fixed",
    //     left: "0",
    //     top: "0",
    //     width: "100vw",
    //     height: "100vh",
    //     backgroundColor: "rgb(0,0,0)",
    //     backgroundColor: "rgba(0,0,0,0.4)",
    //   }}
    //   className="user-info__modal"
    // >
    //   <div
    //     style={{
    //       overflow: "auto",
    //       wordWrap: "break-word",
    //       whiteSpace: "pre-wrap",
    //       width: "50vw",
    //       height: "80vh",
    //       borderTop: "5px solid red",
    //       borderLeft: "5px solid red",
    //       borderBottom: "5px solid red",
    //       background: "#091B4B",
    //       borderRadius: "30px 0 0 30px",
    //     }}
    //     className="modal__content"
    //   >
    //     <div
    //       style={{
    //         display: "flex",
    //         width: "100%",
    //         borderBottom: "5px solid black",
    //         // height: "70px",
    //       }}
    //       className="modal__header"
    //     >
    //       <div style={center} className="header__username">
    //         <p style={{ fontSize: "25px", fontWeight: "bolder" }}>{user}</p>
    //       </div>
    //       <button
    //         onClick={() => setShowUserModal(true)}
    //         style={{ background: "none", border: "0", marginRight: "10px" }}
    //         className="modal__btn--close"
    //       >
    //         X
    //       </button>
    //     </div>
    //     <div className="modal__main">
    //       <div style={center} className="main__header">
    //         <p style={{ fontSize: "25px", fontWeight: "bolder" }}>JSON DATA</p>
    //       </div>
    //       <div className="main__data">
    //         {user_info === undefined ? (
    //           "Loading Info"
    //         ) : (
    //           <HighlightedJSON json={user_info} />
    //         )}
    //       </div>
    //     </div>
    //   </div>
    // </div>
  );
}
