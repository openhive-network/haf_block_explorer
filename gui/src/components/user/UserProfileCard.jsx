import React from "react";
import { Button, ProgressBar } from "react-bootstrap";
// import { UserProfileContext } from "../../contexts/userProfileContext";

export default function UserProfileCard({ setShowUserModal, user }) {
  // const { user_info } = useContext(UserProfileContext);
  const profile_picture = `https://images.hive.blog/u/${user}/avatar`;
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
      <div className="user-currency-amount justify-content-center">
        <ul
          style={{
            padding: "0",
            display: "flex",
            listStyle: "none",
            justifyContent: "space-around",
          }}
        >
          <li>
            HBD : <span>0.00</span>
          </li>
          <li>
            HIVE : <span>0.00</span>
          </li>
          <li>
            HP: <span>0.00</span>
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
          <p style={{ margin: "0" }}>100%</p>
          <ProgressBar
            variant="danger"
            style={{ margin: "10px 0 10px 0" }}
            animated
            now={100}
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
          <p style={{ margin: "0" }}>100%</p>
          <ProgressBar
            variant="danger"
            style={{ margin: "10px 0 10px 0" }}
            animated
            now={100}
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
          <p style={{ margin: "0" }}>100%</p>
          <ProgressBar
            variant="danger"
            style={{ margin: "10px 0 10px 0" }}
            animated
            now={100}
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
          onClick={() => setShowUserModal(false)}
          style={{ width: "70%", color: "white", fontSize: "20px" }}
          variant="danger"
        >
          More info
        </Button>
      </div>
    </div>
  );
}
