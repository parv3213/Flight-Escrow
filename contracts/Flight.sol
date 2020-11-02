// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract Flight {
    using SafeMath for uint256;

    enum Status {noDispute, inDispute, settled}
    Flight.Status public status = Status.noDispute;

    uint256 public timestamp;
    uint256 public baseFare;
    uint256 public passengerLimit;
    uint256 public delayLimit = 10800;
    uint256 public withdrawWait = 172800;
    uint256 public disputeFee;
    address payable public flightOwner;
    address payable public escrow;
    bytes32 public departure;
    bytes32 public arrival;

    uint256 public passengerCount;
    address payable public delayDisputeRaiser;
    string public escrowDecisionReason;
    bool public shouldRefund = false;

    mapping(uint256 => Passenger) public passengers;

    struct Passenger {
        address payable buyer;
        string passengerName;
        bool refunded;
    }

    event PassengerAdded(address indexed buyer, string passengerName);
    event DelayDisputeRaised(address sender);
    event Withdrawal(address withdrawer, uint256 amount);

    modifier noDispute {
        require(status != Status.inDispute, "In dispute");
        _;
    }
    
    receive() external payable{}

    constructor(
        uint256 _timestamp,
        bytes32 _departure,
        bytes32 _arrival,
        uint256 _baseFare,
        uint256 _passengerLimit,
        address payable _escrow,
        address payable _flightOwner
    ) public {
        flightOwner = _flightOwner;
        timestamp = _timestamp;
        departure = _departure;
        arrival = _arrival;
        baseFare = _baseFare;
        passengerLimit = _passengerLimit;
        escrow = _escrow;
        disputeFee = _baseFare/2;
    }

    function buyTicket(address payable _buyer, string calldata _passengerName) external payable {
        require(msg.value == baseFare, "Provide correct amount");
        passengers[passengerCount] = Passenger({buyer: _buyer, passengerName: _passengerName, refunded: false});
        passengerCount = passengerCount.add(1);
        emit PassengerAdded(_buyer, _passengerName);
    }

    function flightDelayRaise() external payable {
        require(status == Status.noDispute, "Not allowed");
        require(now >= (timestamp.add(delayLimit)), "Delay limit not reached");
        require(now <= timestamp.add(withdrawWait), "Dispute time up");
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

    function withdrawMoney() external noDispute {
        require(
            now >= timestamp.add(withdrawWait),
            "Withdraw time not reached"
        );
        require(shouldRefund == false, "Cannot withdraw");
        transferFund(flightOwner, address(this).balance);
        status = Status.settled;
    }

    function publicWithdraw() external {
        require(status == Status.settled, "Not settled");
        require(shouldRefund == true, "No refund");
        for(uint256 i = 0; i < passengerCount; i++){
            if (passengers[i].buyer == msg.sender){
                require(passengers[i].refunded == false, "Already claimed the fund");
                passengers[i].refunded = true;
                transferFund(msg.sender, baseFare);
            }
        }
        
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
