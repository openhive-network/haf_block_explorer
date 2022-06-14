import React, { useContext, useState } from "react";
import { UserProfileContext } from "../contexts/userProfileContext";
import { WitnessContext } from "../contexts/witnessContext";
import { Container, Col, Row } from "react-bootstrap";
import { Button, Pagination } from "@mui/material";
import ArrowForwardIosIcon from "@mui/icons-material/ArrowForwardIos";
import ArrowBackIosNewIcon from "@mui/icons-material/ArrowBackIosNew";
import "../styles/userPage.css";
import UserProfileCard from "../components/user/UserProfileCard";
import UserInfoTable from "../components/user/UserInfoTable";
import HighlightedJSON from "../components/HighlightedJSON";
import MultiSelectFilters from "../components/operations/filters/MultiSelectFilters";
import OpCard from "../components/operations/OpCard";
import Loader from "../components/loader/Loader";
import { handleNextPage, handlePrevPage } from "../functions/user_page_func";

export default function User_Page({ user, setTitle }) {
  const {
    user_profile_data,
    acc_history_limit,
    op_filters,
    set_pagination,
    pagination,
    user_info,
    startDateState,
    endDateState,
  } = useContext(UserProfileContext);
  const { witnessData } = useContext(WitnessContext);
  const user_witness = witnessData?.filter((w) => w.owner === user);
  const max_trx_nr = user_profile_data?.[0]?.acc_operation_id;
  const last_trx_on_page =
    user_profile_data?.[acc_history_limit - 1]?.acc_operation_id;

  localStorage.setItem("last_trx_on_page", last_trx_on_page);
  localStorage.setItem("first_trx_on_page", max_trx_nr);
  pagination === -1 && localStorage.setItem("trx_count_max", max_trx_nr);
  const get_max_trx_num = localStorage.getItem("trx_count_max");
  const get_last_trx_on_page = localStorage.getItem("last_trx_on_page");
  const get_first_trx_on_page = localStorage.getItem("first_trx_on_page");
  const [show_filters, set_show_filters] = useState(false);
  const [filered_op_names, set_filtered_op_names] = useState([]);
  // const [showUserModal, setShowUserModal] = useState(true);

  const check_op_type = user_profile_data?.map(
    (history) => history.operations.type
  );
  const count_same = {};
  check_op_type?.forEach((e) => (count_same[e] = (count_same[e] || 0) + 1));

  const count_filtered_ops = filered_op_names.map((k) => count_same[k]);
  const filtered_ops_sum = count_filtered_ops.reduce((a, b) => a + b, 0);

  const page_count = Math.ceil(get_max_trx_num / acc_history_limit);
  const [page, setPage] = useState([]);

  const style = {
    color: "#160855",
    fontWeight: "bold",
    fontSize: "18px",
  };
  return (
    <>
      {user_info === "" ||
      witnessData === null ||
      user_profile_data === null ||
      user_profile_data.length === 0 ? (
        <Loader />
      ) : (
        <Container fluid>
          <Row className="d-flex mt-5">
            <Col sm={12} md={5} lg={5} xl={3}>
              <UserProfileCard user={user} />
              <UserInfoTable user_info={user_info} />
              {user_info?.json_metadata ? (
                <div
                  style={{
                    background: "#2C3136",
                    color: "#fff",
                    marginTop: "25px",
                    borderRadius: "10px",
                    padding: "20px",
                    wordWrap: "break-word",
                    whiteSpace: "pre-wrap",
                    wordBreak: "break-word",
                    textAlign: "center",
                  }}
                >
                  <h3>JSON metadata</h3>
                  <pre
                    style={{
                      borderRadius: "10px",
                      background: "#18003fef",
                      wordWrap: "break-word",
                      whiteSpace: "pre-wrap",
                      wordBreak: "break-word",
                      padding: "10px",
                      textAlign: "left",
                    }}
                  >
                    <HighlightedJSON
                      json={JSON.parse(user_info?.json_metadata)}
                    />
                  </pre>
                </div>
              ) : (
                ""
              )}
              {user_info?.posting_json_metadata ? (
                <div
                  style={{
                    background: "#2C3136",
                    color: "#fff",
                    marginTop: "25px",
                    borderRadius: "10px",
                    padding: "20px",
                    wordWrap: "break-word",
                    whiteSpace: "pre-wrap",
                    wordBreak: "break-word",
                    textAlign: "center",
                  }}
                >
                  <h3>Posting JSON metadata</h3>
                  <pre
                    style={{
                      borderRadius: "10px",
                      background: "#18003fef",
                      wordWrap: "break-word",
                      whiteSpace: "pre-wrap",
                      wordBreak: "break-word",
                      padding: "10px",
                      textAlign: "left",
                    }}
                  >
                    <HighlightedJSON
                      json={JSON.parse(user_info?.posting_json_metadata)}
                    />
                  </pre>
                </div>
              ) : (
                ""
              )}
              {user_info?.owner?.key_auths ? (
                <div
                  style={{
                    background: "#2C3136",
                    color: "#fff",
                    marginTop: "25px",
                    borderRadius: "10px",
                    padding: "20px",
                    textAlign: "center",
                  }}
                >
                  <h3>Authorities</h3>
                  {user_witness?.[0]?.signing_key !== undefined ? (
                    <div
                      style={{
                        background: "#18003fef",
                        borderRadius: "10px",
                      }}
                    >
                      <h5>Signinig</h5>
                      <p
                        style={{
                          overflow: "auto",
                          padding: "10px",
                          color: "#d8fd50",
                        }}
                      >
                        {user_witness?.[0]?.signing_key}
                      </p>
                    </div>
                  ) : (
                    ""
                  )}

                  {user_info?.owner.key_auths !== undefined ? (
                    <div
                      style={{
                        background: "#18003fef",
                        borderRadius: "10px",
                      }}
                    >
                      <h5>Owner</h5>
                      <p
                        style={{
                          overflow: "auto",
                          padding: "10px",
                          color: "#d8fd50",
                          margin: "0",
                        }}
                      >
                        {user_info?.owner.key_auths[0][0]}
                      </p>
                      <p>
                        Threshold :{" "}
                        <span style={{ color: "#d8fd50" }}>
                          {user_info?.owner.key_auths[0][1]}
                        </span>
                      </p>
                    </div>
                  ) : (
                    ""
                  )}

                  {user_info?.active.key_auths !== undefined ? (
                    <div
                      style={{
                        background: "#18003fef",
                        borderRadius: "10px",
                      }}
                    >
                      <h5>Active</h5>
                      <p
                        style={{
                          overflow: "auto",
                          padding: "10px",
                          color: "#d8fd50",
                          margin: "0",
                        }}
                      >
                        {user_info?.active.key_auths[0][0]}
                      </p>
                      <p>
                        Threshold :{" "}
                        <span style={{ color: "#d8fd50" }}>
                          {user_info?.active.key_auths[0][1]}
                        </span>
                      </p>
                    </div>
                  ) : (
                    ""
                  )}

                  {user_info?.posting.key_auths !== undefined ? (
                    <div
                      style={{
                        background: "#18003fef",
                        borderRadius: "10px",
                      }}
                    >
                      <h5>Posting</h5>
                      <p
                        style={{
                          overflow: "auto",
                          padding: "10px",
                          color: "#d8fd50",
                          margin: "0",
                        }}
                      >
                        {user_info?.posting.key_auths[0][0]}
                      </p>
                      <p>
                        Threshold :{" "}
                        <span style={{ color: "#d8fd50" }}>
                          {user_info?.posting.key_auths[0][1]}
                        </span>
                      </p>
                      {user_info?.posting.account_auths !== undefined ? (
                        <div
                          style={{
                            textAlign: "left",
                            padding: "10px 20px 10px 10px",
                          }}
                        >
                          <ul style={{ listStyle: "none" }}>
                            {user_info?.posting.account_auths.map((acc) => (
                              <Row>
                                <Col classsName="d-flex justify-content-center">
                                  <li>
                                    <a
                                      style={{ textDecoration: "none" }}
                                      href={`/user/${acc[0]}`}
                                    >
                                      {acc[0]}
                                    </a>
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
                    <div
                      style={{
                        background: "#18003fef",
                        borderRadius: "10px",
                        marginTop: "20px",
                      }}
                    >
                      <h5>Memo</h5>
                      <p
                        style={{
                          overflow: "auto",
                          padding: "10px",
                          color: "#d8fd50",
                          margin: "0",
                        }}
                      >
                        {user_info?.memo_key}
                      </p>
                    </div>
                  ) : (
                    ""
                  )}
                </div>
              ) : (
                ""
              )}
              {user_info?.posting_json_metadata ? (
                <div
                  style={{
                    background: "#2C3136",
                    color: "#fff",
                    marginTop: "25px",
                    borderRadius: "10px",
                    padding: "20px",
                    wordWrap: "break-word",
                    whiteSpace: "pre-wrap",
                    wordBreak: "break-word",
                    textAlign: "center",
                  }}
                >
                  <h3>Witness Properties</h3>
                  <UserInfoTable user_info={user_witness?.[0]} />
                </div>
              ) : (
                ""
              )}
              {user_info?.witness_votes?.length !== 0 ? (
                <div
                  style={{
                    background: "#2C3136",
                    color: "#fff",
                    marginTop: "25px",
                    borderRadius: "10px",
                    padding: "20px",
                    wordWrap: "break-word",
                    whiteSpace: "pre-wrap",
                    wordBreak: "break-word",
                    textAlign: "center",
                  }}
                >
                  <h3>Witness Votes</h3>
                  <ul style={{ listStyle: "none" }}>
                    {user_info?.witness_votes?.map((w, i) => (
                      <li>
                        {i + 1}.{" "}
                        <a
                          style={{ textDecoration: "none" }}
                          href={`/user/${w}`}
                        >
                          {w}
                        </a>
                      </li>
                    ))}
                  </ul>
                </div>
              ) : (
                ""
              )}
            </Col>

            <Col sm={12} md={7} lg={7} xl={9}>
              <Row className="mt-3">
                <Col className="d-flex justify-content-between">
                  <div className="op_count">
                    <p style={style}>
                      Operations :{" "}
                      {filtered_ops_sum === 0
                        ? user_profile_data?.length
                        : filtered_ops_sum}
                    </p>
                  </div>
                  {op_filters.length === 0 &&
                  startDateState === null &&
                  endDateState === null ? (
                    <Pagination
                      onClick={(e) =>
                        set_pagination(
                          get_max_trx_num -
                            (Number(e.target.innerText) - 1) * acc_history_limit
                        )
                      }
                      count={page_count}
                      color="secondary"
                      hidePrevButton
                      hideNextButton
                    />
                  ) : (
                    <>
                      <Button
                        onClick={() =>
                          handlePrevPage(setPage, page, set_pagination)
                        }
                      >
                        <ArrowBackIosNewIcon />
                      </Button>

                      {user_profile_data?.length !== acc_history_limit ? (
                        " "
                      ) : (
                        <Button
                          onClick={() =>
                            handleNextPage(
                              set_pagination,
                              get_last_trx_on_page,
                              setPage,
                              get_first_trx_on_page
                            )
                          }
                        >
                          <ArrowForwardIosIcon />
                        </Button>
                      )}
                    </>
                  )}
                  <div>
                    <Button
                      variant="contained"
                      color="secondary"
                      onClick={() => set_show_filters(!show_filters)}
                    >
                      Filters
                    </Button>
                    <MultiSelectFilters
                      show_filters={show_filters}
                      set_show_filters={set_show_filters}
                    />
                  </div>
                </Col>

                {/* <Col sm={1}>
                  <Button
                    variant="secondary"
                    onClick={() => set_show_filters(!show_filters)}
                  >
                    Filters
                  </Button>
                  <MultiSelectFilters
                    show_filters={show_filters}
                    set_show_filters={set_show_filters}
                  />
                </Col> */}
              </Row>
              {/* <Row>
                <Col className="d-flex justify-content-center">
                  {op_filters.length === 0 &&
                  startDateState === null &&
                  endDateState === null ? (
                    <Pagination
                      onClick={(e) =>
                        set_pagination(
                          get_max_trx_num -
                            (Number(e.target.innerText) - 1) * acc_history_limit
                        )
                      }
                      count={page_count}
                      color="secondary"
                      hidePrevButton
                      hideNextButton
                    />
                  ) : (
                    <>
                      <Button onClick={handlePrevPage}>
                        <ArrowBackIosNewIcon />
                      </Button>

                      {user_profile_data?.length !== acc_history_limit ? (
                        " "
                      ) : (
                        <Button onClick={handleNextPage}>
                          <ArrowForwardIosIcon />
                        </Button>
                      )}
                    </>
                  )}
                </Col>
              </Row> */}

              {user_profile_data?.map((profile, i) => {
                return (
                  <Row>
                    <Col key={profile.operation_id}>
                      <OpCard block={profile} index={i} full_trx={profile} />
                    </Col>
                  </Row>
                );
              })}
            </Col>
          </Row>
        </Container>
      )}
    </>
  );
}
