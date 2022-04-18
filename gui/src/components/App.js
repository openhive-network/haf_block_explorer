import "bootstrap/dist/css/bootstrap.min.css";
import Header from "./layout/Header";
import Content from "./layout/Content";
import Footer from "./layout/Footer";
import "../styles/App.css";

function App() {
  return (
    <div className="App">
      <Header />
      <Content />
      <Footer />
    </div>
  );
}

export default App;
