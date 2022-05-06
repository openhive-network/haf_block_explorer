import React, { useContext, useState, useEffect } from "react";
import { UserProfileContext } from "../contexts/userProfileContext";
import { Container, Col, Row, Toast } from "react-bootstrap";
import { Button, Pagination } from "@mui/material";
import ArrowForwardIosIcon from "@mui/icons-material/ArrowForwardIos";
import ArrowBackIosNewIcon from "@mui/icons-material/ArrowBackIosNew";
import "./userPage.css";
import UserProfileCard from "../components/user/UserProfileCard";
import UserInfoModal from "../components/user/UserInfoModal";
import { Link } from "react-router-dom";
import HighlightedJSON from "../components/HighlightedJSON";
import MultiSelectFilters from "../components/MultiSelectFilters";

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
  } = useContext(UserProfileContext);
  // const { setTransactionId } = useContext(TranasctionContext);
  // setTitle(`HAF | User | ${user}`);

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
  const countTransPerPage = ["10", "25", "50", "100", "500", "1000"];
  // Operation  filters

  const [show_filters, set_show_filters] = useState(false);
  const [filered_op_names, set_filtered_op_names] = useState([]);
  const [showUserModal, setShowUserModal] = useState(true);
  // const [filters_length, set_filters_length] = useState(op_filters.length);
  // const [filters_length_names, set_filters_length_names] = useState(
  //   filered_op_names.length
  // );

  const check_op_type = user_profile_data?.map((history) => history.op.type);
  // const set_op = [...new Set(check_op_type)];
  const count_same = {};
  check_op_type.forEach((e) => (count_same[e] = (count_same[e] || 0) + 1));

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

  return (
    <>
      {user_profile_data.length !== 0 ? (
        <Container fluid>
          <div className="op_count">
            <p>
              Showing op_types per page :
              {filtered_ops_sum === 0
                ? user_profile_data?.length
                : filtered_ops_sum}
            </p>
          </div>

          <Row className="d-flex mt-5">
            <Col sm={12} md={3}>
              <UserProfileCard
                setShowUserModal={setShowUserModal}
                user={user}
              />
            </Col>
            <UserInfoModal
              user={user}
              showUserModal={showUserModal}
              setShowUserModal={setShowUserModal}
            />
            <Col sm={12} md={8}>
              <Row style={{ textAlign: "center", margin: "10px 0 10px 0" }}>
                <h1>Operations</h1>
              </Row>
              <Row>
                <Col className="d-flex justify-content-end">
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
                </Col>
              </Row>
              <Row>
                <Col className="d-flex justify-content-center">
                  {op_filters.length === 0 ? (
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
                      <Button onClick={handleNextPage}>
                        <ArrowForwardIosIcon />
                      </Button>
                    </>
                  )}
                </Col>
              </Row>

              <Row>
                {user_profile_data?.map((profile, i) => {
                  const type = profile.op.type.replaceAll("_", " ");
                  const link_to_trx = (
                    <Link
                      style={{ color: "#000", textDecoration: "none" }}
                      to={`/transaction/${profile.trx_id}`}
                    >
                      {profile.operation_id}
                    </Link>
                  );
                  const link_to_block = (
                    <Link
                      style={{
                        color: "#000",
                        textDecoration: "none",
                      }}
                      to={`/block/${profile.block}`}
                    >
                      {profile.block}
                    </Link>
                  );

                  return (
                    <Col key={profile.operation_id} sm={12}>
                      <Toast
                        className="d-inline-block m-1 w-100"
                        bg="secondary"
                        key={i}
                      >
                        <Toast.Header closeButton={false}>
                          <img
                            src="holder.js/20x20?text=%20"
                            className="rounded me-2"
                            alt=""
                          />
                          <strong className="me-auto">
                            <p style={{ margin: "0" }}>
                              ID{" "}
                              {profile.trx_id !== null
                                ? link_to_trx
                                : profile.operation_id}
                            </p>
                            <p style={{ margin: "0" }}>Block {link_to_block}</p>
                          </strong>
                          <strong className="me-auto">
                            <p
                              style={{
                                fontSize: "20px",
                                textTransform: "capitalize",
                              }}
                            >
                              {type}
                            </p>
                          </strong>

                          <small>{profile.timestamp} </small>
                        </Toast.Header>
                        <Toast.Body className="text-white">
                          {/* {user}{" "} */}
                          {profile.op.type === "transfer_operation" ? (
                            <p>
                              from : {profile.op.value.from}, to :{" "}
                              {profile.op.value.to}
                            </p>
                          ) : (
                            ""
                          )}
                          <HighlightedJSON json={profile} />
                          {/* {profile.op.type === "vote_operation" ? (
                            <p>
                              Voter :{" "}
                              <span>
                                <Link
                                  style={{
                                    fontSize: "16px",
                                    color: "red",
                                    fontWeight: "bold",
                                    textDecoration: "none",
                                  }}
                                  to={`/user/${profile.op.value.voter}`}
                                >
                                  {profile.op.value.voter}
                                </Link>
                              </span>{" "}
                              upvoted user's :{" "}
                              <span>
                                <Link
                                  style={{
                                    fontSize: "16px",
                                    color: "red",
                                    fontWeight: "bold",
                                    textDecoration: "none",
                                  }}
                                  to={`/user/${profile.op.value.author}`}
                                >
                                  {profile.op.value.author}
                                </Link>
                              </span>{" "}
                              post :{" "}
                              <span>
                                <Link
                                  style={{
                                    fontSize: "16px",
                                    color: "red",
                                    fontWeight: "bold",
                                    textDecoration: "none",
                                  }}
                                  to={`https://www.hiveblocks.com/steemfest/@${profile.op.value.author}/${profile.op.value.permlink}`}
                                >
                                  {profile.op.value.permlink}
                                </Link>
                              </span>
                            </p>
                          ) : (
                            ""
                          )} */}
                        </Toast.Body>
                      </Toast>
                    </Col>
                  );
                })}
              </Row>

              {/* <TrxTable
                set_show_filters={set_show_filters}
                show_filters={show_filters}
                active_op_filters={filered_op_names}
                next={handleNextPage}
                prev={handlePrevPage}
                first={handleFirstPage}
                last={handleLastPage}
                acc_history_limit={acc_history_limit}
              /> */}
            </Col>
          </Row>
        </Container>
      ) : (
        <div className="d-flex justify-content-center">
          <h1>Please Wait</h1>
        </div>
      )}
    </>
  );
}
