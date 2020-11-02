const FlightFactory = artifacts.require("FlightFactory.sol");
const Flight = artifacts.require("Flight.sol");
const { assert } = require("chai");
const { expectRevert } = require("@openzeppelin/test-helpers");
const { time } = require("@openzeppelin/test-helpers");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");

let ff; //flightFactory contract instance
let f; //flight contract instance
let timestamp;
const departure = web3.utils.keccak256("Delhi");
const arrival = web3.utils.keccak256("Mumbai");
const baseFare = web3.utils.toWei("0.1", "ether");
const disputeFee = baseFare / 2;
const passengerLimit = 5;

contract("FlightFactory", ([escrow, flightOwner]) => {
    before(async () => {
        timestamp = parseInt(await time.latest()) + 24 * 60 * 60;
        ff = await FlightFactory.deployed();
    });
    it("Check initial parameters", async () => {
        assert.equal(parseFloat(await ff.flightCount()), 0);
        assert.equal(await ff.escrow(), escrow);
    });
    it("Add a flight", async () => {
        await expectRevert(
            ff.addFlight(timestamp, departure, arrival, baseFare, passengerLimit, {
                from: flightOwner,
            }),
            "Provide correct dispute fee"
        ); // Correct value not provided
        const receipt = await ff.addFlight(timestamp, departure, arrival, baseFare, passengerLimit, {
            from: flightOwner,
            value: disputeFee,
        });
        assert.equal(receipt.logs[0].event, "FlightAdded");
        assert.equal(receipt.logs[0].args[0], await ff.flights(0));
        assert.equal(parseFloat(await ff.flightCount()), 1);
        assert.equal(parseFloat(await web3.eth.getBalance(receipt.logs[0].args[0])), baseFare / 2);
        assert.equal(parseFloat(await web3.eth.getBalance(ff.address)), 0);
    });
});

contract("Flight", ([escrow, flightOwner, passenger1, passenger2, passenger3, account]) => {
    before(async () => {
        timestamp = parseInt(await time.latest()) + 24 * 60 * 60;
        ff = await FlightFactory.deployed();
        const receipt = await ff.addFlight(timestamp, departure, arrival, baseFare, passengerLimit, {
            from: flightOwner,
            value: disputeFee,
        });
        const flightAddress = receipt.logs[0].args[0];
        f = await Flight.at(flightAddress);
    });
    it("Check parameters", async () => {
        assert.equal(parseFloat(await f.status()), 0);
        assert.equal(parseFloat(await f.timestamp()), timestamp);
        assert.equal(parseFloat(await f.baseFare()), baseFare);
        assert.equal(parseFloat(await f.disputeFee()), disputeFee);
        assert.equal(parseFloat(await f.delayLimit()), 10800);
        assert.equal(parseFloat(await f.withdrawWait()), 172800);
        assert.equal(await f.flightOwner(), flightOwner);
        assert.equal(await f.escrow(), escrow);
        assert.equal(await f.departure(), departure);
        assert.equal(await f.arrival(), arrival);
        assert.equal(parseFloat(await f.passengerCount()), 0);
        assert.equal(await f.delayDisputeRaiser(), "0x0000000000000000000000000000000000000000");
        assert.equal(await f.escrowDecisionReason(), 0);
        assert.equal(await f.shouldRefund(), false);
        assert.equal(parseFloat(await web3.eth.getBalance(ff.address)), 0);
        assert.equal(parseFloat(await web3.eth.getBalance(f.address)), 0.5 * baseFare);
    });
    it("Buy tickets", async () => {
        await expectRevert(f.buyTicket(passenger1, "Stuart Little"), "Provide correct amount");
        const receipt = await f.buyTicket(passenger1, "Stuart Little", { from: passenger1, value: baseFare });
        const { buyer, passengerName, refunded } = await f.passengers(0);
        assert.equal(buyer, passenger1);
        assert.equal(passengerName, "Stuart Little");
        assert.equal(refunded, false);
        assert.equal(parseFloat(await f.passengerCount()), 1);
        assert.equal(receipt.logs[0].event, "PassengerAdded");
        assert.equal(receipt.logs[0].args[0], passenger1);
        assert.equal(receipt.logs[0].args[1], "Stuart Little");
        await f.buyTicket(passenger2, "Wonder Women", { from: passenger2, value: baseFare });
        await f.buyTicket(passenger3, "Spider Man", { from: passenger3, value: baseFare });
        assert.equal(parseFloat(await f.passengerCount()), 3);
        assert.equal(parseFloat(await web3.eth.getBalance(f.address)), 3.5 * baseFare);
    });
    it("Flight owner withdraws money", async () => {
        await expectRevert(f.escrowDecision("Passenger must get a refund", true, { from: escrow }), "Not in dispute");
        await expectRevert(f.publicWithdraw({ from: passenger1 }), "Not settled");
        await expectRevert(f.claimDelayRaise(), "Not eligible");
        await expectRevert(f.withdrawMoney(), "Withdraw time not reached");
        await time.increaseTo(timestamp + 172800);
        const oldFlightOwnerBalance = parseFloat(await web3.eth.getBalance(flightOwner));
        const receipt = await f.withdrawMoney();
        assert.equal(receipt.logs[0].event, "Withdrawal");
        assert.equal(parseFloat(receipt.logs[0].args.amount), parseFloat(web3.utils.toWei("0.35")));
        const newFlightOwnerBalance = parseFloat(await web3.eth.getBalance(flightOwner));
        assert.equal(newFlightOwnerBalance - oldFlightOwnerBalance, parseFloat(web3.utils.toWei("0.35")));
        assert.equal(parseFloat(await f.status()), 2);
    });
});

