pragma solidity 0.8.1;
// SPDX-License-Identifier: UNLICENSED

import "./Flight.sol";

contract FlightFactory {
    uint256 public flightCount;
    address payable public escrow;
    mapping(uint256 => address) public flights;

    event FlightAdded(address indexed flightAddress, address indexed owner);

    constructor(address payable _escrow) {
        escrow = _escrow;
    }

    function addFlight(
        uint256 _timestamp,
        bytes32 _departure,
        bytes32 _arrival,
        uint256 _baseFare,
        uint256 _passengerLimit
    ) external payable {
        require(msg.value == _baseFare / 2, "Provide correct dispute fee");
        Flight _flight =
            new Flight(
                _timestamp,
                _departure,
                _arrival,
                _baseFare,
                _passengerLimit,
                escrow,
                msg.sender
            );
        flights[flightCount] = address(_flight);
        flightCount = flightCount+1;
        payable(flights[flightCount]).transfer(msg.value);
        emit FlightAdded(flights[flightCount], msg.sender);
    }
}
