import { useContext } from "react";
import { ApiContext } from "../context/apiContext";
import OperationCard from "../components/OperationCard";
import { Link } from "react-router-dom";

export default function Main_Page() {
  const { head_block, head_block_data } = useContext(ApiContext);
  const current_head_block = head_block.head_block_number;
  const transaction = head_block_data?.transactions;
  const transactions_of_block = transaction?.map(
    (trans) => trans.operations[0]
  );

  const operations_count_per_block = transaction?.length;
  const transactions_ids = head_block_data.transaction_ids;

  const tr = localStorage.getItem("transaction");
  console.log(tr);

  return (
    <div className="main">
      <h1>
        Head Block :
        <Link
          onClick={() => localStorage.setItem("block", current_head_block)}
          to={`/block/${current_head_block}`}
        >
          {current_head_block}
        </Link>
      </h1>
      <h4>
        Operations per block :
        {operations_count_per_block !== 0 && operations_count_per_block}
      </h4>
      <h4>Current witness :{head_block.current_witness}</h4>
      <br></br>
      {transactions_of_block?.map((single, index) => (
        <OperationCard
          key={index}
          transaction={single}
          k={index}
          tr_id={transactions_ids}
        />
      ))}
    </div>
  );
}
