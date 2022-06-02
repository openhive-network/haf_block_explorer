import React, { useContext, useState } from "react";
import { UserProfileContext } from "../contexts/userProfileContext";
import { WitnessContext } from "../contexts/witnessContext";
import { Container, Col, Row } from "react-bootstrap";
import { Button, Pagination } from "@mui/material";
import ArrowForwardIosIcon from "@mui/icons-material/ArrowForwardIos";
import ArrowBackIosNewIcon from "@mui/icons-material/ArrowBackIosNew";
import "./userPage.css";
import UserProfileCard from "../components/user/UserProfileCard";
import UserInfoTable from "../components/user/UserInfoTable";
// import { Link } from "react-router-dom";
import HighlightedJSON from "../components/HighlightedJSON";
import MultiSelectFilters from "../components/MultiSelectFilters";
// import GetOperation from "../operations";
import OpCard from "../components/OpCard";

export default function User_Page({ user, setTitle }) {
  const {
    user_profile_data,
    // setUser_profile_data,
    // set_acc_history_limit,
    acc_history_limit,
    // op_types,
    op_filters,
    // set_op_filters,
    set_pagination,
    pagination,
    // userProfile,
    // resource_credits,
    user_info,
    startDateState,
    endDateState,
  } = useContext(UserProfileContext);
  const { witnessData } = useContext(WitnessContext);
  const user_witness = witnessData?.filter((w) => w.owner === user);
  // console.log(user_info?.witness_votes);
  // console.log(user_witness?.[0].signing_key);
  // const { setTransactionId } = useContext(TranasctionContext);
  // setTitle(`HAF | User | ${user}`);
  // console.log(getOperation("vote_operation"));
  const max_trx_nr = user_profile_data?.[0]?.acc_operation_id;
  const last_trx_on_page =
    user_profile_data?.[acc_history_limit - 1]?.acc_operation_id;

  localStorage.setItem("last_trx_on_page", last_trx_on_page);
  localStorage.setItem("first_trx_on_page", max_trx_nr);
  pagination === -1 && localStorage.setItem("trx_count_max", max_trx_nr);
  const get_max_trx_num = localStorage.getItem("trx_count_max");
  const get_last_trx_on_page = localStorage.getItem("last_trx_on_page");
  const get_first_trx_on_page = localStorage.getItem("first_trx_on_page");

  //Transactions per page
  // const countTransPerPage = ["10", "25", "50", "100", "500", "1000"];
  // Operation  filters
  // const [show_json, set_show_json] = useState(false);
  const [show_filters, set_show_filters] = useState(false);
  const [filered_op_names, set_filtered_op_names] = useState([]);
  const [showUserModal, setShowUserModal] = useState(true);
  // const [filters_length, set_filters_length] = useState(op_filters.length);
  // const [filters_length_names, set_filters_length_names] = useState(
  //   filered_op_names.length
  // );
  // console.log(user_profile_data);
  // console.log(witnessData);

  const check_op_type = user_profile_data?.map(
    (history) => history.operations.type
  );
  // const set_op = [...new Set(check_op_type)];
  const count_same = {};
  check_op_type?.forEach((e) => (count_same[e] = (count_same[e] || 0) + 1));

  const count_filtered_ops = filered_op_names.map((k) => count_same[k]);
  const filtered_ops_sum = count_filtered_ops.reduce((a, b) => a + b, 0);

  const page_count = Math.ceil(get_max_trx_num / acc_history_limit);
  const [page, setPage] = useState([]);
  const handleNextPage = () => {
    set_pagination(get_last_trx_on_page);
    setPage((prev) => [...prev, get_first_trx_on_page]);
  };

  const handlePrevPage = () => {
    setPage(page.slice(0, -1));
    set_pagination(page.pop());
  };

  // const handleClose = () => setShowUserModal(true);
  const handleShow = () => setShowUserModal(false);
  // const meta_data = JSON?.parse(user_info?.json_metadata);
  // console.log(user_info);
  // console.log(...user_info?.owner.key_auths[0]);
  return (
    <>
      {user_info === "" ||
      witnessData === null ||
      user_profile_data === null ? (
        <h1>Loading ...</h1>
      ) : (
        <Container fluid>
          {/* <div className="op_count">
            <p>
              Showing op_types per page :
              {filtered_ops_sum === 0
                ? user_profile_data?.length
                : filtered_ops_sum}
            </p>
          </div> */}

          <Row className="d-flex mt-5">
            <Col sm={12} md={3}>
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
                    // wordWrap: "break-word",
                    // whiteSpace: "pre-wrap",
                    // wordBreak: "break-word",
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

            <Col>
              <Row>
                <Col className="d-flex justify-content-between">
                  <div className="op_count">
                    <p>
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

              <Row>
                {user_profile_data?.map((profile, i) => {
                  return (
                    <Col key={profile.operation_id} sm={12}>
                      <OpCard block={profile} index={i} full_trx={profile} />
                    </Col>
                  );
                })}
              </Row>
            </Col>
          </Row>
        </Container>
      )}
    </>
  );
}
