### Blocks
* `/blocks`
* `/blocks/:block-num`
* `/blocks/:block-num/raw-details`
* `/blocks/:block-num/operations?operation-types,page,account-name,key-conent,set-of-keys`
* `/blocks/:block-num/operations/types`
* `/blocks/:block-num/operations/count`
* `/blocks/:block-num/latest` - ?

### Block numbers
* `/block-numbers?limit,operation-types,account-name,from-block,to-block,start-date,end-date,key-content,key-conent,set-of-keys`
* `/block-numbers/time/:timestamp`
* `/block-numbers/last-synced`
* `/block-numbers/headblock`

### Transactions
* `/transactions/:transaction-id`

### Operation
* `/operations/:operation-id`
* `/operation-types`
* `/operation-types/:input-type`
* `/operation-keys/:operation-type`

### Account
* `/accounts/:account-name`
* `/accounts/:account-name/authority`
* `/accounts/:account-name/operations?operation-types,page-num,page-size,from-block,to-block,date-start,date-end,body-limit`
* `/accounts/:account-name/operations/types`
* `/accounts/:account-name/operations/comments?permlink,page-num,page-size,operation-types,from-block,to-block,start-date,end-date,body-limit`

### Witnesses
* `/witnesses?limit,order-by,order-is`
* `/witnesses/:account-name`
* `/witnesses/:account-name/voters?order-by,order-is`
* `/witnesses/:account-name/voters/count`
* `/witnesses/:account-name/votes/history?limit,order-by,order-is,start-date,end-date`

### Other
* `/input-type/:input-type`
* `/hafbe-version`
