import { useContext } from "react";
import { ApiContext } from "../context/apiContext";
import OperationCard from "../components/OperationCard";
import { Link } from "react-router-dom";

export default function Main_Page() {
  const { head_block, head_block_data, setBlockNumber, setUserProfile } =
    useContext(ApiContext);
  const current_head_block = head_block.head_block_number;
  const transaction = head_block_data?.transactions;
  const transactions_of_block = transaction?.map(
    (trans) => trans.operations[0]
  );

  const operations_count_per_block = transaction?.length;
  const transactions_ids = head_block_data.transaction_ids;

  return (
    <div className="main">
      <h1>
        Head Block :
        <Link
          onClick={() => setBlockNumber(current_head_block)}
          to={`/block/${current_head_block}`}
        >
          {current_head_block}
        </Link>
      </h1>
      <h4>
        Operations per block :
        {operations_count_per_block !== 0 && operations_count_per_block}
      </h4>
      <h4>
        Current witness :
        <Link to={`/user/${head_block.current_witness}`}>
          <p onClick={() => setUserProfile(head_block.current_witness)}>
            {head_block.current_witness}
          </p>
        </Link>
      </h4>
      <h4>
        <Link to="/witnesses">Top Wintesses</Link>
      </h4>
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
