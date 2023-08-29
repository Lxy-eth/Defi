const {ethers} = require('hardhat')
const {expect} = require('chai')

describe('Owner', () => {
    let weth;
    let flashbot;
    let owner;
    beforeEach(async () => {
        owner = await ethers.getSigner(0);
        const WETH = await ethers.getContractFactory('Test');
        weth = await WETH.deploy('weth','weth')
        await weth.deployed(); 
        const flashBot = await ethers.getContractFactory('FlashBot')
        flashbot = await flashBot.deploy(weth.address)
        await flashbot.deployed();
    });

    it('Should set owner to deployer',async () =>  {
        expect(await flashbot.owner()).to.be.eq(owner.address);
    })

    it('recieve ether', async () => {
        const amount = ethers.utils.parseEther('9.1');
        const tx = await owner.sendTransaction({
            to: flashbot.address,
            value: amount
        })
        expect(await ethers.provider.getBalance(flashbot.address)).to.be.eq(amount);

    })

    it('withdraw ether', async () => {
        const amount = ethers.utils.parseEther('9.1');
        const tx = await owner.sendTransaction({
            to: flashbot.address,
            value: amount
        })

        
        const wethAmount = ethers.utils.parseEther('100.1');
        await weth.mint(flashbot.address, wethAmount);

        const balanceBefore = await ethers.provider.getBalance(flashbot.address);
        const wethBefore = await weth.balanceOf(flashbot.address);

        const withdraw = await flashbot.withdraw()

        const balanceAfter = await ethers.provider.getBalance(flashbot.address);
        const wethAfter = await weth.balanceOf(flashbot.address);

        expect(balanceBefore).to.be.eq(balanceAfter.add(amount));
        expect(wethBefore).to.be.eq(wethAfter.add(wethAmount));
    })
})