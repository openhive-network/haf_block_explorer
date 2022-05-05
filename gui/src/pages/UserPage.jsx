import React, { useContext, useState, useEffect } from "react";
import { UserProfileContext } from "../contexts/userProfileContext";
import { userPagination } from "../functions";
import FilteredOps from "../components/user/FilteredOps";
import Ops from "../components/user/Ops";
import {
  Container,
  Col,
  Row,
  // Button,
  // Pagination,
  Dropdown,
  Toast,
  Modal,
  Form,
  ProgressBar,
} from "react-bootstrap";
import { Button, Pagination } from "@mui/material";
import "./userPage.css";
import TrxTable from "../components/tables/TrxTable";
import UserProfileCard from "../components/user/UserProfileCard";
import UserInfoModal from "../components/user/UserInfoModal";
import { TranasctionContext } from "../contexts/transactionContext";
import { Link } from "react-router-dom";
import HighlightedJSON from "../components/HighlightedJSON";
import MultiSelectFilters from "../components/MultiSelectFilters";

export default function User_Page({ user, setTitle }) {
  const {
    user_profile_data,
    setUser_profile_data,
    set_acc_history_limit,
    acc_history_limit,
    op_types,
    op_filters,
    set_op_filters,
  } = useContext(UserProfileContext);
  const { setTransactionId } = useContext(TranasctionContext);
  // setTitle(`HAF | User | ${user}`);

  const max_trx_nr = user_profile_data?.[0]?.operation_id;
  const [pagination_start, set_pagination_start] = useState(0);
  const trx_count =
    pagination_start === 0 ? pagination_start + max_trx_nr : pagination_start;

  pagination_start === 0 && localStorage.setItem("trx_count_max", max_trx_nr);
  const get_max_trx_num = localStorage.getItem("trx_count_max");
  function handleNextPage() {
    set_pagination_start(trx_count - acc_history_limit);
  }

  function handlePrevPage() {
    set_pagination_start(trx_count + acc_history_limit);
  }
  function handleLastPage() {
    set_pagination_start(acc_history_limit);
  }

  function handleFirstPage() {
    set_pagination_start(Number(get_max_trx_num));
  }
  useEffect(() => {
    if (pagination_start !== 0) {
      userPagination(
        user,
        pagination_start,
        setUser_profile_data,
        acc_history_limit,
        op_filters
      );
    }
  }, [pagination_start, setUser_profile_data, acc_history_limit, op_filters]);

  //Transactions per page
  const countTransPerPage = ["10", "25", "50", "100", "500", "1000"];
  const [countIndex, setCountIndex] = useState();
  const handleCheckbox = (e) => {
    set_acc_history_limit(() => Number(e.target.name));
    setCountIndex(countTransPerPage.indexOf(e.target.name));
  };
  // Operation  filters

  const [show_filters, set_show_filters] = useState(false);
  const [filered_op_names, set_filtered_op_names] = useState([]);
  const [showUserModal, setShowUserModal] = useState(true);
  const [filters_length, set_filters_length] = useState(op_filters.length);
  const [filters_length_names, set_filters_length_names] = useState(
    filered_op_names.length
  );

  const check_op_type = user_profile_data?.map((history) => history.op.type);
  const set_op = [...new Set(check_op_type)];
  const count_same = {};
  check_op_type.forEach((e) => (count_same[e] = (count_same[e] || 0) + 1));

  const count_filtered_ops = filered_op_names.map((k) => count_same[k]);
  const filtered_ops_sum = count_filtered_ops.reduce((a, b) => a + b, 0);
  // console.log(filtered_ops_sum);
  // useEffect(() => {
  //   if (user !== "") {
  //     axios({
  //       method: "post",
  //       url: "http://192.168.5.118:3002/rpc/get_acc_op_types",
  //       headers: { "Content-Type": "application/json" },
  //       data: {
  //         _account: user,
  //       },
  //     }).then((res) => set_operations(res.data));
  //   }
  // }, [user]);

  // console.log(op_types.map((o) => o[1]));
  const opName = op_types?.map((o) => o[1]);
  const opId = op_types?.map((o) => o[0]);
  const opVirtual = op_types.map((o) => o[2]);
  // let opObj = {};
  // opName?.forEach((name) => opObj[name[opId]]);
  // console.log(opName);
  // console.log(op_filters);

  const handleCheck = (e, i) => {
    if (e.target.checked === true) {
      set_op_filters((prev) => [...prev, opId[i]]);
      set_filters_length(filters_length + 1);
      set_filtered_op_names((prev) => [...prev, opName[i]]);
      set_filters_length_names(filters_length_names + 1);
    }
    if (e.target.checked === false) {
      set_filters_length(filters_length - 1);
      set_filters_length_names(filters_length_names - 1);
      const index = op_filters.indexOf(opId[i]);
      index === 0 ? op_filters.shift() : op_filters.splice(index, index);
      const index_names = filered_op_names.indexOf(opName[i]);
      index === 0
        ? filered_op_names.shift()
        : filered_op_names.splice(index_names, index_names);
    }
  };

  // console.log(user_profile_data);

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
          {/* <div> */}
          {/* <Row hidden={show_filters} className="filters">
              <Row className="d-flex justify-content-center">
                <Col className="filters__header text-center" xs={5}>
                  <h3>Filters</h3>
                </Col>
              </Row>
              <Col xs={2} className="filters__operation-count">
                <p>Operations count per page</p>
                {countTransPerPage.map((nr, i) => {
                  return (
                    <div key={i} className="m-1">
                      <input
                        type="checkbox"
                        name={nr}
                        checked={
                          countIndex !== undefined
                            ? countIndex === i
                            : nr == user_profile_data?.length
                        }
                        onChange={(e) => handleCheckbox(e)}
                      />
                      <label htmlFor={nr}>{nr}</label>
                    </div>
                  );
                })}
              </Col>
              <Col xs={3} className="filters__operation">
                <p>Filter Operations</p>
                {opName?.map((o, i) => {
                  // console.log(opId[i]);
                  return (
                    <div key={i} className="m-1">
                      <input
                        type="checkbox"
                        name={o}
                        onChange={(e) => handleCheck(e, i)}
                      />
                      <label htmlFor={o}>{o}</label>
                    </div>
                  );
                })}
              </Col>
            </Row> */}
          {/* </div> */}
          {/* <div
            style={{ display: "flex", justifyContent: "center" }}
            className="filters_btn"
          >
            <Button>Open</Button>
          </div> */}

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
              <Row
                style={{ margin: "20px 5px 20px 0" }}
                className="d-flex justify-content-end align-items-right"
              >
                <Button onClick={() => set_show_filters(!show_filters)}>
                  Modal
                </Button>
                <MultiSelectFilters
                  show_filters={show_filters}
                  set_show_filters={set_show_filters}
                />
                {/* <Button
                  style={{ width: "200px" }}
                  variant="contained"
                  color="secondary"
                  onClick={() => set_show_filters(!show_filters)}
                >
                  Filters
                </Button> */}
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
