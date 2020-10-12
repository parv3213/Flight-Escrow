// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

import "./Flight.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract FlightFactory {
    using SafeMath for uint256;

    uint256 public flightCount;
    address payable public escrow;

    mapping(uint256 => FlightInfo) public flights;

    struct FlightInfo {
        address flight;
    }

    event FlightAdded(address indexed flightAddress);

    constructor(address payable _escrow) public {
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
        Flight _flight = new Flight(
            _timestamp,
            _departure,
            _arrival,
            _baseFare,
            _passengerLimit,
            escrow,
            msg.sender
        );
        address(_flight).transfer(msg.value);
        flights[flightCount] = FlightInfo({flight: address(_flight)});
        flightCount = flightCount.add(1);
        emit FlightAdded(address(_flight));
    }
}