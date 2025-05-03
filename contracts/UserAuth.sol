// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract UserAuth {
    mapping(address => bool) private registeredUsers;
    event UserRegistered(address indexed user);
    event UserLoggedIn(address indexed user);

    function register() public {
        require(!registeredUsers[msg.sender], "User already registered");
        registeredUsers[msg.sender] = true;
        emit UserRegistered(msg.sender);
    }

    function isRegistered(address user) public view returns (bool) {
        return registeredUsers[user];
    }

    function login() public {
        require(registeredUsers[msg.sender], "User not registered");
        emit UserLoggedIn(msg.sender);
    }
}