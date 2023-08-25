//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFlashBot {
    
    struct OrderedReserves {
    uint256 tokenA1; 
    uint256 tokenB1;
    uint256 tokenA2;
    uint256 tokenB2;
}

struct ArbitrageInfo {
    address baseToken;
    address quoteToken;
    bool baseTokenSmaller;
    address lowerPool; 
    address higherPool; 
}

struct CallbackData {
    address debtPool;
    address targetPool;
    bool debtTokenSmaller;
    address borrowedToken;
    address debtToken;
    uint256 debtAmount;
    uint256 debtTokenOutAmount;
}
}