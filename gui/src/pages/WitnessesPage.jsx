import React, { useContext, useEffect, useState } from "react";
import { styled } from "@mui/material/styles";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell, { tableCellClasses } from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Paper from "@mui/material/Paper";
import { tidyNumber } from "../functions";
import { Container, Row, Col } from "react-bootstrap";
import { WitnessContext } from "../contexts/witnessContext";
import moment from "moment";
import Button from "@mui/material/Button";
import { Link } from "react-router-dom";
export default function DataTable() {
  const { witnessData, setWitnessData } = useContext(WitnessContext);
  const cell_names = [
    "Name",
    "Votes (M)",
    "Voters",
    "Missed",
    "Last_block",
    "APR",
    "Price_feed",
    "Bias",
    "Price_hive",
    "Price_hbd",
    "Feed_age",
    "Ac_fee",
    "Ac_avail",
    "Ac_budget",
    "Ac_decay",
    "Block_size",
    "Version",
  ];
  const [count, setCount] = useState(1);

  const StyledTableCell = styled(TableCell)(({ theme }) => ({
    [`&.${tableCellClasses.head}`]: {
      backgroundColor: theme.palette.common.black,
      color: theme.palette.common.white,
    },
    [`&.${tableCellClasses.body}`]: {
      fontSize: 14,
    },
  }));

  const StyledTableRow = styled(TableRow)(({ theme }) => ({
    "&:nth-of-type(odd)": {
      backgroundColor: theme.palette.action.hover,
    },
    // hide last border
    "&:last-child td, &:last-child th": {
      border: 0,
    },
  }));

  function sortNumber(object_key) {
    if (count % 2 === 0) {
      return witnessData?.sort(
        (a, b) => parseInt(b[object_key]) - parseInt(a[object_key])
      );
    } else {
      return witnessData?.sort(
        (a, b) => parseInt(a[object_key]) - parseInt(b[object_key])
      );
    }
  }
  function sortString(object_key) {
    if (count % 2 === 0) {
      witnessData?.sort((a, b) => (a[object_key] < b[object_key] ? 1 : -1));
    } else {
      witnessData?.sort((a, b) => (a[object_key] > b[object_key] ? 1 : -1));
    }
  }
  function sortNestedObj(object_key) {
    if (count % 2 === 0) {
      return witnessData?.sort(
        (a, b) => Number(b.props[object_key]) - Number(a.props[object_key])
      );
    } else {
      return witnessData?.sort(
        (a, b) => Number(a.props[object_key]) - Number(b.props[object_key])
      );
    }
  }

  const sort = (name) => {
    switch (name) {
      case "Name":
        sortString("owner");
        break;
      case "Votes (M)":
        sortNumber("votes");
        break;
      case "Missed":
        sortNumber("total_missed");
        break;
      case "Last_block":
        sortNumber("last_confirmed_block_num");
        break;
      case "Feed_age":
        sortNumber("last_hbd_exchange_update");
        break;
      case "Price_feed":
        if (count % 2 === 0) {
          return witnessData?.sort(
            (a, b) =>
              Number(b.hbd_exchange_rate.base.split("HBD")[0]) -
              Number(a.hbd_exchange_rate.base.split("HBD")[0])
          );
        } else {
          return witnessData?.sort(
            (a, b) =>
              Number(a.hbd_exchange_rate.base.split("HBD")[0]) -
              Number(b.hbd_exchange_rate.base.split("HBD")[0])
          );
        }
        break;
      case "Ac_budget":
        sortNestedObj("account_subsidy_budget");
        break;
      case "Ac_decay":
        sortNestedObj("account_subsidy_decay");

        break;
      case "Block_size":
        sortNestedObj("maximum_block_size");
        break;
      case "Version":
        sortNumber("hardfork_version_vote");
        break;
      default:
    }
  };

  const click = (name) => {
    setCount(count + 1);
    sort(name);
  };

  return (
    <>
      {witnessData === null ? (
        "Loading ... "
      ) : (
        <Container>
          <Row>
            <Col>
              <TableContainer style={{ height: "800px" }} component={Paper}>
                <Table
                  stickyHeader
                  style={{ maxWidth: "100vw" }}
                  sx={{ minWidth: 700 }}
                  aria-label="customized table"
                >
                  <TableHead>
                    <TableRow>
                      {cell_names.map((name) => (
                        <StyledTableCell>
                          <Button onClick={() => click(name)}>{name}</Button>
                        </StyledTableCell>
                      ))}
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {witnessData.map((witness, i) => {
                      return (
                        <StyledTableRow key={i}>
                          <StyledTableCell component="th" scope="witness">
                            <Link to={`/user/${witness.owner}`}>
                              {witness.owner}
                            </Link>
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {tidyNumber(
                              Math.round(witness.votes / 1000000 / 1000000)
                            )}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {witness.total_missed}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {witness.last_confirmed_block_num}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {witness.hbd_exchange_rate.base.split("HBD")[0]}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {moment(witness.last_hbd_exchange_update).fromNow()}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {witness.props.account_creation_fee}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {witness.props.account_subsidy_budget}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {witness.props.account_subsidy_decay}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {witness.props.maximum_block_size}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="witness">
                            {witness.hardfork_version_vote}
                          </StyledTableCell>
                        </StyledTableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </TableContainer>
            </Col>
          </Row>
        </Container>
      )}
    </>
  );
}
