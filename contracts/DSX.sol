pragma solidity ^0.4.6;

import "Token.sol";

contract DSX {

    // only for truffle 
    function getLastTokenAddress() constant returns (address) {
      return markets[nextMarketID - 1].addr;
    }

    /* 
    Each Token has its own Market struct
     */
    Market[] markets;

    /* 
    The order book is implemented in form of two mappings for the bid and ask quotes. Each market is
    identifiable by its block number, name, id and token address. Hence, each token can get
    registered only once and all orders associated with the token are matched within one order
    book
    */
    struct Market{
      uint256 id;
      bytes32 name;
      address addr;
      uint256 lastPrice;
      address owner;
      uint256 blockNumber;
      bytes32 lowestAskId;
      bytes32 highestBidId;
      mapping (bytes32 => OrderId) askOrderBook;
      mapping (bytes32 => OrderId) bidOrderBook;
    }   

    /* 
    The OrderId struct serves as means to create a linked list on basis
    of solidity’s mapping storage type.
     */
    struct OrderId{
      bytes32 id;
      bytes32 nextId;
      bytes32 prev_id;
    }

    /*
    All trade information associated with a particular order is saved in a struct named "Order". 
    The variable “typ” simply defines whether it is a bid or ask order. The marketId assigns 
    the order to a particular token. The blockNumber indicates when the
    order was incorporated into the Blockchain. By hashing all the variables, each order gets
    assigned to a unique id that is used in a global mapping.
    */
    struct Order {
      bytes32 typ;
      uint256 amount;
      uint256 price;
      uint256 marketId;
      bytes32 id;
      address sender;
      address owner;
      uint256 blockNumber;
    }

    /* 
    Tracks the users' balances. Further explanations in comment above deposit functions
    */
    struct LocalBalance {
      uint256 available;
      uint256 trading;
    }

    mapping (bytes32 => Order) orders;
    mapping (address => mapping (uint256 => LocalBalance)) public balances;
    uint256 public nextMarketID = 0;
    Token currentToken;
    uint256[] bidPrice;
    uint256[] bidVol;
    uint256[] askPrice;
    uint256[] askVol;

    // only for truffle
    function getAvailableBalance(uint256 _marketId) constant returns(uint256){
      return balances[msg.sender][_marketId].available;
    }

    /* 
    Retrieves two arrays, containing the prices and volumes of the bid order book
     */
    function getBidOrders(uint256 _marketId) constant returns (uint256[] rv1,uint256[] rv2){
        bytes32 bidIdIter = markets[_marketId].highestBidId;
        bidPrice = rv1;
        bidVol = rv2;
        while (orders[bidIdIter].amount != 0){
          bidVol.push(orders[bidIdIter].amount);
          bidPrice.push(orders[bidIdIter].price);
          bidIdIter = markets[_marketId].bidOrderBook[bidIdIter].nextId;
          }
        return(bidPrice,bidVol);
    }

    /* 
    Retrieves two arrays, containing the prices and volumes of the ask order book
     */
    function getAskOrders(uint256 _marketId) constant returns (uint256[] rv1,uint256[] rv2){
          askPrice = rv1;
          askVol = rv2;
          bytes32 askIdIter = markets[_marketId].lowestAskId;
          while (orders[askIdIter].amount != 0){
            askPrice.push(orders[askIdIter].price);
            askVol.push(orders[askIdIter].amount);
            askIdIter = markets[_marketId].askOrderBook[askIdIter].nextId;
          }
        return(askPrice,askVol);
    }

    /*
    After creating the individual token contract, it needs to be registered with the exchange.
    By passing the token’s address as parameter to the “registerToken” function, a Market struct
    is created containing the order book for the associated token.
     */
    function registerToken(address _addr, bytes32 _name) {
          markets.push(Market(nextMarketID,_name,_addr,1,msg.sender,block.number,0,0));
          nextMarketID +=1;
          currentToken = Token(_addr);
    }

    /*
    In order to execute an initial public offering, the token owner needs to deposit tokens
    on the exchange, so that the exchange is capable of executing orders on his behalf. In
    technical terms this means that the token owner allows the exchange contract to credit
    tokens to its account inside the token contract. Hence, according to the token contract, the
    owner has given away tokens to the exchange. The DSX contract itself now keeps track of
    which user owns how much of the exchange’s tokens. At this point, a distinction is made between
    available and trading balance. The former one determines the amount of tokens
    that are free to withdraw and trade. The latter one determines the amount of tokens that are 
    bound to outstanding orders. By doing so, the obvious attack vector to double spend tokens that 
    are not yet matched is eliminated.
     */
    function deposit(uint256 _amount,uint256 _marketId) {
          currentToken = Token(markets[_marketId].addr);
          if (currentToken.transferFrom(msg.sender, this, _amount)){
            uint256 balance = balances[msg.sender][_marketId].available;
            balance = balance + _amount;
            balances[msg.sender][_marketId].available = balance;
          }
    }
    
    /* 
    Token owners are free to withdraw their tokens at any time. This ensures
    that tokens stay independent and tradable on any exchange. Especially in view of the fact
    that any error in the exchange’s complex code may lead to a total loss of all funds, the
    option to withdraw tokens to save them within the much simpler token contract is of vital
    importance.
     */
    function withdraw(uint256 _amount, uint256 _marketId) {
          currentToken = Token(markets[_marketId].addr);
          if (currentToken.transfer(msg.sender, _amount)) {
            uint256 balance = balances[msg.sender][_marketId].available;
            balance = balance - _amount;
            balances[msg.sender][_marketId].available = balance;
          }
    }

    function checkOrder(uint256 _amount, uint256 _price, uint256 _marketId) returns (bool rv){
          if (_amount <= 0 || _price <=0 || _marketId <0) return false;
          return true;
    }

    /* 
    Saves an order and verifies that the buyer has attached enough Ether
     */
    function buy(uint256 _amount, uint256 _price, uint256 _marketId) payable {
          uint256 rv;
          if (!checkOrder(_amount, _price, _marketId)) throw;
          rv = ((_amount*_price) * 10000000000000000);
          if (msg.value < rv) throw;
          if (msg.value >= rv){
          if (!msg.sender.send(msg.value - rv)) throw;
          }
          saveOrder("BID",_amount,_price,_marketId);
          matchOrders(_marketId);
    }

    /* 
    Saves an order and verifies that the seller has enough tokens
     */
    function sell(uint256 _amount, uint256 _price, uint256 _marketId){
          if (!checkOrder(_amount, _price, _marketId)) throw;
          uint256 balance = balances[msg.sender][_marketId].available;
          if (balance > _amount){
            saveOrder("ASK",_amount,_price,_marketId);
          }
          matchOrders(_marketId);
    }

    /*
    Saves an order in the linked list while maintaning a best price sequence
    */
    function saveOrder(bytes32 _typ,uint256 _amount, uint256 _price, uint256 _marketId) returns(bytes32 rv){
          // Daten typ Konvertierung "memory" zu "storage"
          bytes32 typ = _typ;
          uint256 amount = _amount;
          uint256 marketId = _marketId;
          uint256 price = _price;
      
          bytes32 tradeId = sha3(typ,amount,price,marketId,msg.sender,block.number);
          if (orders[tradeId].id != 0) throw;
          orders[tradeId].typ = typ;
          orders[tradeId].amount = amount;
          orders[tradeId].price = price;
          orders[tradeId].marketId = marketId;
          orders[tradeId].sender = msg.sender;
          orders[tradeId].blockNumber = block.number;
          orders[tradeId].id = tradeId;
          bool positionFound = false;
          bytes32 id_iter;
          if (typ == "ASK"){
            bytes32 lowestAskId = markets[marketId].lowestAskId;
            markets[marketId].askOrderBook[tradeId].id = tradeId;
            if (orders[lowestAskId].price == 0 || price < orders[lowestAskId].price){     // fälle wo ask ganz vorne dran gehangen wird
              if (orders[lowestAskId].price == 0) {
                markets[marketId].lowestAskId  = tradeId;
              } else {
                markets[marketId].askOrderBook[tradeId].nextId = markets[marketId].lowestAskId ;
                markets[marketId].lowestAskId = tradeId;
              }
            } else {
               id_iter = lowestAskId;
              while (!positionFound){ // ask wird iwo zwischen gesetzt
                if (price < orders[markets[marketId].askOrderBook[id_iter].nextId].price) {
                  markets[marketId].askOrderBook[tradeId].nextId = markets[marketId].askOrderBook[id_iter].nextId;
                  markets[marketId].askOrderBook[tradeId].prev_id = id_iter;
                  markets[marketId].askOrderBook[markets[marketId].askOrderBook[id_iter].nextId].prev_id = tradeId;
                  markets[marketId].askOrderBook[id_iter].nextId = tradeId;
                  positionFound = true;
                }
                if (markets[marketId].askOrderBook[id_iter].nextId == 0){ // ask wird ganz hinten dran gehangen
                  markets[marketId].askOrderBook[tradeId].prev_id = id_iter;
                  markets[marketId].askOrderBook[id_iter].nextId = tradeId;
                  positionFound = true;
                }
                id_iter = markets[marketId].askOrderBook[id_iter].nextId;
                balances[msg.sender][marketId].available -= amount;
                balances[msg.sender][marketId].trading += amount;
              }
            }
          }
          if (typ == "BID"){
              bytes32 highestBidId = markets[marketId].highestBidId;
              markets[marketId].bidOrderBook[tradeId].id = tradeId;
              if (orders[highestBidId].price == 0 || price > orders[highestBidId].price){     // fälle wo bid ganz vorne dran gehangen wird
                if (orders[highestBidId].price == 0) {
                  markets[marketId].highestBidId  = tradeId;
                } else {
                  markets[marketId].bidOrderBook[tradeId].nextId = markets[marketId].highestBidId ;
                  markets[marketId].highestBidId = tradeId;
                }
              } else {
                 id_iter = highestBidId;
                while (!positionFound){ // bid wird iwo zwischen gesetzt
                  if (price > orders[markets[marketId].bidOrderBook[id_iter].nextId].price) {
                    markets[marketId].bidOrderBook[tradeId].nextId = markets[marketId].bidOrderBook[id_iter].nextId;
                    markets[marketId].bidOrderBook[tradeId].prev_id = id_iter;
                    markets[marketId].bidOrderBook[markets[marketId].bidOrderBook[id_iter].nextId].prev_id = tradeId;
                    markets[marketId].bidOrderBook[id_iter].nextId = tradeId;
                    positionFound = true;
                  }
                  if (markets[marketId].bidOrderBook[id_iter].nextId == 0){ // bid wird ganz hinten dran gehangen
                    markets[marketId].bidOrderBook[tradeId].prev_id = id_iter;
                    markets[marketId].bidOrderBook[id_iter].nextId = tradeId;
                    positionFound = true;
                  }
                  id_iter = markets[marketId].bidOrderBook[id_iter].nextId;
                  balances[msg.sender][marketId].available -= amount;
                  balances[msg.sender][marketId].trading += amount;
                }
            }
          }
    }

    /* 
    Removes an order struct from the linked list.
     */
    function removeOrder(bytes32 _tradeId, uint256 _marketId){

          bytes32 flag = "BID";
    
          if (orders[_tradeId].typ == flag){
        
              if (markets[_marketId].highestBidId == _tradeId){
                markets[_marketId].highestBidId = markets[_marketId].bidOrderBook[_tradeId].nextId;
                bytes32 highest = markets[_marketId].highestBidId;
              }
              bytes32 nextId = markets[_marketId].bidOrderBook[_tradeId].nextId;
              bytes32 prev_id = markets[_marketId].bidOrderBook[_tradeId].prev_id;
        
              markets[_marketId].bidOrderBook[prev_id].nextId = nextId;
              markets[_marketId].bidOrderBook[nextId].prev_id = prev_id;
        
              markets[_marketId].bidOrderBook[_tradeId].id = 0;
              markets[_marketId].bidOrderBook[_tradeId].nextId = 0;
              markets[_marketId].bidOrderBook[_tradeId].prev_id = 0;
          } else {
              if (markets[_marketId].lowestAskId == _tradeId){
                  markets[_marketId].lowestAskId = markets[_marketId].askOrderBook[_tradeId].nextId;
                  bytes32 lowest = markets[_marketId].highestBidId;
              }
      
              prev_id = markets[_marketId].askOrderBook[_tradeId].prev_id;
              nextId = markets[_marketId].askOrderBook[_tradeId].nextId;
      
              markets[_marketId].askOrderBook[prev_id].nextId = nextId;
              markets[_marketId].askOrderBook[nextId].prev_id = prev_id;
      
              markets[_marketId].askOrderBook[_tradeId].id = 0;
              markets[_marketId].askOrderBook[_tradeId].nextId = 0;
              markets[_marketId].askOrderBook[_tradeId].prev_id = 0;
          }
    
          orders[_tradeId].typ = 0;
          orders[_tradeId].amount = 0;
          orders[_tradeId].price = 0;
          orders[_tradeId].marketId = 0;
          orders[_tradeId].id = 0;
          orders[_tradeId].sender = 0;
          orders[_tradeId].blockNumber = 0;
    }

    /* 
    Once the orders are saved based on the best prices and highest volumes, a simple iteration
    is all that is needed to match and settle orders. Settlement happens by directly sending
    Ether to the seller and modifying the users’ local token balances. The match function
    gets executed right after an order is newly submitted.
     */
    function matchOrders(uint256 _marketId) {

          bool bidMatched = false;
          bool askMatched = false;
          bytes32 bidIdIter = markets[_marketId].highestBidId;
          bytes32 askIdIter = markets[_marketId].lowestAskId;
          uint256 fill;
          uint256 payback;
          uint256 costs;
          bytes32 askIdIter_helper;
          bytes32 bidIdIter_helper;
      
          while(!bidMatched){
              if (orders[bidIdIter].amount == 0) return;
              bidMatched = true;
              while(!askMatched){
                if (orders[askIdIter].amount == 0) return;
                askMatched = true;
                if (orders[bidIdIter].price >= orders[askIdIter].price) {  
                bidMatched = false;
                if (orders[bidIdIter].amount > orders[askIdIter].amount){
                    fill =  orders[askIdIter].amount;
                    orders[bidIdIter].amount -= fill;
                    balances[orders[askIdIter].owner][_marketId].trading -= fill;
                    balances[orders[bidIdIter].owner][_marketId].available += fill;
                    costs = fill * orders[askIdIter].price * 10000000000000000;
                    payback = fill * (orders[bidIdIter].price - orders[askIdIter].price) * 10000000000000000;
                    if (!orders[askIdIter].owner.send(costs)) throw;
                  if (payback > 0){
                      if (!orders[bidIdIter].owner.send(payback)) throw;
                    }
                    askIdIter_helper = askIdIter;
                    askIdIter = markets[_marketId].askOrderBook[askIdIter].nextId;
                    removeOrder(askIdIter_helper,_marketId);
                    askMatched = false;
                  }
                  if (orders[bidIdIter].amount == orders[askIdIter].amount) {
                    fill =  orders[bidIdIter].amount;
                    balances[orders[askIdIter].owner][_marketId].trading -= fill;
                    balances[orders[bidIdIter].owner][_marketId].available += fill;
                    costs = fill * orders[askIdIter].price * 10000000000000000;
                    payback = fill * (orders[bidIdIter].price - orders[askIdIter].price) * 10000000000000000;
                    if (!orders[askIdIter].owner.send(costs)) throw;
                    if (payback > 0){
                      if (!orders[bidIdIter].owner.send(payback)) throw;
                    }
                    askIdIter_helper = askIdIter;
                    bidIdIter_helper = bidIdIter;
                    askIdIter = markets[_marketId].askOrderBook[askIdIter].nextId;
                    bidIdIter = markets[_marketId].bidOrderBook[bidIdIter].nextId;
                    removeOrder(askIdIter_helper,_marketId);
                    removeOrder(bidIdIter_helper,_marketId);
                  }
                  if (orders[bidIdIter].amount < orders[askIdIter].amount) {
                    fill =  orders[bidIdIter].amount;
                    orders[askIdIter].amount -= fill;
                    balances[orders[askIdIter].owner][_marketId].trading -= fill;
                    balances[orders[bidIdIter].owner][_marketId].available += fill;
                    costs = fill * orders[askIdIter].price * 10000000000000000;
                    payback = fill * (orders[bidIdIter].price - orders[askIdIter].price) * 10000000000000000;
                    if (!orders[askIdIter].owner.send(costs)) throw;
                    if (payback > 0){
                      if (!orders[bidIdIter].owner.send(payback)) throw;
                    }
                    bidIdIter_helper = bidIdIter;
                    bidIdIter = markets[_marketId].bidOrderBook[bidIdIter].nextId;
                    removeOrder(bidIdIter_helper,_marketId);
                  }
                }
              } 
          askMatched = false;
          }
    }
}
