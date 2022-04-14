import React, { useContext, useState, useEffect } from "react";
import { ApiContext } from "../context/apiContext";
import { userPagination } from "../functions";
import FilteredOps from "../components/userOperartions/FilteredOps";
import Ops from "../components/userOperartions/Ops";
import { Container, Col, Row } from "react-bootstrap";
import { operations } from "../operations";

// TODO : CHECK FILTERS, Ops LENGTH,Cards design

export default function User_Page({ user, setTitle }) {
  const {
    user_profile_data,
    setUser_profile_data,
    set_acc_history_limit,
    acc_history_limit,
  } = useContext(ApiContext);
  setTitle(`HAF | User | ${user}`);

  const max_trx_nr = user_profile_data?.[0]?.[0];
  const [pagination_start, set_pagination_start] = useState(0);
  const trx_count =
    pagination_start === 0 ? pagination_start + max_trx_nr : pagination_start;

  function handleNextPage() {
    set_pagination_start(trx_count - acc_history_limit);
  }

  function handlePrevPage() {
    set_pagination_start(trx_count + acc_history_limit);
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
  }, [pagination_start]);

  //Transactions per page
  const countTransPerPage = ["10", "25", "50", "100", "500", "1000"];
  const [countIndex, setCountIndex] = useState();
  const handleCheckbox = (e) => {
    set_acc_history_limit(Number(e.target.name));
    setCountIndex(countTransPerPage.indexOf(e.target.name));
  };
  // Operation type filters

  const [active_op_filters, set_active_op_filters] = useState([]);
  const [filters_len, set_filters_len] = useState(active_op_filters.length);
  const handleOperationFilters = (e) => {
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

  const check_op_type = user_profile_data?.map((history) => history[1].op.type);
  const set_op = [...new Set(check_op_type)];

  return (
    <Container>
      <Row>
        <h1>This is personal page of {user}</h1>
      </Row>
      <Row>
        <div className="d-flex flex-column justify-content-center align-items-center ">
          <div className="nav-pages mb-3">
            <button onClick={handlePrevPage}>Prev Page</button>
            <button onClick={handleNextPage}>Next page</button>
          </div>

          <div className="labels mb-3 d-flex">
            {countTransPerPage.map((nr, i) => {
              return (
                <div key={i} className="m-1">
                  <input
                    type="checkbox"
                    name={nr}
                    checked={countIndex === i}
                    onChange={(e) => handleCheckbox(e)}
                  />
                  <label htmlFor={nr}>{nr}</label>
                </div>
              );
            })}
          </div>
          <p>Showing operations per page : {user_profile_data?.length}</p>
          <div>
            <p>Filter Operations</p>
            {operations?.map((o, i) => {
              return (
                <div
                  key={i}
                  className="m-1"
                  style={
                    set_op.includes(o) === true
                      ? { display: "block" }
                      : { display: "none" }
                  }
                >
                  <input
                    disabled={!set_op.includes(o)}
                    type="checkbox"
                    name={o}
                    onChange={(e) => handleOperationFilters(e)}
                  />
                  <label htmlFor={o}>{o}</label>
                </div>
              );
            })}
          </div>
        </div>
      </Row>

      <Row>
        <Col
          style={{
            height: "800px",
            overflow: "auto",
          }}
          xs={8}
        >
          {filters_len === 0 ? (
            <Ops user_profile_data={user_profile_data} />
          ) : (
            <FilteredOps
              user_profile_data={user_profile_data}
              active_op_filters={active_op_filters}
            />
          )}
        </Col>
        <Col xs={4}>Col 4</Col>
      </Row>
    </Container>
  );
}
