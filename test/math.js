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
            console.log(x1.toString(), x2.toString())
            expect(x1).to.be.eq(7);
            expect(x2).to.be.eq(0);      
        })
    })
    describe('calcBorrowAmount', () => {
        it("returns right amount with small liquidity pairs",async () => {
            const reserves = {a1:5000,a2:10,b1:6000,b2:10}
            const input = lodash.mapValues(reserves, (v) => ethers.utils.parseEther(v));
            const out = await flashBot._calcBorrowAmount(input);
            console.log(out)
        })
    })
})