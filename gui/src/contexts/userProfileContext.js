import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const UserProfileContext = createContext();
export const UserProfileContextProvider = ({ children }) => {
  const [userProfile, setUserProfile] = useState("");
  const [user_profile_data, setUser_profile_data] = useState([]);
  const [acc_history_limit, set_acc_history_limit] = useState(1000);
  const [op_filters, set_op_filters] = useState([]);
  const [user_info, set_user_info] = useState("");
  const [op_types, set_op_types] = useState([]);

  //Get available operation types for current user
  useEffect(() => {
    if (userProfile !== "") {
      axios({
        method: "post",
        url: "http://192.168.5.118:3002/rpc/get_acc_op_types",
        headers: { "Content-Type": "application/json" },
        data: {
          _account: userProfile,
        },
      }).then((res) => set_op_types(res.data));
    }
  }, [userProfile, set_op_types]);
  //  Get user profile data #2

  useEffect(() => {
    if (userProfile !== "") {
      axios({
        method: "post",
        url: "http://192.168.5.118:3002/rpc/get_ops_by_account",
        headers: { "Content-Type": "application/json" },
        data: {
          _account: userProfile,
          _start: -1,
          _limit: acc_history_limit,
          _filter: op_filters,
        },
      }).then((res) => setUser_profile_data(res.data));
    }
  }, [userProfile, op_filters, acc_history_limit, setUser_profile_data]);

  // Get user personal info
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "condenser_api.get_accounts",
        params: [[userProfile]],
        id: 1,
      },
    }).then((res) => set_user_info(res?.data?.result[0]));
  }, [userProfile]);
  return (
    <UserProfileContext.Provider
      value={{
        userProfile: userProfile,
        setUser_profile_data: setUser_profile_data,
        user_profile_data: user_profile_data,
        setUserProfile: setUserProfile,
        set_acc_history_limit: set_acc_history_limit,
        acc_history_limit: acc_history_limit,
        set_op_filters: set_op_filters,
        user_info: user_info,
        op_types: op_types,
        op_filters: op_filters,
        set_op_filters: set_op_filters,
      }}
    >
      {children}
    </UserProfileContext.Provider>
  );
};
