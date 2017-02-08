
contract DSX {
    
    Market[] markets;

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
    struct OrderId{
      bytes32 id;
      bytes32 nextId;
      bytes32 prev_id;
    }
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
    struct LocalBalance {
      uint256 available;
      uint256 trading;
    }
    mapping (bytes32 => Order) orders;
    mapping (address => mapping (uint256 => LocalBalance)) public balances;
    uint256 public nextbidIdIter = 0;
    Token currentToken;
    uint256[] bidPrice;
    uint256[] bidVol;
    uint256[] askPrice;
    uint256[] askVol;

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

    function registerToken(address _addr, bytes32 _name) {
          markets.push(Market(nextbidIdIter,_name,_addr,1,msg.sender,block.number,0,0));
          nextbidIdIter +=1;
          currentToken = Token(_addr);
    }


    function deposit(uint256 _amount,uint256 _marketId) {
          currentToken = Token(markets[_marketId].addr);
          if (currentToken.transferFrom(msg.sender, this, _amount)){
            uint256 balance = balances[msg.sender][_marketId].available;
            balance = balance + _amount;
            balances[msg.sender][_marketId].available = balance;
          }
    }

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


    function buy(uint256 _amount, uint256 _price, uint256 _marketId) payable {
          uint256 rv;
          if (!checkOrder(_amount, _price, _marketId)) throw;
          rv = ((_amount*_price) * 10000000000000000);
          if (msg.value < rv) throw;
          if (msg.value >= rv){
          msg.sender.send(msg.value - rv);
          }
          saveOrder("BID",_amount,_price,_marketId);
          matchOrders(_marketId);
    }


    function sell(uint256 _amount, uint256 _price, uint256 _marketId){
          if (!checkOrder(_amount, _price, _marketId)) throw;
          uint256 balance = balances[msg.sender][_marketId].available;
          if (balance > _amount){
            saveOrder("ASK",_amount,_price,_marketId);
          }
          matchOrders(_marketId);
    }


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
                    orders[askIdIter].owner.send(costs);
                  if (payback > 0){
                      orders[bidIdIter].owner.send(payback);
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
                    orders[askIdIter].owner.send(costs);
                    if (payback > 0){
                      orders[bidIdIter].owner.send(payback);
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
                    orders[askIdIter].owner.send(costs);
                    if (payback > 0){
                      orders[bidIdIter].owner.send(payback);
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

  /*
  Token Standard (without any additional functionality) Source: https://github.com/ethereum/EIPs/issues/20
  */
    contract Token {

      address public token = this;

      event Transfer(address indexed _from, address indexed _to, uint256 _value);
      event Approval(address indexed _owner, address indexed _spender, uint256 _value);

        function transfer(address _to, uint256 _value) returns (bool success) {
            //Default assumes totalSupply can't be over max (2^256 - 1).
            //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
            //Replace the if with this one instead.
            //if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            if (balances[msg.sender] >= _value && _value > 0) {
                balances[msg.sender] -= _value;
                balances[_to] += _value;
                Transfer(msg.sender, _to, _value);
                return true;
            } else { return false; }
        }

        function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
            //same as above. Replace this line with the following if you want to protect against wrapping uints.
            //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
                balances[_to] += _value;
                balances[_from] -= _value;
                allowed[_from][msg.sender] -= _value;
                //Transfer(_from, _to, _value);
                return true;
            } else { return false; }
        }

        function balanceOf(address _owner) constant returns (uint256 balance) {
            return balances[_owner];
        }

        function approve(address _spender, uint256 _value) returns (bool success) {
            allowed[msg.sender][_spender] = _value;
            Approval(msg.sender, _spender, _value);
            return true;
        }

        function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
          return allowed[_owner][_spender];
        }

        mapping (address => uint256) public balances;
        mapping (address => mapping (address => uint256)) public allowed;
        uint256 public totalSupply;



        /* Public variables of the token */

        /*
        NOTE:
        The following variables are OPTIONAL vanities. One does not have to include them.
        They allow one to customise the token contract & in no way influences the core functionality.
        Some wallets/interfaces might not even bother to look at this information.
        */
        string public name;                   //fancy name: eg Simon Bucks
        uint8 public decimals;                //How many decimals to show. ie. There could 1000 base units with 3 decimals. Meaning 0.980 SBX = 980 base units. It's like comparing 1 wei to 1 ether.
        string public symbol;                 //An identifier: eg SBX
        string public version = 'H0.1';       //human 0.1 standard. Just an arbitrary versioning scheme.

        function Token() {
            balances[msg.sender] = 100000;               // Give the creator all initial tokens
            totalSupply = 100000;                        // Update total supply
            name = "DSX_token";
        }

    }
