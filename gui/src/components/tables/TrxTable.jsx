import React, { useState } from "react";
import Paper from "@mui/material/Paper";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import TableHead from "@mui/material/TableHead";
import TablePagination from "@mui/material/TablePagination";
import TableRow from "@mui/material/TableRow";
import Button from "@mui/material/Button";
import { ApiContext } from "../../context/apiContext";
// import Pop from "../components/userOperartions/Pop";
import { Row, Col, Offcanvas } from "react-bootstrap";
// import { Button, Offcanvas } from "react-bootstrap";
import { Link } from "react-router-dom";

export default function TrxTable({
  next,
  prev,
  first,
  last,
  active_op_filters,
  acc_history_limit,
  set_show_filters,
  show_filters,
}) {
  const [page, setPage] = React.useState(0);
  const [rowsPerPage, setRowsPerPage] = React.useState(10);
  const { user_profile_data } = React.useContext(ApiContext);
  const [show, setShow] = useState(false);

  // const handleClose = () => setShow(false);
  const handleShow = () => setShow(!show);
  // console.log(op_types.map((o, i) => o[0][i] == active_op_filters));
  // console.log(active_op_filters);
  const columns = [
    { id: "name", label: "Op Number", minWidth: 170 },
    // { id: "code", label: "Op Block", minWidth: 170 },
    {
      id: "op_block",
      label: "Block Number",
      minWidth: 170,
      align: "left",
    },
    {
      id: "op_type",
      label: "Op Type",
      minWidth: 170,
      align: "left",
      format: (value) => value.toLocaleString("en-US"),
    },
    // {
    //   id: "op_value",
    //   label: "Op Value",
    //   minWidth: 170,
    //   align: "left",
    // },
    {
      id: "info",
      label: "More Details",
      minWidth: 170,
      align: "left",
      format: (value) => value.toLocaleString("en-US"),
    },
  ];

  function createData(
    name,
    op_block,
    op_type,
    // op_value,
    op_details,
    op_trx_id
  ) {
    return { name, op_block, op_type, op_details, op_trx_id };
  }

  const op_number = user_profile_data?.map((history) => history.operation_id);
  const op_block = user_profile_data?.map((history) => history.block);
  const op_trx_id = user_profile_data?.map((history) => history.trx_id);
  const op_type = user_profile_data?.map((history) => history.op.type);
  // const op_value = user_profile_data?.map((history) => history[1].op.value.id);
  const more_details = <Button onClick={handleShow}>show</Button>;
  let rows = [];
  for (let i = 0; i < user_profile_data?.length; i++) {
    if (user_profile_data.length !== 0) {
      rows.push(
        createData(
          op_number[i],
          op_block[i],
          op_type[i],
          // op_value[i],
          more_details,
          op_trx_id[i]
        )
      );
    }
  }

  // const handleChangePage = (event, newPage) => {
  //   setPage(newPage);
  // };

  // const handleChangeRowsPerPage = (event) => {
  //   setRowsPerPage(+event.target.value);
  //   setPage(0);
  // };

  return (
    <Row>
      <Col>
        <Paper>
          <TableContainer>
            <div className="d-flex">
              <div className="pagination-btn">
                <Button onClick={first}>First</Button>
                <Button onClick={prev}>Prev</Button>
                <Button onClick={next}>Next</Button>
                <Button onClick={last}>Last</Button>
              </div>
              <div style={{ marginLeft: "auto" }} className="filters-btn">
                <Button
                  variant="contained"
                  color="secondary"
                  onClick={() => set_show_filters(!show_filters)}
                >
                  Filters
                </Button>
              </div>
            </div>
            <Table stickyHeader aria-label="sticky table">
              <TableHead>
                <TableRow>
                  {columns.map((column, i) => (
                    <TableCell
                      key={column.id}
                      align={column.align}
                      style={{ minWidth: column.minWidth }}
                    >
                      {column.label}
                    </TableCell>
                  ))}
                </TableRow>
              </TableHead>
              <TableBody>
                {rows
                  .slice(page * rowsPerPage, page * rowsPerPage + rowsPerPage)
                  .map((row, i) => {
                    return (
                      <TableRow
                        hidden={
                          newOp === false && active_op_filters.length !== 0
                        }
                        hover
                        // role="checkbox"
                        key={i}
                      >
                        {columns.map((column, i) => {
                          const value = row[column.id];
                          const route = () => {
                            if (column.id === "op_block") {
                              return <a href={`/block/${value}`}>{value}</a>;
                            }
                            if (
                              column.id === "name" &&
                              row.op_trx_id !==
                                "0000000000000000000000000000000000000000"
                            ) {
                              return (
                                <a href={`/transaction/${row.op_trx_id}`}>
                                  {value}
                                </a>
                              );
                            }
                            if (value === undefined) {
                              return "- - - - - - ";
                            } else {
                              return value;
                            }
                          };
                          return (
                            <TableCell key={i} align={column.align}>
                              {/* {value === undefined ? "- - - - - - -" : value} */}
                              {route()}
                            </TableCell>
                          );
                        })}
                      </TableRow>
                    );
                  })}
              </TableBody>
            </Table>
          </TableContainer>

          {/* <div style={{ display: "flex", justifyContent: "space-around" }}>
            <TablePagination
              rowsPerPageOptions={[10, 25, 100, 1000]}
              component="div"
              count={rows.length}
              rowsPerPage={rowsPerPage}
              page={page}
              onPageChange={handleChangePage}
              onRowsPerPageChange={handleChangeRowsPerPage}
            />
          </div> */}
        </Paper>
      </Col>
      <div className="userpage__offcanvas" hidden={!show}>
        More Detailed Info about current transaction
      </div>
    </Row>
  );
}
