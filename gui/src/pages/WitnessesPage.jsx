import React, { useContext, useState } from "react";
import { ApiContext } from "../context/apiContext";
import { Row, Col, Container, Table } from "react-bootstrap";

export default function Witnesses_Page({ setTitle }) {
  setTitle("HAF | Witnesess");
  const { witnessData } = useContext(ApiContext);
  let nr = [];
  for (let i = 1; i <= witnessData?.length; i++) {
    nr.push(i);
  }

  return (
    <div>
      <Container>
        <Row>
          <Col>
            <Table striped bordered hover variant="light" responsive>
              <thead>
                <tr>
                  <th>Nr. </th>
                  <th>Name </th>
                  <th>H_T_V </th>
                  <th>H_V_V </th>
                  <th>Hbd_ex_rate/b </th>
                  <th>Hbd_ex_rate/q </th>
                  <th>last_aslot </th>
                  <th>last_conf_nr </th>
                  <th>last_hbd_ex_updt </th>
                  <th>run_vers </th>
                  <th>total_missed </th>
                  <th>URL</th>
                </tr>
              </thead>
              <tbody>
                <td>
                  {nr.map((n) => (
                    <tr>{`${n}.`}</tr>
                  ))}
                </td>

                <td>
                  {witnessData && witnessData.map((w) => <tr>{w.owner}</tr>)}
                </td>

                <td>
                  {witnessData &&
                    witnessData.map((w) => <tr>{w.hardfork_time_vote}</tr>)}
                </td>
                <td>
                  {witnessData &&
                    witnessData.map((w) => <tr>{w.hardfork_version_vote}</tr>)}
                </td>
                <td>
                  {witnessData &&
                    witnessData.map((w) => <tr>{w.hbd_exchange_rate.base}</tr>)}
                </td>
                <td>
                  {witnessData &&
                    witnessData.map((w) => (
                      <tr>{w.hbd_exchange_rate.quote}</tr>
                    ))}
                </td>
                <td>
                  {witnessData &&
                    witnessData.map((w) => <tr>{w.last_aslot}</tr>)}
                </td>
                <td>
                  {witnessData &&
                    witnessData.map((w) => (
                      <tr>{w.last_confirmed_block_num}</tr>
                    ))}
                </td>
                <td>
                  {witnessData &&
                    witnessData.map((w) => (
                      <tr>{w.last_hbd_exchange_update}</tr>
                    ))}
                </td>
                <td>
                  {witnessData &&
                    witnessData.map((w) => <tr>{w.running_version}</tr>)}
                </td>
                <td>
                  {witnessData &&
                    witnessData.map((w) => <tr>{w.total_missed}</tr>)}
                </td>
                <td>
                  {witnessData &&
                    witnessData.map((w) => (
                      <tr>
                        <a href={w.url} target="_blank">
                          Open
                        </a>
                      </tr>
                    ))}
                </td>
              </tbody>
            </Table>
          </Col>
        </Row>
      </Container>
    </div>
  );
}