// Dispute raised but shouldRefund = false
contract("Flight", ([escrow, flightOwner, passenger1, passenger2, passenger3, account]) => {
    before(async () => {
        timestamp = parseInt(await time.latest()) + 24 * 60 * 60;
        ff = await FlightFactory.deployed();
        const receipt = await ff.addFlight(timestamp, departure, arrival, baseFare, passengerLimit, {
            from: flightOwner,
            value: disputeFee,
        });
        const flightAddress = receipt.logs[0].args[0];
        f = await Flight.at(flightAddress);
    });
    it("Create a new flight and raise false dispute", async () => {
        await f.buyTicket(passenger1, "Stuart Little", { from: passenger1, value: baseFare });
        await f.buyTicket(passenger2, "Wonder Women", { from: passenger2, value: baseFare });
        await f.buyTicket(passenger3, "Spider Man", { from: passenger3, value: baseFare });
        await expectRevert(f.flightDelayRaise(), "Delay limit not reached");
        await time.increaseTo(timestamp + 10800);
        await expectRevert(f.flightDelayRaise(), "Provide correct dispute fee");
        const receipt = await f.flightDelayRaise({value: disputeFee});
        assert.equal(parseFloat(await f.status()), 1);
        assert.equal(await f.delayDisputeRaiser(), escrow);
        assert.equal(receipt.logs[0].event, "DelayDisputeRaised");
        assert.equal(receipt.logs[0].args[0], escrow);
        await expectRevert(f.flightDelayRaise(), "Not allowed");       
    });
    it("Escrow makes the decision", async () => {
        await  expectRevert(f.escrowDecision("As per our data the flight took off at right time",false, {from: flightOwner}), "Not authorized");
        await f.escrowDecision("As per our data the flight took off at right time", false);
        assert.equal(await f.escrowDecisionReason(), "As per our data the flight took off at right time")
        assert.equal(await f.shouldRefund(), false);
        assert.equal(parseFloat(await f.status()), 2);
    })
    it("Public should NOT be able to withdraw", async() => {
        await expectRevert(f.publicWithdraw(), "No refund")
    })
    it("Delay claim raise should NOT be able to claim", async() => {
        await expectRevert(f.claimDelayRaise(), "Not eligible");
    })
    it("Flight owner can withdraw money", async() => {
        await time.increaseTo(timestamp + 172800);
        const oldFlightOwnerBalance = parseFloat(await web3.eth.getBalance(flightOwner));
        await f.withdrawMoney();
        const newFlightOwnerBalance = parseFloat(await web3.eth.getBalance(flightOwner));
        assert.equal(newFlightOwnerBalance - oldFlightOwnerBalance, parseFloat(web3.utils.toWei("0.35")));
        assert.equal(parseFloat(await f.status()), 2);
    })
});

