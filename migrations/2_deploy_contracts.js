const FlightFactory = artifacts.require("FlightFactory");

module.exports = function(deployer, network, accounts) {
  deployer.deploy(FlightFactory, accounts[0]);
};
