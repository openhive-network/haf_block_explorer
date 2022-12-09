import React, {
  useContext,
  useState,
  useEffect,
  useRef,
  useCallback,
} from "react";
import { WitnessContext } from "../../contexts/witnessContext";
import Loader from "../../components/loader/Loader";
import WitnessTable from "./WitnessTable";
import VotersListTable from "./VotersListTable";
import VotesHistoryTable from "./VotesHistoryTable";
import axios from "axios";
import { HeadBlockContext } from "../../contexts/headBlockContext";
import { calculateHivePower } from "../../functions/calculations";
import {
  TiArrowUnsorted,
  TiArrowSortedUp,
  TiArrowSortedDown,
} from "react-icons/ti";
import { Link } from "react-router-dom";

export default function DataTable() {
  document.title = "HAF | Witnesses";
  const {
    witnessData,
    witnessTableOrderBy,
    witnessOrderDescending,
    handleOrderBy,
  } = useContext(WitnessContext);
  const [isVotersListTable, setIsVotersListTable] = useState(false);
  const [isVotesHistoryTableOpen, setIsVotesHistoryTableOpen] = useState(false);
  const [witnessVotersList, setWitnessVotersList] = useState(null);
  const [currentWitness, setCurrentWintess] = useState("");
  const [orderDescending, setOrderDescending] = useState(true);

  const [orderBy, setOrderBy] = useState(null);
  const { vesting_fund, vesting_shares } = useContext(HeadBlockContext);
  const [votersPagination, setVotersPagination] = useState(0);

  const handeOpenVotersListTable = (witness) => {
    setIsVotersListTable(!isVotersListTable);
    setCurrentWintess(witness);
  };

  const handleOpenVotesHistoryTable = (witness) => {
    setIsVotesHistoryTableOpen(!isVotesHistoryTableOpen);
    setCurrentWintess(witness);
  };
  const vestsToHive = (vests) => {
    return calculateHivePower(vests, vesting_fund, vesting_shares);
  };
  const orderByCellName = {
    date: "timestamp",
    name: "voter",
    hp: "vests",
    "account hp": "account_vests",
    "proxied hp": "proxied_vests",
  };
  useEffect(() => {
    if (isVotesHistoryTableOpen) {
      setOrderBy("timestamp");
    } else setOrderBy(null);
  }, [isVotesHistoryTableOpen]);

  const handleOrderByVoters = (cell) => {
    setOrderBy(orderByCellName[cell]);
    setOrderDescending(cell && !orderDescending);
  };

  const arrowPosition = (cell) => {
    if (cell === witnessTableOrderBy) {
      if (witnessOrderDescending) {
        return <TiArrowSortedDown />;
      } else {
        return <TiArrowSortedUp />;
      }
    }
    if (orderBy === orderByCellName[cell]) {
      if (orderDescending) {
        return <TiArrowSortedDown />;
      } else {
        return <TiArrowSortedUp />;
      }
    }
    return <TiArrowUnsorted />;
  };

  const linkToUserProfile = (username) => {
    return <Link to={`/user/${username}`}>{username}</Link>;
  };

  useEffect(() => {
    if (currentWitness) {
      axios({
        method: "post",
        url: `http://192.168.4.250:3000/rpc/get_witness_voters`,
        headers: { "Content-Type": "application/json" },
        data: {
          _witness: currentWitness.witness,
          _limit: 100,
          _offset: votersPagination,
          _order_by: orderBy, //orderBy
          _order_is: orderDescending ? "desc" : "asc",
        },
      }).then((res) => setWitnessVotersList(res.data));
    }
    return () => setWitnessVotersList(null);
  }, [currentWitness, votersPagination, orderDescending, orderBy]);

  return (
    <>
      {!witnessData ? (
        <Loader />
      ) : (
        <>
          <WitnessTable
            handleOpenVotesHistoryTable={handleOpenVotesHistoryTable}
            setCurrentWintess={setCurrentWintess}
            handeOpenVotersListTable={handeOpenVotersListTable}
            orderBy={orderBy}
            setOrderBy={setOrderBy}
            handleOrderBy={handleOrderBy}
            arrowPosition={arrowPosition}
            linkToUserProfile={linkToUserProfile}
            vestsToHive={vestsToHive}
          />
          <VotersListTable
            witnessVotersList={witnessVotersList}
            isVotersListTable={isVotersListTable}
            setIsVotersListTable={setIsVotersListTable}
            orderBy={orderBy}
            setOrderBy={setOrderBy}
            vestsToHive={vestsToHive}
            handleOrderBy={handleOrderByVoters}
            arrowPosition={arrowPosition}
            linkToUserProfile={linkToUserProfile}
            setVotersPagination={setVotersPagination}
            currentWitness={currentWitness}
          />
          <VotesHistoryTable
            arrowPosition={arrowPosition}
            handleOrderBy={handleOrderByVoters}
            vestsToHive={vestsToHive}
            witnessVotersList={witnessVotersList}
            isVotesHistoryTableOpen={isVotesHistoryTableOpen}
            setIsVotesHistoryTableOpen={setIsVotesHistoryTableOpen}
            setOrderBy={setOrderBy}
            orderBy={orderBy}
            linkToUserProfile={linkToUserProfile}
          />
        </>
      )}
    </>
  );
}
