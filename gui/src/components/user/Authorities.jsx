import React from "react";
import styles from "./userStyles.module.css";
import { Row, Col } from "react-bootstrap";

export default function Authorities({ user_info, user_witness }) {
  return (
    <>
      {user_info?.owner?.key_auths ? (
        <div className={styles.authContainer}>
          <h3>Authorities</h3>

          {user_witness.length ? (
            <div className={styles.authDataContainer}>
              <h5>Signinig</h5>
              <p className={styles.authData}>
                {user_witness?.[0]?.signing_key}
              </p>
            </div>
          ) : (
            ""
          )}

          {user_info?.owner?.key_auths.length ? (
            <div className={styles.authDataContainer}>
              <h5>Owner</h5>
              <p className={styles.authData}>
                {user_info?.owner.key_auths[0][0]}
              </p>
              <p>
                Threshold : <span>{user_info?.owner.key_auths[0][1]}</span>
              </p>
            </div>
          ) : (
            ""
          )}

          {user_info?.active?.key_auths.length ? (
            <div className={styles.authDataContainer}>
              <h5>Active</h5>
              <p className={styles.authData}>
                {user_info?.active.key_auths[0][0]}
              </p>
              <p>
                Threshold : <span>{user_info?.active.key_auths[0][1]}</span>
              </p>
            </div>
          ) : (
            ""
          )}

          {user_info?.posting?.key_auths.length ? (
            <div className={styles.authDataContainer}>
              <h5>Posting</h5>
              <p className={styles.authData}>
                {user_info?.posting.key_auths[0][0]}
              </p>
              <p>
                Threshold : <span>{user_info?.posting.key_auths[0][1]}</span>
              </p>

              {user_info?.posting?.account_auths.length ? (
                <div className={styles.tresholdContainer}>
                  <ul>
                    {user_info?.posting.account_auths.map((acc, i) => (
                      <Row key={i}>
                        <Col className="d-flex justify-content-center">
                          <li>
                            <a href={`/user/${acc[0]}`}>{acc[0]}</a>
                          </li>
                        </Col>
                        <Col className="d-flex justify-content-end">
                          <li> {acc[1]}</li>
                        </Col>
                      </Row>
                    ))}
                  </ul>
                </div>
              ) : (
                ""
              )}
            </div>
          ) : (
            ""
          )}

          {user_info?.memo_key !== undefined ? (
            <div className={styles.authDataContainer}>
              <h5>Memo</h5>
              <p className={styles.authData}>{user_info?.memo_key}</p>
            </div>
          ) : (
            ""
          )}
        </div>
      ) : (
        ""
      )}
    </>
  );
}
