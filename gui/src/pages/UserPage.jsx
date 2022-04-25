import React, { useContext, useState, useEffect } from "react";
import { ApiContext } from "../context/apiContext";
import { userPagination } from "../functions";
import FilteredOps from "../components/user/FilteredOps";
import Ops from "../components/user/Ops";
import { Container, Col, Row, Button, Pagination } from "react-bootstrap";
import { operations } from "../operations";
import ProgressBar from "react-bootstrap/ProgressBar";
// import Pagination from "react-bootstrap/Pagination";
import "./userPage.css";
// import TimeAgo from "javascript-time-ago";
// import en from "javascript-time-ago/locale/en.json";
// import ReactTimeAgo from "react-time-ago";
import TrxTable from "../components/tables/TrxTable";
import UserProfileCard from "../components/user/UserProfileCard";
import UserInfoModal from "../components/user/UserInfoModal";
import axios from "axios";

// TimeAgo.addDefaultLocale(en);
export default function User_Page({ user, setTitle }) {
  const {
    user_profile_data,
    setUser_profile_data,
    set_acc_history_limit,
    acc_history_limit,
  } = useContext(ApiContext);
  setTitle(`HAF | User | ${user}`);

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
        acc_history_limit
      );
    }
  }, [pagination_start, setUser_profile_data, acc_history_limit]);

  //Transactions per page
  const countTransPerPage = ["10", "25", "50", "100", "500", "1000"];
  const [countIndex, setCountIndex] = useState();
  const handleCheckbox = (e) => {
    set_acc_history_limit(Number(e.target.name));
    setCountIndex(countTransPerPage.indexOf(e.target.name));
  };
  // Operation type filters
  const [filters, setFilters] = useState([]);
  const [active_op_filters, set_active_op_filters] = useState([]);
  const [filters_len, set_filters_len] = useState(active_op_filters.length);
  const handleOperationFilters = (e, index) => {
    if (e.target.checked === true) {
      set_active_op_filters((prev) => [...prev, e.target.name]);
      set_filters_len(filters_len + 1);
    } else if (e.target.checked === false) {
      set_filters_len(filters_len - 1);

      const i = active_op_filters.indexOf(e.target.name);
      i === 0 ? active_op_filters?.shift() : active_op_filters?.splice(i, i);
    }
  };

  // Check if operation type exist and enable/disable filters

  const check_op_type = user_profile_data?.map((history) => history.op.type);
  const set_op = [...new Set(check_op_type)];
  const count_same = {};
  check_op_type.forEach((e) => (count_same[e] = (count_same[e] || 0) + 1));

  const count_filtered_ops = active_op_filters.map((k) => count_same[k]);
  const filtered_ops_sum = count_filtered_ops.reduce((a, b) => a + b, 0);

  const [show_filters, set_show_filters] = useState(true);
  const [showUserModal, setShowUserModal] = useState(true);
  console.log(count_filtered_ops);
  // const timestamp = user_profile_data?.[1]?.[1].timestamp;
  // const now = new Date().toISOString().slice(0, timestamp?.length);
  // console.log(operations.indexOf(active_op_filters));
  return (
    <>
      {user_profile_data.length !== 0 ? (
        <Container fluid>
          <div className="op_count">
            <p>
              Showing operations per page :
              {filtered_ops_sum === 0
                ? user_profile_data?.length
                : filtered_ops_sum}
            </p>
          </div>
          <div>
            <Row hidden={show_filters} className="filters">
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
                {operations?.map((o, i) => {
                  return (
                    <div
                      key={i}
                      className="m-1"
                      // style={
                      //   set_op.includes(o) === true
                      //     ? { display: "block" }
                      //     : { display: "none" }
                      // }
                    >
                      <input
                        // disabled={!set_op.includes(o)}
                        type="checkbox"
                        name={o}
                        onChange={(e) => handleOperationFilters(e, i)}
                      />
                      <label htmlFor={o}>{o}</label>
                    </div>
                  );
                })}
              </Col>
            </Row>
          </div>
          <div
            style={{ display: "flex", justifyContent: "center" }}
            className="filters_btn"
          ></div>

          {/* <div className="pagination mt-3">
            <Col xs={12}>
              <Pagination>
                <Pagination.First
                  disabled={get_max_trx_num == max_trx_nr}
                  onClick={handleFirstPage}
                />
                <Pagination.Prev
                  disabled={get_max_trx_num == max_trx_nr}
                  onClick={handlePrevPage}
                />

                <Pagination.Next
                  disabled={pagination_start === acc_history_limit}
                  onClick={handleNextPage}
                />
                <Pagination.Last
                  disabled={pagination_start === acc_history_limit}
                  onClick={handleLastPage}
                />
              </Pagination>
            </Col>
          </div> */}

          <Row className="d-flex justify-content-center mt-5">
            {/* <Col
              style={{
                height: "70vh",
                overflow: "auto",
              }}
              xs={10}
              aria-live="polite"
              aria-atomic="true"
              className="bg-dark position-relative"
            >
              {filters_len === 0 ? (
                <Ops user_profile_data={user_profile_data} user={user} />
              ) : (
                <FilteredOps
                  user={user}
                  user_profile_data={user_profile_data}
                  active_op_filters={active_op_filters}
                />
              )}
            </Col> */}
            <UserInfoModal
              user={user}
              showUserModal={showUserModal}
              setShowUserModal={setShowUserModal}
            />
            <Col sm={12} md={3}>
              <UserProfileCard
                setShowUserModal={setShowUserModal}
                user={user}
              />
            </Col>
            <Col>
              <TrxTable
                set_show_filters={set_show_filters}
                show_filters={show_filters}
                active_op_filters={active_op_filters}
                next={handleNextPage}
                prev={handlePrevPage}
                first={handleFirstPage}
                last={handleLastPage}
                acc_history_limit={acc_history_limit}
              />
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
