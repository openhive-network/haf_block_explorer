import React, { useContext, useState } from "react";
import { styled } from "@mui/material/styles";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell, { tableCellClasses } from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Paper from "@mui/material/Paper";
import { tidyNumber } from "../functions";

import { WitnessContext } from "../contexts/witnessContext";
import moment from "moment";

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

// function createData(
//   name,
//   votes,
//   voters,
//   missed,
//   last_block,
//   APR,
//   price_feed,
//   bias,
//   price_hive,
//   price_hbd,
//   feed_age,
//   ac_fee,
//   ac_avail,
//   ac_budget,
//   ac_decay,
//   block_size,
//   version
// ) {
//   return {
//     name,
//     votes,
//     voters,
//     missed,
//     last_block,
//     APR,
//     price_feed,
//     bias,
//     price_hive,
//     price_hbd,
//     feed_age,
//     ac_fee,
//     ac_avail,
//     ac_budget,
//     ac_decay,
//     block_size,
//     version,
//   };
// }

// const rows = [
//   createData("Frozen yoghurt", 159, 6.0, 24, 4.0),
//   createData("Ice cream sandwich", 237, 9.0, 37, 4.3),
//   createData("Eclair", 262, 16.0, 24, 6.0),
//   createData("Cupcake", 305, 3.7, 67, 4.3),
//   createData("Gingerbread", 356, 16.0, 49, 3.9),
// ];
const cell_names = [
  "Rank",
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

export default function CustomizedTables() {
  const { witnessData } = useContext(WitnessContext);

  return (
    <>
      {witnessData === null ? (
        "Loading ... "
      ) : (
        <TableContainer component={Paper}>
          <Table sx={{ minWidth: 700 }} aria-label="customized table">
            <TableHead>
              <TableRow>
                {cell_names.map((name) => (
                  <StyledTableCell>{name}</StyledTableCell>
                ))}
              </TableRow>
            </TableHead>
            <TableBody>
              {witnessData.map((witness, i) => (
                <StyledTableRow key={i}>
                  <StyledTableCell component="th" scope="witness">
                    {i}
                  </StyledTableCell>
                  <StyledTableCell component="th" scope="witness">
                    {witness.owner}
                  </StyledTableCell>
                  <StyledTableCell component="th" scope="witness">
                    {tidyNumber(Math.round(witness.votes / 1000000 / 1000000))}
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
                    {witness.hbd_exchange_rate.base}
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
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      )}
    </>
  );
}

// import React, { useContext, useState } from "react";
// import { WitnessContext } from "../contexts/witnessContext";
// import { Row, Col, Container, Table } from "react-bootstrap";

// export default function Witnesses_Page({ setTitle }) {
//   // setTitle("HAF | Witnesess");
//   const { witnessData } = useContext(WitnessContext);
//   let nr = [];
//   for (let i = 1; i <= witnessData?.length; i++) {
//     nr.push(i);
//   }
//   console.log(witnessData);
//   return (
//     <div>
//       <Container>
//         <Row>
//           <Col>
//             <Table striped bordered hover variant="light" responsive>
//               <thead>
//                 <tr>
//                   <th>Nr. </th>
//                   <th>Name </th>
//                   <th>H_T_V </th>
//                   <th>H_V_V </th>
//                   <th>Hbd_ex_rate/b </th>
//                   <th>Hbd_ex_rate/q </th>
//                   <th>last_aslot </th>
//                   <th>last_conf_nr </th>
//                   <th>last_hbd_ex_updt </th>
//                   <th>run_vers </th>
//                   <th>total_missed </th>
//                   <th>URL</th>
//                 </tr>
//               </thead>
//               <tbody>
//                 <td>
//                   {nr.map((n) => (
//                     <tr>{`${n}.`}</tr>
//                   ))}
//                 </td>

//                 <td>
//                   {witnessData && witnessData.map((w) => <tr>{w.owner}</tr>)}
//                 </td>

//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => <tr>{w.hardfork_time_vote}</tr>)}
//                 </td>
//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => <tr>{w.hardfork_version_vote}</tr>)}
//                 </td>
//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => <tr>{w.hbd_exchange_rate.base}</tr>)}
//                 </td>
//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => (
//                       <tr>{w.hbd_exchange_rate.quote}</tr>
//                     ))}
//                 </td>
//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => <tr>{w.last_aslot}</tr>)}
//                 </td>
//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => (
//                       <tr>{w.last_confirmed_block_num}</tr>
//                     ))}
//                 </td>
//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => (
//                       <tr>{w.last_hbd_exchange_update}</tr>
//                     ))}
//                 </td>
//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => <tr>{w.running_version}</tr>)}
//                 </td>
//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => <tr>{w.total_missed}</tr>)}
//                 </td>
//                 <td>
//                   {witnessData &&
//                     witnessData.map((w) => (
//                       <tr>
//                         <a href={w.url} target="_blank">
//                           Open
//                         </a>
//                       </tr>
//                     ))}
//                 </td>
//               </tbody>
//             </Table>
//           </Col>
//         </Row>
//       </Container>
//     </div>
//   );
// }
