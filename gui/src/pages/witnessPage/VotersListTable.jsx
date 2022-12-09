import React, { useState, useEffect } from "react";
import styles from "./witnessTable.module.css";
import { Pagination } from "@mui/material";
import axios from "axios";
import Loader from "../../components/loader/Loader";
import usePagination from "../../components/Pagination";

const CELLS = ["name", "hp", "account hp", "proxied hp"];
const stylesButtonInherit = {
  background: "inherit",
  border: "none",
  color: "#fff",
};

export default function VotersListTable({
  isVotersListTable,
  setIsVotersListTable,
  witnessVotersList,
  handleOrderBy,
  arrowPosition,
  linkToUserProfile,
  setVotersPagination,
  currentWitness,
}) {
  const [page, setPage] = useState(1);
  const [votersCount, setVotersCount] = useState(null);

  useEffect(() => {
    if (currentWitness) {
      axios({
        method: "post",
        url: `http://192.168.4.250:3000/rpc/get_witness_voters_num`,
        headers: { "Content-Type": "application/json" },
        data: {
          _witness: currentWitness?.witness,
        },
      }).then((res) => setVotersCount(res.data));
    }
  }, [currentWitness]);

  useEffect(() => {
    setVotersPagination(page === 1 ? 0 : (page - 1) * 100);
  }, [setVotersPagination, page]); //TODO: check if this setVotersPagination is needed here

  const PER_PAGE = witnessVotersList?.length;
  const count = Math.ceil(votersCount / 100);
  const _DATA = usePagination(witnessVotersList, PER_PAGE);

  const handleChange = (e, p) => {
    setPage(p);
    _DATA.jump(p);
  };

  const handlecloseTable = () => {
    setIsVotersListTable(false);
    setVotersCount(0);
    setVotersPagination(0);
    setPage(1);
  };

  return (
    <div hidden={!isVotersListTable} className={styles.modal}>
      <div className={styles["modal-content"]}>
        {votersCount === 0 || !witnessVotersList ? (
          <Loader />
        ) : (
          <>
            <div className={styles["modal-header"]}>
              <h2>Voters list</h2>
              <span>
                <button
                  style={{ background: "inherit", border: "none" }}
                  onClick={handlecloseTable}
                  className={styles.close}
                >
                  &times;
                </button>
              </span>
            </div>

            <div
              style={{
                display: "flex",
                justifyContent: "center",
                alignItems: "center",
                marginBottom: "25px",
              }}
            >
              {
                <Pagination
                  count={count}
                  size="large"
                  page={page}
                  variant="outlined"
                  shape="rounded"
                  onChange={handleChange}
                />
              }
            </div>
            <table style={{ width: "100%" }}>
              <thead>
                <tr style={{ fontSize: "20px", fontWeight: "bold" }}>
                  {CELLS.map((cell, i) => (
                    <th key={i}>
                      {cell.toUpperCase()}
                      <button
                        onClick={() => handleOrderBy(cell)}
                        style={stylesButtonInherit}
                      >
                        {arrowPosition(cell)}
                      </button>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {witnessVotersList?.map((voter) => (
                  <tr
                    key={voter.account}
                    style={{ fontSize: "16px", fontWeight: "light" }}
                  >
                    <td>{linkToUserProfile(voter.account)}</td>
                    <td>{voter.hive_power.toFixed(2)}</td>
                    <td>{voter.account_hive_power.toFixed(2)}</td>
                    <td>{voter.proxied_hive_power.toFixed(2)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}
      </div>
    </div>
  );
}