// Dispute raised but shouldRefund = true
contract("Flight", ([escrow, flightOwner, passenger1, passenger2, passenger3, account]) => {
    before(async () => {
        timestamp = parseInt(await time.latest()) + 24 * 60 * 60;
        ff = await FlightFactory.deployed();
        const receipt = await ff.addFlight(timestamp, departure, arrival, baseFare, passengerLimit, {
            from: flightOwner,
            value: disputeFee,
        });
        const flightAddress = receipt.logs[0].args[0];
        f = await Flight.at(flightAddress);
    });
    it("Create a new flight and raise false dispute", async () => {
        await f.buyTicket(passenger1, "Stuart Little", { from: passenger1, value: baseFare });
        await f.buyTicket(passenger2, "Wonder Women", { from: passenger2, value: baseFare });
        await f.buyTicket(passenger3, "Spider Man", { from: passenger3, value: baseFare });
        await expectRevert(f.flightDelayRaise(), "Delay limit not reached");
        await time.increaseTo(timestamp + 10800);
        await expectRevert(f.flightDelayRaise(), "Provide correct dispute fee");
        const receipt = await f.flightDelayRaise({value: disputeFee});
        assert.equal(parseFloat(await f.status()), 1);
        assert.equal(await f.delayDisputeRaiser(), escrow);
        assert.equal(receipt.logs[0].event, "DelayDisputeRaised");
        assert.equal(receipt.logs[0].args[0], escrow);
        await expectRevert(f.flightDelayRaise(), "Not allowed");    
        await expectRevert(f.withdrawMoney({from: flightOwner}), "In dispute");
    });
    it("Escrow makes the decision", async () => {
        await  expectRevert(f.escrowDecision("As per our data the flight took off late. So should refund to passengers",true, {from: flightOwner}), "Not authorized");
        await f.escrowDecision("As per our data the flight took off late. So should refund to passengers", true);
        assert.equal(await f.escrowDecisionReason(), "As per our data the flight took off late. So should refund to passengers")
        assert.equal(await f.shouldRefund(), true);
        assert.equal(parseFloat(await f.status()), 2);
    })
    it("Flight owner can NOT withdraw money", async() => {
        await time.increaseTo(timestamp + 172800);
        const oldFlightOwnerBalance = parseFloat(await web3.eth.getBalance(flightOwner));
        await expectRevert(f.withdrawMoney(), "Cannot withdraw");
        const newFlightOwnerBalance = parseFloat(await web3.eth.getBalance(flightOwner));
        assert.equal(newFlightOwnerBalance - oldFlightOwnerBalance, parseFloat(web3.utils.toWei("0")));
        assert.equal(parseFloat(await f.status()), 2);
    })
    it("Public should be able to withdraw", async() => {
        const oldPassenger1Balance = parseFloat(await web3.eth.getBalance(passenger1));
        await f.publicWithdraw({from: passenger1});
        const newPassenger1Balance = parseFloat(await web3.eth.getBalance(passenger1));
        assert.equal( parseFloat(web3.utils.fromWei(String(newPassenger1Balance-oldPassenger1Balance))).toFixed(5) , parseFloat(web3.utils.fromWei(baseFare)).toFixed(5) );

        const oldPassenger2Balance = parseFloat(await web3.eth.getBalance(passenger2));
        await f.publicWithdraw({from: passenger2});
        const newPassenger2Balance = parseFloat(await web3.eth.getBalance(passenger2));
        assert.equal((parseFloat(web3.utils.fromWei(String(newPassenger2Balance - oldPassenger2Balance)))).toFixed(5), parseFloat(web3.utils.fromWei(baseFare)).toFixed(5) );

        const oldPassenger3Balance = parseFloat(await web3.eth.getBalance(passenger3));
        await f.publicWithdraw({from: passenger3});
        const newPassenger3Balance = parseFloat(await web3.eth.getBalance(passenger3));
        assert.equal((parseFloat(web3.utils.fromWei(String(newPassenger3Balance - oldPassenger3Balance)))).toFixed(5), parseFloat(web3.utils.fromWei(baseFare)).toFixed(5) );

        await expectRevert(f.publicWithdraw({from: passenger3}), "Already claimed the fund");
    })
    it("Delay claim raise should be able to claim", async() => {
        const oldDisputerBalance = parseFloat(await web3.eth.getBalance(escrow));
        await f.claimDelayRaise();
        const newDisputerBalance = parseFloat(await web3.eth.getBalance(escrow));
        assert.equal((parseFloat(web3.utils.fromWei(String(newDisputerBalance - oldDisputerBalance)))).toFixed(5), parseFloat(parseFloat(web3.utils.fromWei(baseFare))*0.5).toFixed(5) );
    })
});

// Dispute raised cannot be raised after 
contract("Flight", ([escrow, flightOwner, passenger1, passenger2, passenger3, account]) => {
    before(async () => {
        timestamp = parseInt(await time.latest()) + 24 * 60 * 60;
        ff = await FlightFactory.deployed();
        const receipt = await ff.addFlight(timestamp, departure, arrival, baseFare, passengerLimit, {
            from: flightOwner,
            value: disputeFee,
        });
        const flightAddress = receipt.logs[0].args[0];
        f = await Flight.at(flightAddress);
    });
    it("Create a new flight and raise false dispute", async () => {
        await f.buyTicket(passenger1, "Stuart Little", { from: passenger1, value: baseFare });
        await f.buyTicket(passenger2, "Wonder Women", { from: passenger2, value: baseFare });
        await f.buyTicket(passenger3, "Spider Man", { from: passenger3, value: baseFare });
        await time.increaseTo(timestamp + 172801);
        await expectRevert(f.flightDelayRaise({value: disputeFee}), "Dispute time up");
    });
});