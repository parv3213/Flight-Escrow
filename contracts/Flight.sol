// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract Flight {
    using SafeMath for uint256;

    enum Status {noDispute, inDispute, settled}
    Flight.Status public status = Status.noDispute;

    uint256 public timestamp;
    uint256 public baseFare;
    uint256 public passengerLimit;
    uint256 public passengerCount;
    uint256 public delayLimit = 10800;
    uint256 public withdrawWait = 172800;
    uint256 public disputeFee;
    address payable public flightOwner;
    address payable public escrow;
    address payable public delayDisputeRaiser;
    bytes32 public departure;
    bytes32 public arrival;
    string public escrowDecisionReason;
    bool public shouldRefund = false;

    mapping(uint256 => Passenger) public passengers;

    struct Passenger {
        address passenger;
    }

    event PassengerAdded(address indexed passenger);
    event DelayDisputeRaised(address sender);
    event Withdrawal(address withdrawer, uint256 amount);

    modifier onlyFlightOwner {
        require(msg.sender == flightOwner, "Not authorized");
        _;
    }

    modifier noDispute {
        require(status == Status.noDispute, "Cannot withdraw, in dispute");
        _;
    }

    constructor(
        uint256 _timestamp,
        bytes32 _departure,
        bytes32 _arrival,
        uint256 _baseFare,
        uint256 _passengerLimit,
        address payable _escrow,
        uint256 _disputeFee
    ) public {
        flightOwner = msg.sender;
        timestamp = _timestamp;
        departure = _departure;
        arrival = _arrival;
        baseFare = _baseFare;
        passengerLimit = _passengerLimit;
        escrow = _escrow;
        disputeFee = _disputeFee;
    }

    function buyTicket(address[] calldata _passengers) external payable {
        require(
            passengerCount.add(_passengers.length) <= passengerLimit,
            "Passenger limit reached"
        );
        require(
            msg.value == baseFare.mul(_passengers.length),
            "Provide correct amount"
        );
        for (uint256 i = 0; i < _passengers.length; i++) {
            passengers[passengerCount] = Passenger({passenger: _passengers[i]});
            passengerCount = passengerCount.add(1);
            emit PassengerAdded(_passengers[i]);
        }
    }

    function flightDelayRaise() external payable {
        require(status == Status.noDispute, "Not allowed");
        require(now >= (timestamp + delayLimit), "Delay limit not reached");
        require(now <= timestamp + withdrawWait, "Dispute time up");
        require(msg.value == disputeFee, "Provide correct dispute fee");
        status = Status.inDispute;
        delayDisputeRaiser = msg.sender;
        emit DelayDisputeRaised(delayDisputeRaiser);
    }

    function escrowDecision(string calldata _reason, bool _shouldRefund)
        external
    {
        require(status == Status.inDispute, "Not in dispute");
        require(msg.sender == escrow, "Not authorized");
        escrowDecisionReason = _reason;
        shouldRefund = _shouldRefund;
        escrow.transfer(disputeFee);
        status = Status.settled;
    }

    function withdrawMoney() external onlyFlightOwner noDispute {
        require(
            now >= timestamp.add(withdrawWait),
            "Withdraw time not reached"
        );
        require(shouldRefund == false, "Cannot withdraw!");
        transferFund(flightOwner, address(this).balance);
        status = Status.settled;
    }

    function publicWithdraw() external {
        require(status == Status.settled, "Not settled");
        require(shouldRefund == true, "No refund");
        transferFund(msg.sender, baseFare);
    }

    function claimDelayRaise() external {
        require(shouldRefund == true, "Not eligible");
        transferFund(delayDisputeRaiser, disputeFee);
    }

    function transferFund(address payable _to, uint256 _amount) internal {
        _to.transfer(_amount);
        emit Withdrawal(_to, _amount);
    }
}
