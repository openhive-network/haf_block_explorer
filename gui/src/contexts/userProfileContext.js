import { useState, createContext, useEffect } from "react";
import axios from "axios";
import useDebounce from "../components/customHooks/useDebounce";

export const UserProfileContext = createContext();
export const UserProfileContextProvider = ({ children }) => {
  const [userProfile, setUserProfile] = useState("");
  const [user_profile_data, setUser_profile_data] = useState(null);
  const [acc_history_limit, set_acc_history_limit] = useState(100);
  const [op_filters, set_op_filters] = useState([]);
  const [user_info, set_user_info] = useState("");
  const [op_types, set_op_types] = useState(null);
  const [pagination, set_pagination] = useState(-1);
  const [resource_credits, set_resource_credits] = useState({});
  const [startDateState, setStartDateState] = useState(null);
  const [endDateState, setEndDateState] = useState(null);

  const [opTypesLoading, setOpTypesLoading] = useState(false);
  const [userDataLoading, setUserDataLoading] = useState(false);

  const debouncePagination = useDebounce(pagination, 200);

  useEffect(() => {
    (async function () {
      setOpTypesLoading(true);
      try {
        if (userProfile) {
          axios({
            method: "post",
            url: `http://192.168.4.250:3000/rpc/get_acc_op_types`,
            headers: { "Content-Type": "application/json" },
            data: {
              _account: userProfile,
            },
          }).then((res) => set_op_types(res.data));
        }
      } catch (err) {
        console.log(err);
      } finally {
        setOpTypesLoading(false);
      }
    })();
  }, [userProfile]);

  useEffect(() => {
    if (userProfile) {
      const calc_limit =
        debouncePagination !== -1 && acc_history_limit > debouncePagination
          ? debouncePagination
          : acc_history_limit;

      (async function () {
        setUserDataLoading(true);
        try {
          await axios({
            method: "post",
            url: `http://192.168.4.250:3000/rpc/get_ops_by_account`,
            headers: { "Content-Type": "application/json" },
            data: {
              _account: userProfile,
              _top_op_id: debouncePagination,
              _limit: calc_limit,
              _filter: op_filters,
              _date_start: startDateState,
              _date_end: endDateState,
            },
          }).then((res) => setUser_profile_data(res?.data));
        } catch (err) {
          console.log(err);
        } finally {
          setUserDataLoading(false);
        }
      })();
    }
  }, [
    userProfile,
    debouncePagination,
    acc_history_limit,
    op_filters,
    startDateState,
    endDateState,
  ]);

  useEffect(() => {
    if (userProfile) {
      axios({
        method: "post",
        url: "http://192.168.4.250:3000/rpc/get_account",
        headers: { "Content-Type": "application/json" },
        data: { _account: userProfile },
      }).then((res) => set_user_info(res?.data));
    }
    return () => set_user_info("");
  }, [userProfile]);

  useEffect(() => {
    if (userProfile) {
      axios({
        method: "post",
        url: `http://192.168.4.250:3000/rpc/get_account_resource_credits`,
        headers: { "Content-Type": "application/json" },
        data: { _account: userProfile },
      }).then((res) => set_resource_credits(res?.data));
    }
    return () => set_resource_credits({});
  }, [userProfile]);

  return (
    <UserProfileContext.Provider
      value={{
        resource_credits: resource_credits,
        set_pagination: set_pagination,
        pagination: pagination,
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
        startDateState: startDateState,
        setStartDateState: setStartDateState,
        endDateState: endDateState,
        setEndDateState: setEndDateState,
        opTypesLoading: opTypesLoading,
        userDataLoading: userDataLoading,
        debouncePagination: debouncePagination,
      }}
    >
      {children}
    </UserProfileContext.Provider>
  );
};
