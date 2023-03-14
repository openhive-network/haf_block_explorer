import { Box, Button } from "@mui/material";
import ArrowUpwardIcon from "@mui/icons-material/ArrowUpward";

const DEFAULT_BUTTON_BOX_STYLES = {
  position: "fixed",
  bottom: "50px",
  right: "50px",
};

const DEFAULT_BUTTON_STYLES = {
  height: "50px",
  width: "50px",
};

const TopScrollButton = () => {
  const handelScrollToTop = () => {
    document.body.scrollTop = 0;
    document.documentElement.scrollTop = 0;
  };
  return (
    <Box sx={DEFAULT_BUTTON_BOX_STYLES}>
      <Button
        onClick={handelScrollToTop}
        sx={DEFAULT_BUTTON_STYLES}
        variant="contained"
        color="secondary"
      >
        <ArrowUpwardIcon />
      </Button>
    </Box>
  );
};

export default TopScrollButton;
