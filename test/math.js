const {lodash} =  require('lodash');
const {ethers} = require('hardhat')
const {expect} = require('chai')
const { BigNumber } = ethers;

describe('MathTest', () => {
    let flashbot;
    beforeEach(async () => {
        const WETH = await ethers.getContractFactory('Test');
        const weth = await WETH.deploy('weth','weth')
        await weth.deployed();
        const flashBot = await ethers.getContractFactory('FlashBot')
         flashbot = await flashBot.deploy(weth.address)
        await flashbot.deployed();
    })

    describe("calcSolutionForQuadratic",() => {
        it('calculate right solution for quadratic', async () => {
            const [a, b, c] = ['12345678901234567890', '-98765432109876543210', '11111111111111111111'];
         
            const [x1, x2] = await flashbot.calcSolutionForQuadratic(a, b, c);    
            //console.log(x1.toString(), x2.toString())
            expect(x1).to.be.eq(7);
            expect(x2).to.be.eq(0);      
        })
    })
    describe('calcBorrowAmount', () => {
        it("returns right amount with small liquidity pairs",async () => {
            const reserves = [
                ethers.utils.parseEther('5000'),
                ethers.utils.parseEther('10'),
                ethers.utils.parseEther('6000'),
                ethers.utils.parseEther('10')
            ];
            // console.log(reserves)
           
            const out = await flashbot.calcBorrowAmount(reserves);
            expect(out).to.be.closeTo(ethers.utils.parseEther('0.45'), ethers.utils.parseEther('0.01'));
        })
    })
})