import React, { useContext, useState } from "react";
import { UserProfileContext } from "../../contexts/userProfileContext";
import { WitnessContext } from "../../contexts/witnessContext";
import { Container, Col, Row } from "react-bootstrap";
import { Button, ButtonGroup } from "@mui/material";
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
import { useEffect } from "react";
import usePrevious from "../../components/customHooks/usePrevious";

export default function User_Page({ user }) {
  document.title = `HAF | User ${user}`;
  const {
    user_profile_data,
    acc_history_limit,
    op_filters,
    set_pagination,
    user_info,
    startDateState,
    endDateState,
    set_op_filters,
    setStartDateState,
    setEndDateState,
    userDataLoading,
  } = useContext(UserProfileContext);
  const { witnessData } = useContext(WitnessContext);
  const [show_filters, set_show_filters] = useState(false);
  const [prevNextPage, setPrevNextPage] = useState([]);

  const user_witness = witnessData?.filter((w) => w.witness === user);
  const max_trx_nr = user_profile_data?.[0]?.acc_operation_id;

  const last_trx_on_page =
    user_profile_data?.[acc_history_limit - 1]?.acc_operation_id;
  const [get_last_trx_on_page, set_get_last_trx_on_page] = useState(0);
  const [get_first_trx_on_page, set_get_first_trx_on_page] = useState(0);
  const prevUser = usePrevious(user);

  useEffect(() => {
    if (prevUser === user) {
      set_get_last_trx_on_page(last_trx_on_page);
      set_get_first_trx_on_page(max_trx_nr);
    } else {
      set_pagination(-1);
      set_op_filters([]);
    }
  }, [prevUser, user, last_trx_on_page, max_trx_nr]);

  return (
    <>
      {!user_profile_data || !user_info ? (
        <Loader />
      ) : (
        <Container className={styles.user_page} fluid>
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
              <MultiSelectFilters
                show_filters={show_filters}
                set_show_filters={set_show_filters}
              />
              <Row className="my-3">
                <Col className="d-flex justify-content-between">
                  <div>
                    <p className={styles.operationsCount}>
                      Operations : {user_profile_data?.length}
                    </p>
                  </div>

                  <ButtonGroup
                    sx={{
                      maxHeight: "40px",
                    }}
                    size="small"
                    disableElevation
                    variant="contained"
                    color="secondary"
                  >
                    <Button
                      onClick={() =>
                        handlePrevPage(
                          set_pagination,
                          prevNextPage,
                          setPrevNextPage
                        )
                      }
                    >
                      <ArrowBackIosNewIcon />
                    </Button>
                    <Button
                      onClick={() =>
                        handleNextPage(
                          set_pagination,
                          get_last_trx_on_page,
                          get_first_trx_on_page,
                          setPrevNextPage
                        )
                      }
                    >
                      <ArrowForwardIosIcon />
                    </Button>
                  </ButtonGroup>

                  {op_filters.length === 0 &&
                  startDateState === null &&
                  endDateState === null ? (
                    <>
                      <Button
                        variant="contained"
                        color="secondary"
                        onClick={() => set_show_filters(!show_filters)}
                      >
                        Filters
                      </Button>
                    </>
                  ) : (
                    <ButtonGroup>
                      <Button
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
                            set_op_filters,
                            set_pagination
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
                    </ButtonGroup>
                  )}
                </Col>
              </Row>
              {user_profile_data.length === 0
                ? "No operations found"
                : user_profile_data.map((profile) => (
                    <Row key={profile.operation_id}>
                      <Col>
                        <OpCard block={profile} full_trx={profile} />
                      </Col>
                    </Row>
                  ))}
            </Col>
          </Row>
        </Container>
      )}
    </>
  );
}
