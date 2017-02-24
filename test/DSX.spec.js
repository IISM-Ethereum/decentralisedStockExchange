'use strict';

const co = require('co');
const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
const expect = chai.expect;
chai.use(chaiAsPromised);
const assert = require("assert");

const eth = web3.eth;

var dsx;
var token;
var marketID;

contract('DSX', function(accounts) {


    describe("First things first", function() {

        beforeEach(function() {
            return co(function*() {
                eth.defaultAccount = accounts[0];
                dsx = yield DSX.new();
                token = yield Token.new();
                marketID = (yield dsx.nextMarketID()).toNumber();
            });
        });


        it('The DSX contract should be deployed to the blockchain', function(done) {
            assert(dsx);
            //console.log("dsx contract has address:", dsx.address);
            done();
        });

        it('The Token contract should be deployed to the blockchain', function(done) {
            assert(token);
            //console.log("token contract has address:", token.address);
            done();
        });
    });

    describe("Register new token contract with the exchange contract", function() {

        before(function() {
            return co(function*() {
                eth.defaultAccount = accounts[0];
                dsx = yield DSX.new();
                token = yield Token.new();
                marketID = (yield dsx.nextMarketID()).toNumber();
            });
        });

        it('Market struct should be created for Token', function() {
            return co(function*() {
                yield dsx.registerToken(token.address, 'myTestToken');
                var addr = yield dsx.getLastTokenAddress();
                assert.equal(addr, token.address);
            })
        });

        it('should be possible to assign 1000 tokens to the exchange contract', function() {
            return co(function*() {

                yield token.approve(dsx.address, 1000);
                let allowed = (yield token.allowance(eth.accounts[0], dsx.address)).toNumber();
                assert.equal(1000, allowed);
                yield dsx.deposit(1000, marketID);
                let balance = (yield dsx.getAvailableBalance(marketID)).toNumber();
                assert.equal(1000, balance, "exchange contract did not get assigned 1000 tokens");
            })
        });

    });


    describe("Trading Functionality", function() {

        beforeEach(function() {
            return co(function*() {
                eth.defaultAccount = accounts[0];
                dsx = yield DSX.new();
                token = yield Token.new();
                marketID = (yield dsx.nextMarketID()).toNumber();
                yield dsx.registerToken(token.address, 'myTestToken');
                yield token.approve(dsx.address, 1000);
                yield dsx.deposit(1000, marketID);
            });
        });

        it('should be possible to emit a buy order', function() {
            return co(function*() {
                yield dsx.buy(1, 1, marketID, { from: eth.accounts[1], value: web3.toWei(10) });
                let orders = yield dsx.getBidOrders(marketID);
                let price = orders[0][0].toNumber();
                let volume = orders[1][0].toNumber();
                assert(price, 1);
                assert(volume, 1);
            })
        });

        it('should not be possible to emit a buy order when not enough money is attached', function() {
            return expect(co(function*() {
                yield dsx.buy(1, 1, marketID, { from: eth.accounts[1], value: 1 });
                let orders = yield dsx.getBidOrders(marketID);
                let price = orders[0][0].toNumber();
                let volume = orders[1][0].toNumber();
                assert(price, 1);
                assert(volume, 1);
            })).to.be.rejected;
        });

        it('should be possible to emit a sell order', function() {
            return co(function*() {
                yield dsx.sell(1, 1, marketID);
                let orders = yield dsx.getAskOrders(marketID);
                let price = orders[0][0].toNumber();
                let volume = orders[1][0].toNumber();
                assert(price, 1);
                assert(volume, 1);
            })
        });


        it('ask order gets fulfilled partly', function() {
            return co(function*() {
                yield dsx.buy(1, 1, marketID, { from: eth.accounts[1], value: web3.toWei(10) });
                yield dsx.sell(10, 1, marketID);
                let askOrders = yield dsx.getAskOrders(marketID);
                let volume = askOrders[1][0].toNumber();
                assert(volume, 9);
            })
        });

        it('bid order gets fulfilled partly', function() {
            return co(function*() {
                yield dsx.buy(10, 1, marketID, { from: eth.accounts[1], value: web3.toWei(10) });
                yield dsx.sell(1, 1, marketID);
                let bidOrders = yield dsx.getBidOrders(marketID);
                let volume = bidOrders[1][0].toNumber();
                assert(volume, 9);
            })
        });

        it('ask order fulfills all bid orders and some ask orders are left', function() {
            return co(function*() {
                yield dsx.buy(5, 1, marketID, { from: eth.accounts[1], value: web3.toWei(10) });
                yield dsx.sell(10, 1, marketID);
                let bidOrders = yield dsx.getBidOrders(marketID);
                assert(bidOrders[1][0] == undefined);
                let askOrders = yield dsx.getAskOrders(marketID);
                let askvolume = askOrders[1][0].toNumber();
                assert(askvolume, 5);
            })
        });


        it('bid order fulfills all ask orders and some bid orders are left', function() {
            return co(function*() {
                yield dsx.buy(10, 1, marketID, { from: eth.accounts[1], value: web3.toWei(20) });
                yield dsx.sell(5, 1, marketID);
                let askOrders = yield dsx.getAskOrders(marketID);
                assert(askOrders[1][0] == undefined);
                let bidOrders = yield dsx.getBidOrders(marketID);
                let bidVolume = bidOrders[1][0].toNumber();
                assert(bidVolume, 5);
            })
        });

        it('ask order fulfills a few bid orders', function() {
            return co(function*() {
                yield dsx.buy(10, 1, marketID, { from: eth.accounts[1], value: web3.toWei(20) });
                yield dsx.sell(5, 1, marketID);
                let askOrders = yield dsx.getAskOrders(marketID);
                assert(askOrders[1][0] == undefined);
                let bidOrders = yield dsx.getBidOrders(marketID);
                let bidVolume = bidOrders[1][0].toNumber();
                assert(bidVolume, 5);
            })
        });

    });

})
