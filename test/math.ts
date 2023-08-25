import lodash from 'lodash';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, ContractFactory } from 'ethers';

//const { BigNumber } = ethers;

describe('MathTest', () => {
    let wethFactory: ContractFactory;
    let flashBotFactory: ContractFactory;
    let weth: Contract; 

    beforeEach(async () => {
        wethFactory = await ethers.getContractFactory('Test');
        weth = await wethFactory.deploy('WETH', 'weth'); 
        
        flashBotFactory = await ethers.getContractFactory('FlashBot');
        const flashBot = await flashBotFactory.deploy(weth.address);
    });
});