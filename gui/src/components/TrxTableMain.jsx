import * as React from "react";
import Paper from "@mui/material/Paper";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import TableHead from "@mui/material/TableHead";
import TablePagination from "@mui/material/TablePagination";
import TableRow from "@mui/material/TableRow";
import { Link } from "react-router-dom";
import { useContext } from "react";
import { ApiContext } from "../context/apiContext";

export default function TrxTableMain({ block_trans, tr_id }) {
  const [page, setPage] = React.useState(0);
  const [rowsPerPage, setRowsPerPage] = React.useState(10);
  const { userProfile, setUserProfile, setTransactionId } =
    useContext(ApiContext);

  const columns = [
    { id: "name", label: "Username", minWidth: 170 },
    // { id: "code", label: "Op Block", minWidth: 170 },
    {
      id: "population",
      label: "Op Type",
      minWidth: 170,
      align: "left",
      //   format: (value) => value.toLocaleString("en-US"),
    },
    {
      id: "size",
      label: "Op Value",
      minWidth: 170,
      align: "left",
      format: (value) => value.toLocaleString("en-US"),
    },
    {
      id: "info",
      label: "More Details",
      minWidth: 170,
      align: "left",
      format: (value) => value.toLocaleString("en-US"),
    },
  ];

  const user = block_trans?.map(
    (transaction) =>
      (transaction.value?.required_auths?.length === 0
        ? transaction.value?.required_posting_auths
        : transaction.value?.required_auths) ||
      transaction.value.from ||
      transaction.value.voter ||
      transaction.value.delegator ||
      transaction.value.account ||
      transaction.value.author ||
      transaction.value.owner ||
      transaction.value.creator ||
      transaction.value.publisher
  );

  function createData(name, population, size, info) {
    return { name, population, size, info };
  }
  //   const trx_user = ;
  const trx_type = block_trans?.map((history) => history.type);
  const trx_value = block_trans?.map((history) => history.value.id);

  const rows = [];

  for (let i = 0; i < block_trans?.length; i++) {
    if (block_trans.length !== 0) {
      const id = tr_id.filter((single_id, index) => index === i && single_id);

      rows.push(
        createData(
          <div
            onClick={() =>
              setUserProfile(typeof user[i] === "object" ? user[i][0] : user[i])
            }
          >
            <Link to={`user/${user[i]}`}>{user[i]}</Link>
          </div>,
          trx_type[i],
          trx_value[i],
          <Link to={`/transaction/${id}`}>
            <p onClick={() => setTransactionId(id)}>Open transaction</p>
          </Link>
        )
      );
    }
  }

  const handleChangePage = (event, newPage) => {
    setPage(newPage);
  };

  const handleChangeRowsPerPage = (event) => {
    setRowsPerPage(+event.target.value);
    setPage(0);
  };

  return (
    <>
      <Paper style={{ border: "15px solid #FDF6F0", borderRadius: "20px" }}>
        <TableContainer sx={{ maxHeight: 440 }}>
          <Table stickyHeader aria-label="sticky table">
            <TableHead>
              <TableRow>
                {columns.map((column) => (
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
                    <TableRow hover role="checkbox" tabIndex={-1} key={i}>
                      {columns.map((column, i) => {
                        const value = row[column.id];
                        return (
                          <TableCell key={i} align={column.align}>
                            {column.format && typeof value === "number"
                              ? column.format(value)
                              : value}
                          </TableCell>
                        );
                      })}
                    </TableRow>
                  );
                })}
            </TableBody>
          </Table>
        </TableContainer>

        <div style={{ display: "flex", justifyContent: "space-around" }}>
          <TablePagination
            rowsPerPageOptions={[10, 25, 100]}
            component="div"
            count={rows.length}
            rowsPerPage={rowsPerPage}
            page={page}
            onPageChange={handleChangePage}
            onRowsPerPageChange={handleChangeRowsPerPage}
          />
        </div>
      </Paper>
    </>
  );
}
