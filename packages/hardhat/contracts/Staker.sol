// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "hardhat/console.sol";
import "./ExampleExternalContract.sol";

contract Staker {

  // External contract to handle stacked funds
  ExampleExternalContract public exampleExternalContract;

  // Mapping of addresses to staked funds (in wei)
  mapping (address => uint256) public balances;

  // Staking threshold
  uint256 public constant threshold = 1 ether;

  // Deadline for staking
  uint256 public deadline = block.timestamp + 30 seconds;

  // Boolean to track whether withdrawals can begin
  bool private openForWithdraw = false;

  // Boolean for reentrancy guard
  bool private locked = false;

  // Boolean to track whether execution was successful
  bool private hasExecuted = false;

  // Event for staking an amount
  event Stake(address indexed _contributor, uint256 _amount);

  constructor(address exampleExternalContractAddress) public {
      exampleExternalContract = ExampleExternalContract(exampleExternalContractAddress);
  }

  modifier onlyAfterDeadline {
    require(block.timestamp >= deadline, "Must be after deadline!");
    _;
  }

  modifier onlyBeforeDeadline {
    require(block.timestamp < deadline, "Must be before deadline!");
    _;
  }

  modifier stakeNotCompleted() {
    bool isExtContractCompleted = exampleExternalContract.completed();
    require(!isExtContractCompleted, "External contract and staking process are already completed!");
    _;
  }

  modifier reentrancyGuard() {
    require(!locked, "Reentrancy guard is in place...");
    locked = true;
    _;
    locked = false;
  }

  // Collect funds in a payable `stake()` function and track individual `balances` with a mapping:
  // ( make sure to add a `Stake(address,uint256)` event and emit it for the frontend <List/> display )
  function stake() public payable onlyBeforeDeadline {
    balances[msg.sender] += msg.value;
    emit Stake(msg.sender, msg.value);
  }

  // After some `deadline` allow anyone to call an `execute()` function
  // It should either call `exampleExternalContract.complete{value: address(this).balance}()` to send all the value
  function execute() external onlyAfterDeadline stakeNotCompleted {
    require(!hasExecuted, "Execute function can only be called once!");
    hasExecuted = true;

    if (address(this).balance >= threshold) {
      exampleExternalContract.complete{value: address(this).balance}();
      // if the `threshold` was not met, allow everyone to call a `withdraw()` function
    } else {
      openForWithdraw = true;
    }
  }

  // Add a `withdraw()` function to let users withdraw their balance
  // We need a reentrancy guard because if someone withdraws the balance to another malicious contract,
  // triggering the malicious contract's fallback/receive function, the malicious function could call 
  // this withdraw function again before the balance of its address is set to 0 (balances[msg.sender] = 0) 
  function withdraw() public payable onlyAfterDeadline stakeNotCompleted reentrancyGuard {
    require(openForWithdraw, "Not open for withdrawal...");
    require(balances[msg.sender] > 0, "No balance to withdraw for this user.");

    (bool sent, ) = msg.sender.call{value: balances[msg.sender]}("");
    require(sent, "Failed to withdraw staked ether!");

    balances[msg.sender] = 0;
  }

  // Add a `timeLeft()` view function that returns the time left before the deadline for the frontend
  function timeLeft() external view returns (uint256) {
    if (block.timestamp >= deadline) {
      return 0;
    }
    return deadline - block.timestamp;
  }

  // Add the `receive()` special function that receives eth and calls stake()
  // This is like a fallback to make sure eth is used properly
  // (in fact, before solidity 0.6.0 it was part of the fallback fn)
  receive() external payable {
    stake();
  }

}
