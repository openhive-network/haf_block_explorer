### Operation
* `/operations/:operation-id`

* `/operation-types`
* `/operation-types/:input-type`

* `/operation-keys/:operation-type`

### Transactions
* `/transactions/:transaction-id`

### Block
* `/blocks`
* `/blocks/:block-num`
* `/blocks/:block-num/raw-details`
* `/blocks/:block-num/operations?operation-types,page,account-name,key-conent,set-of-keys`
* `/blocks/:block-num/operation-types`
* `/blocks/:block-num/operations-count`
* `/blocks/:block-num/latest` - ?

* `/block-numbers?limit,operation-types,account-name,from-block,to-block,start-date,end-date,key-content,key-conent,set-of-keys`
* `/block-numbers/time/:timestamp`
* `/block-numbers/last-synced`
* `/block-numbers/headblock`

### Account
* `/accounts/:account-name`
* `/accounts/:account-name/operation-types`
* `/accounts/:account-name/authority`
* `/accounts/:account-name/operations?operation-types,page-num,page-size,from-block,to-block,date-start,date-end,body-limit`
* `/accounts/:account-name/comments-operations?permlink,page-num,page-size,operation-types,from-block,to-block,start-date,end-date,body-limit`

### Witnesses
* `/witnesses?limit,order-by,order-is`
* `/witnesses/:account-name`
* `/witnesses/:account-name/voters?order-by,order-is`
* `/witnesses/:account-name/votes/history?limit,order-by,order-is,start-date,end-date`


### Other
* `/input-type/:input-type`
* `/hafbe-version`
