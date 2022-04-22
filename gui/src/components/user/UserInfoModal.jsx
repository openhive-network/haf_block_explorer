import React, { useContext } from "react";
import { ApiContext } from "../../context/apiContext";
import HighlightedJSON from "../HighlightedJSON";

export default function UserInfoModal({
  showUserModal,
  setShowUserModal,
  user,
}) {
  const center = {
    display: "flex",
    width: "100%",
    justifyContent: "center",
    padding: "15px 0 0 0",
  };

  const { user_info } = useContext(ApiContext);
  const user_info_to_json = JSON.stringify(user_info, null, 2);

  return (
    <div
      onClick={() => setShowUserModal(true)}
      hidden={showUserModal}
      style={{
        zIndex: "3",
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        position: "fixed",
        left: "0",
        top: "0",
        width: "100vw",
        height: "100vh",
        backgroundColor: "rgb(0,0,0)",
        backgroundColor: "rgba(0,0,0,0.4)",
      }}
      className="user-info__modal"
    >
      <div
        style={{
          overflow: "auto",
          wordWrap: "break-word",
          whiteSpace: "pre-wrap",
          width: "50vw",
          height: "80vh",
          borderTop: "5px solid red",
          borderLeft: "5px solid red",
          borderBottom: "5px solid red",
          background: "#fff",
          borderRadius: "30px 0 0 30px",
        }}
        className="modal__content"
      >
        <div
          style={{
            display: "flex",
            width: "100%",
            borderBottom: "5px solid black",
            // height: "70px",
          }}
          className="modal__header"
        >
          <div style={center} className="header__username">
            <p style={{ fontSize: "25px", fontWeight: "bolder" }}>{user}</p>
          </div>
          <button
            onClick={() => setShowUserModal(true)}
            style={{ background: "none", border: "0", marginRight: "10px" }}
            className="modal__btn--close"
          >
            X
          </button>
        </div>
        <div className="modal__main">
          <div style={center} className="main__header">
            <p style={{ fontSize: "25px", fontWeight: "bolder" }}>JSON DATA</p>
          </div>
          <div className="main__data">
            {user_info === undefined ? (
              "Loading Info"
            ) : (
              <HighlightedJSON json={user_info} />
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
