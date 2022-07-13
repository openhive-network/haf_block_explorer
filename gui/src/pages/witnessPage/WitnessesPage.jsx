import React, { useContext, useState } from "react";
import { WitnessContext } from "../../contexts/witnessContext";
import Loader from "../../components/loader/Loader";
import WitnessTable from "./WitnessTable";
import VotersListTable from "./VotersListTable";
import VotesHistoryTable from "./VotesHistoryTable";
export default function DataTable() {
  document.title = "HAF | Witnesses";
  const { witnessData } = useContext(WitnessContext);

  const [isVotersListTable, setIsVotersListTable] = useState(false);
  const [isVotesHistoryTableOpen, setIsVotesHistoryTableOpen] = useState(false);

  const handleOpenVotersListTable = () => {
    setIsVotersListTable(!isVotersListTable);
  };
  const handleOpenVotesHistoryTable = () => {
    setIsVotesHistoryTableOpen(!isVotesHistoryTableOpen);
  };
  return (
    <>
      {witnessData === null ? (
        <Loader />
      ) : (
        <>
          <WitnessTable
            handleOpenVotesHistoryTable={handleOpenVotesHistoryTable}
            handleOpenVotersListTable={handleOpenVotersListTable}
          />
          <VotersListTable
            isVotersListTable={isVotersListTable}
            setIsVotersListTable={setIsVotersListTable}
          />
          <VotesHistoryTable
            isVotesHistoryTableOpen={isVotesHistoryTableOpen}
            setIsVotesHistoryTableOpen={setIsVotesHistoryTableOpen}
          />
        </>
      )}
    </>
  );
}
