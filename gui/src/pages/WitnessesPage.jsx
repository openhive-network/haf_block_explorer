import React, { useContext } from "react";
import { ApiContext } from "../context/apiContext";
import { Row, Col } from "react-bootstrap";

export default function Witnesses_Page() {
  const { witnessData } = useContext(ApiContext);
  console.log(witnessData);
  return (
    <div>
      <table>
        <tr>
          <th>Name || </th>
          <th>H_V_T || </th>
          <th>H_V_V || </th>
          <th>Hbd_ex_rate || </th>
          <th>last_aslot || </th>
          <th>last_conf_nr || </th>
          <th>last_hbd_ex_updt || </th>
          <th>run_vers || </th>
          <th>total_missed || </th>
        </tr>
        <ol>
          {witnessData &&
            witnessData.map((w) => (
              <li>
                <tr>
                  <td>{w.owner}</td>
                </tr>
              </li>
            ))}
        </ol>

        {witnessData &&
          witnessData.map((w) => (
            <tr>
              <td>{w.hardfork_time_vote}</td>
            </tr>
          ))}
      </table>
    </div>
  );
}
