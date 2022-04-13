import React, { useContext, useState } from "react";
import { ApiContext } from "../context/apiContext";
import { userPagination } from "../functions";

import { Card, Col, Row } from "react-bootstrap";
export default function User_Page({ user, setTitle }) {
  const {
    user_profile_data,
    setUser_profile_data,
    set_acc_history_limit,
    acc_history_limit,
  } = useContext(ApiContext);
  setTitle(`HAF | User | ${user}`);
  // const paging_limit = 100;
  // const [limit, setLimit] = useState(acc_history_limit);
  const max_trx_nr = user_profile_data?.[0]?.[0];

  const [selectPage, setSelectPage] = useState(0);
  // const [prevPage, setPrevPage] = useState(0);
  const trx_count = selectPage === 0 ? selectPage + max_trx_nr : selectPage;
  // const trx_count_prev = prevPage === 0 ? prevPage + max_trx_nr : prevPage;

  function handleselectPage() {
    setSelectPage(trx_count - acc_history_limit);
  }

  function handlePrevPage() {
    setSelectPage(trx_count + acc_history_limit);
  }

  selectPage !== 0 &&
    userPagination(user, selectPage, setUser_profile_data, acc_history_limit);

  //Transactions per page
  const countTransPerPage = ["10", "25", "50", "100", "500", "1000"];
  const [findIndex, setFindIndex] = useState();
  const handleCheckbox = (e) => {
    set_acc_history_limit(Number(e.target.name));
    setFindIndex(countTransPerPage.indexOf(e.target.name));
  };

  return (
    <div>
      <h1>This is personal page of {user}</h1>

      <div className="d-flex flex-column justify-content-center align-items-center ">
        <div className="nav-pages mb-3">
          <button onClick={handlePrevPage}>Prev Page</button>
          <button onClick={handleselectPage}>Next page</button>
        </div>

        <div className="labels mb-3 d-flex">
          {countTransPerPage.map((nr, i) => {
            return (
              <div key={i} className="m-1">
                <input
                  type="checkbox"
                  name={nr}
                  checked={findIndex === i}
                  onChange={(e) => handleCheckbox(e)}
                />
                <label htmlFor={nr}>{nr}</label>
              </div>
            );
          })}
        </div>
        <p>Showing operations per page : {user_profile_data?.length}</p>
      </div>

      {user_profile_data?.map((d) => {
        const userDataJson = JSON.stringify(d, null, 2);
        return (
          <Row key={d[0]} className="justify-content-center">
            <Col xs={6} className="m-2">
              <Card>
                <pre>{userDataJson}</pre>
              </Card>
            </Col>
          </Row>
        );
      })}
    </div>
  );
}
