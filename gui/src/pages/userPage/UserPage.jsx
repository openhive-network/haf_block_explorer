import React, { useContext, useState } from "react";
import { UserProfileContext } from "../../contexts/userProfileContext";
import { WitnessContext } from "../../contexts/witnessContext";
import { Container, Col, Row } from "react-bootstrap";
import { Button, Pagination } from "@mui/material";
import ArrowForwardIosIcon from "@mui/icons-material/ArrowForwardIos";
import ArrowBackIosNewIcon from "@mui/icons-material/ArrowBackIosNew";
import styles from "./userPage.module.css";
import UserProfileCard from "../../components/user/userCard/UserProfileCard";
import UserInfoTable from "../../components/user/userTable/UserInfoTable";
import MultiSelectFilters from "../../components/operations/filters/MultiSelectFilters";
import OpCard from "../../components/operations/operationCard/OpCard";
import Loader from "../../components/loader/Loader";
import {
  handleNextPage,
  handlePrevPage,
  clearFilters,
} from "../../functions/user_page_func";
import JsonMetaData from "../../components/user/JsonMetaData";
import PostingJsonMetaData from "../../components/user/PostingJsonMetaData";
import Authorities from "../../components/user/Authorities";
import WitnessProps from "../../components/user/WitnessProps";
import WitnessVotes from "../../components/user/WitnessVotes";

export default function User_Page({ user }) {
  document.title = `HAF | User ${user}`;
  const {
    user_profile_data,
    acc_history_limit,
    op_filters,
    set_pagination,
    pagination,
    user_info,
    startDateState,
    endDateState,
    set_op_filters,
    setStartDateState,
    setEndDateState,
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
  const check_op_type = user_profile_data?.map(
    (history) => history.operations.type
  );
  const count_same = {};
  check_op_type?.forEach((e) => (count_same[e] = (count_same[e] || 0) + 1));
  const page_count = Math.ceil(get_max_trx_num / acc_history_limit);
  const [page, setPage] = useState([]);

  return (
    <>
      {user_info === "" ||
      witnessData === null ||
      user_profile_data === null ||
      user_profile_data.length === 0 ? (
        <Loader />
      ) : (
        <Container fluid>
          <Row className="d-flex">
            <Col sm={12} md={5} lg={5} xl={3}>
              <UserProfileCard user={user} />
              <UserInfoTable user_info={user_info} />
              <JsonMetaData user_info={user_info} />
              <PostingJsonMetaData user_info={user_info} />
              <Authorities user_info={user_info} user_witness={user_witness} />
              <WitnessProps user_info={user_info} user_witness={user_witness} />
              <WitnessVotes user_info={user_info} />
            </Col>

            <Col sm={12} md={7} lg={7} xl={9}>
              <Row className="mt-3">
                <Col className="d-flex justify-content-between">
                  <div>
                    <p className={styles.operationsCount}>
                      Operations : {user_profile_data?.length}
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
                  {op_filters.length === 0 &&
                  startDateState === null &&
                  endDateState === null ? (
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
                  ) : (
                    <div>
                      <Button
                        className="m-3"
                        variant="contained"
                        color="warning"
                        onClick={() => set_show_filters(!show_filters)}
                      >
                        Filters (active)
                      </Button>
                      <Button
                        onClick={() =>
                          clearFilters(
                            setEndDateState,
                            setStartDateState,
                            set_op_filters
                          )
                        }
                        variant="contained"
                        color="secondary"
                      >
                        Clear filters
                      </Button>
                      <MultiSelectFilters
                        show_filters={show_filters}
                        set_show_filters={set_show_filters}
                      />
                    </div>
                  )}
                </Col>
              </Row>
              {user_profile_data?.map((profile) => {
                return (
                  <Row key={profile.operation_id}>
                    <Col>
                      <OpCard block={profile} full_trx={profile} />
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
