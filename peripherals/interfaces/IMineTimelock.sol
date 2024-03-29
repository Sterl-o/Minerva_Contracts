// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IMineTimelock {
    function setAdmin(address _admin) external;
    function signalSetGov(address _target, address _gov) external;
}
