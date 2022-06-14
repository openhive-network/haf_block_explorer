import "bootstrap/dist/css/bootstrap.min.css";

// import { useContext } from "react";
import Header from "./layout/header/Header";
import Content from "./layout/content/Content";
import Footer from "./layout/footer/Footer";
import "../styles/App.css";

// import { HeadBlockContext } from "../contexts/headBlockContext";
export default function App() {
  // const { head_block_data } = useContext(HeadBlockContext);

  // For head block (main page) only
  // const isDataLoading =
  //   head_block_data?.transaction_ids?.length === 0 ||
  //   head_block_data?.transaction_ids?.length == undefined;

  return (
    // <div className="App">
    //   {isDataLoading ? (
    //     "Data loading"
    //   ) : (
    <>
      <Header />
      <Content />
      <Footer />
    </>
    //   )}
    // </div>
  );
}
