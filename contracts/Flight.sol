pragma solidity 0.8.1;
// SPDX-License-Identifier: UNLICENSED

// ! remove dispute fee
contract Flight {

    /// DATA STRUCTURES ///
    struct Passenger {
        address buyer;
        string passengerName;
        bool refunded;
    }
    enum Status {noDispute, inDispute, settled}

    /// CONSTANT PARAMETERS ///
    uint256 public constant delayLimit = 10800; //3 hr
    uint256 public constant withdrawWait = 172800; //4 days
    
    /// CONSTRUCTOR PARAMETERS ///
    uint256 public timestamp;
    uint256 public baseFare;
    uint256 public passengerLimit;
    uint256 public disputeFee;
    address public flightOwner;
    address public escrow;
    bytes32 public departure;
    bytes32 public arrival;

    /// FLIGHT DYNAMIC VARIABLE ///
    uint256 public passengerCount; //will start from 1
    address public delayDisputeRaiser;
    bool public deplayMoneyClaimed;
    string public escrowDecisionReason;
    bool public shouldRefund;
    Flight.Status public status = Status.noDispute;
    mapping(uint256 => Passenger) public passengers;

    /// EVENTS ///
    event PassengerAdded(address indexed buyer, string indexed passengerName);
    event DelayDisputeRaised(address indexed sender);
    event Withdrawal(address indexed withdrawer, uint256 amount);

    modifier noDispute {
        require(status != Status.inDispute, "In dispute");
        _;
    }

    receive() external payable {}

    constructor(
        uint256 _timestamp,
        bytes32 _departure,
        bytes32 _arrival,
        uint256 _baseFare,
        uint256 _passengerLimit,
        address _escrow,
        address _flightOwner
    ) {
        timestamp = _timestamp;
        departure = _departure;
        arrival = _arrival;
        baseFare = _baseFare;
        passengerLimit = _passengerLimit;
        escrow = _escrow;
        flightOwner = _flightOwner;
        disputeFee = _baseFare / 2;
    }

    function buyTicket(string calldata _passengerName)
        external
        payable
    {
        require(msg.value == baseFare, "Provide correct amount");
        passengerCount = passengerCount++;
        passengers[passengerCount] = Passenger({
            buyer: msg.sender,
            passengerName: _passengerName,
            refunded: false
        });
        emit PassengerAdded(msg.sender, _passengerName);
    }

    function flightDelayRaise() external payable {
        require(status == Status.noDispute, "Not allowed");
        require(block.timestamp >= timestamp + delayLimit, "Delay limit not reached");
        require(block.timestamp <= timestamp + withdrawWait, "Dispute time up");
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
        payable(escrow).transfer(disputeFee/2); // escrow gets half of dispute fee
        status = Status.settled;
    }

    function withdrawMoney() external noDispute {
        require(
            block.timestamp >= timestamp + withdrawWait,
            "Withdraw time not reached"
        );
        require(!shouldRefund, "Cannot withdraw");
        transferFund(flightOwner, address(this).balance);
        status = Status.settled;
    }

    function publicWithdraw() external {
        require(status == Status.settled, "Not settled");
        require(shouldRefund, "No refund");
        for(uint256 i = 0; i < passengerCount; i++){
            if (passengers[i].buyer == msg.sender){
                require(passengers[i].refunded == false, "Already claimed the fund");
                passengers[i].refunded = true;
                transferFund(msg.sender, baseFare);
            }
        }
    }

    function claimDelayRaise() external {
        require(shouldRefund && !deplayMoneyClaimed, "Not eligible");
        deplayMoneyClaimed = true;
        transferFund(delayDisputeRaiser, 2*disputeFee);
    }

    function transferFund(address _to, uint256 _amount) internal {
        payable(_to).transfer(_amount);
        emit Withdrawal(_to, _amount);
    }

    function buyerDetails(address _buyer) public view returns(bytes[] memory){
        bytes[] memory _buyerDetails;
        uint256 _buyerBookingCount;
        for (uint256 i = 0; i < passengerCount; i++){
            if (passengers[i].buyer == _buyer) {
                _buyerDetails[_buyerBookingCount] = abi.encodePacked(i, passengers[i].passengerName, passengers[i].refunded);
                _buyerBookingCount++;
            }
        }
        return _buyerDetails;
    }
}
