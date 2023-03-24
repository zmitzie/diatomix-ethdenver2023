import { expect } from "chai";
import { Signer } from "ethers";
import { ethers, upgrades } from "hardhat";
import hre from "hardhat";

// check to make some duplicates of amount prices
const { parseEther, parseUnits } = ethers.utils;

describe("Run scenarios with Aave and Uniswap", () => {
    let pool: any;
    let stablecoin: any;
    let wbtc: any;
    let uniLp: any;
    let aToken: any;
    let uniswapRouterInstance: any;
    let ownerSigner: Signer
    let impersonatedSigner: Signer
    let user1Signer: Signer, user2Signer: Signer
    let user1: String, user2: String, owner: String;

    const WBTC = "0xf4423F4152966eBb106261740da907662A3569C5";
    const USDC = "0x9FD21bE27A2B059a288229361E2fA632D8D2d074";
    const LPTOKEN = "0x6e321c578c27E248B261011Ee55D40765690065a";
    const ATOKEN = "0x935c0F6019b05C787573B5e6176681282A3f3E05";
    const UNISWAPROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";


    //const amount = ethers.BigNumber.from("3645");

    before(async () => {
        [ownerSigner, user1Signer, user2Signer] = await ethers.getSigners();

        owner = await ownerSigner.getAddress();
        user1 = await user1Signer.getAddress();
        user2 = await user2Signer.getAddress();

        console.log('Deploying Pool contract...');
        const Pool = await ethers.getContractFactory("Pool");
        pool = await upgrades.deployProxy(Pool, ["0xf4423F4152966eBb106261740da907662A3569C5", "0x9FD21bE27A2B059a288229361E2fA632D8D2d074", 7500, 2, 20000, 2000000, "Diatomix Pool #1", "DTX1"], { initializer: 'initialize' });
        await pool.connect(ownerSigner).deployed();
        console.log('Pool deployed to:', pool.address);

        const erc20 = await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
            ethers.constants.AddressZero
        );

        // Setup Uniswap router & attach to address
        const uniswapRouter = await ethers.getContractAt(
            "contracts/interfaces/IUniswapV2Router.sol:IUniswapV2Router",
            ethers.constants.AddressZero
        );
        uniswapRouterInstance = uniswapRouter.attach(UNISWAPROUTER);

        //Impersonate USDC whale
        impersonatedSigner = await ethers.getImpersonatedSigner("0x59d3f24990098325ae80af90dc06e5aff5e6356a");
        //impersonatedSigner = await ethers.getImpersonatedSigner("0x03575dC0316D4DFcd09ccBbd18A17A8fa5C1161e");

        stablecoin = erc20.attach(USDC);
        console.log("Balance of whale in USDC: ",await stablecoin.balanceOf(impersonatedSigner.getAddress()));

        wbtc = erc20.attach(WBTC);
        console.log("Balance of whale in WBTC: ",await wbtc.balanceOf(impersonatedSigner.getAddress()));

        uniLp = erc20.attach(LPTOKEN);
        console.log("Balance of owner in uniLp: ",await uniLp.balanceOf(owner));

        aToken = erc20.attach(ATOKEN);
        console.log("Balance of whale in aToken: ",await aToken.balanceOf(impersonatedSigner.getAddress()));

        // Make an initial deposit of 1000 USDC
        const amountToDeposit = ethers.BigNumber.from("1000000000");
        await stablecoin.connect(impersonatedSigner).approve(pool.address, amountToDeposit); //usdc
        await pool.connect(impersonatedSigner)._userDeposit(amountToDeposit);
        console.log("DXP balance:",await pool.balanceOf(impersonatedSigner.getAddress()));

        // Uncomment to throw in some dust in USDC and WBTC
        // await wbtc.connect(user1Signer).approve(pool.address, ethers.BigNumber.from("10"));
        // await wbtc.connect(user1Signer).transfer(pool.address, ethers.BigNumber.from("10"));
        // await stablecoin.connect(user1Signer).approve(pool.address, ethers.BigNumber.from("1000"));
        // await stablecoin.connect(user1Signer).transfer(pool.address, ethers.BigNumber.from("1000"));
    });
    describe("Simulate normal contract interactions", () => {
        describe("Perform Generic Withdrawals", () => {
            it("should deduct the total supply by burning tokens", async () => {
                const userBalance = await pool.balanceOf(impersonatedSigner.getAddress());
                const totalSupply = await pool.totalSupply();
                const amountToWithdraw = ethers.BigNumber.from(userBalance).div(ethers.BigNumber.from(100));
                await pool.connect(impersonatedSigner)._userWithdraw(amountToWithdraw);
                expect(await pool.totalSupply()).to.deep.equal(ethers.BigNumber.from(totalSupply - userBalance.div(100)));
            });
            it("should reduce the user's balance by burning tokens", async () => {
                const userBalance = await pool.balanceOf(impersonatedSigner.getAddress());
                const amountToWithdraw = ethers.BigNumber.from("10000000");
                await pool.connect(impersonatedSigner)._userWithdraw(amountToWithdraw);
                expect(await pool.balanceOf(impersonatedSigner.getAddress())).to.deep.equal(ethers.BigNumber.from(userBalance - 10000000));
            });
            it("should withdraw without affecting the DXP token price", async () => {
                const userBalance = await pool.balanceOf(impersonatedSigner.getAddress());
                const tokenPriceBeforeWithdraw = await pool.getDXPTokenPrice();
                const amountToWithdraw = ethers.BigNumber.from(userBalance).div(ethers.BigNumber.from(10));
                await pool.connect(impersonatedSigner)._userWithdraw(amountToWithdraw);
                expect((await pool.getDXPTokenPrice()).toNumber()).to.be.within(tokenPriceBeforeWithdraw.toNumber()*0.9999, tokenPriceBeforeWithdraw.toNumber()*1.1111);
            });
            it("should withdraw without unbalancing the pool", async () => {
                const userBalance = await pool.balanceOf(impersonatedSigner.getAddress());
                const amountToWithdraw = ethers.BigNumber.from(userBalance).div(ethers.BigNumber.from(10));
                await pool.connect(impersonatedSigner)._userWithdraw(amountToWithdraw);
                console.log(await pool.consoleLogPoolState());
                const poolStatePct = await pool.returnPctPoolState();
                expect(poolStatePct[2].toNumber()).to.be.within(85695*0.99, 85695*1.11);
                expect(poolStatePct[3].toNumber()).to.be.within(57142*0.99, 57142*1.11);
                expect(poolStatePct[4].toNumber()).to.be.within(428*0.99, 428*1.11);
            });
        });

        describe("Perform Specific Deposits and Withdrawals", () => {
            it("Deposit 1000 USDC", async () => {
                const amountToDeposit = ethers.BigNumber.from("1000000000");
                await stablecoin.connect(impersonatedSigner).approve(pool.address, amountToDeposit); //usdc
                await pool.connect(impersonatedSigner)._userDeposit(amountToDeposit);
                console.log("DXP balance:",await pool.balanceOf(impersonatedSigner.getAddress()));
                console.log("Total supply:",await pool.totalSupply());
                const poolStatePct = await pool.returnPctPoolState();
                expect(poolStatePct[2].toNumber()).to.be.within(85695*0.99, 85695*1.11);
                expect(poolStatePct[3].toNumber()).to.be.within(57142*0.99, 57142*1.11);
                expect(poolStatePct[4].toNumber()).to.be.within(428*0.99, 428*1.11);
                //expect(await fractionToken.balanceOf(dutchAuction.address)).to.equal(22);
            });

            it("should withdraw 50% of USDC from the pool and remain balanced", async () => {
                const userBalance = await pool.balanceOf(impersonatedSigner.getAddress());
                console.log(userBalance);
                const totalSupply = await pool.totalSupply();
                const amountToWithdraw = ethers.BigNumber.from(userBalance).div(ethers.BigNumber.from(2));
                console.log(amountToWithdraw);
                await pool.connect(impersonatedSigner)._userWithdraw(amountToWithdraw);
                console.log("DXP balance:",await pool.balanceOf(impersonatedSigner.getAddress()));
                expect(await pool.totalSupply()).to.deep.equal(ethers.BigNumber.from(userBalance - userBalance.div(2)));
                expect(await pool.totalSupply()).to.deep.equal(ethers.BigNumber.from(totalSupply - userBalance.div(2)));
                expect(await pool.balanceOf(impersonatedSigner.getAddress())).to.deep.equal(ethers.BigNumber.from(userBalance - userBalance.div(2)));
                const poolStatePct = await pool.returnPctPoolState();
                expect(poolStatePct[2].toNumber()).to.be.within(85695*0.99, 85695*1.11);
                expect(poolStatePct[3].toNumber()).to.be.within(57142*0.99, 57142*1.11);
                expect(poolStatePct[4].toNumber()).to.be.within(428*0.99, 428*1.11);
            });
        
        });
    });

    
    describe("Transfer tokens to contract to check rebalancing", () => {
        it("Transfer LP tokens to contract and expect proper rebalancing", async () => {
            // 
            const transferAmount = ethers.BigNumber.from("1000000");
            await uniLp.connect(ownerSigner).approve(pool.address, transferAmount);
            await uniLp.connect(ownerSigner).transfer(pool.address, transferAmount);
            const amountToDeposit = ethers.BigNumber.from("10000000");
            await stablecoin.connect(impersonatedSigner).approve(pool.address, amountToDeposit); //usdc
            await pool.connect(impersonatedSigner)._userDeposit(amountToDeposit);
            const poolStatePct = await pool.returnPctPoolState();
            expect(poolStatePct[2].toNumber()).to.be.within(85695*0.99, 85695*1.11);
            expect(poolStatePct[3].toNumber()).to.be.within(57142*0.99, 57142*1.11);
            expect(poolStatePct[4].toNumber()).to.be.within(428*0.99, 428*1.11);

        });
        it("Transfer aTokens to contract and expect proper rebalancing", async () => {
            const transferAmount = ethers.BigNumber.from("1000000000");
            await aToken.connect(impersonatedSigner).approve(pool.address, transferAmount);
            await aToken.connect(impersonatedSigner).transfer(pool.address, transferAmount);
            const amountToDeposit = ethers.BigNumber.from("10000000");
            await stablecoin.connect(impersonatedSigner).approve(pool.address, amountToDeposit); //usdc
            await pool.connect(impersonatedSigner)._userDeposit(amountToDeposit);
            const poolStatePct = await pool.returnPctPoolState();
            expect(poolStatePct[2].toNumber()).to.be.within(85695*0.99, 85695*1.11);
            expect(poolStatePct[3].toNumber()).to.be.within(57142*0.99, 57142*1.11);
            expect(poolStatePct[4].toNumber()).to.be.within(428*0.99, 428*1.11);
        });
        it("Transfer wbtc to contract and expect proper rebalancing", async () => {
            const transferAmount = ethers.BigNumber.from("100");
            await wbtc.connect(impersonatedSigner).approve(pool.address, transferAmount);
            await wbtc.connect(impersonatedSigner).transfer(pool.address, transferAmount);
            const amountToDeposit = ethers.BigNumber.from("10000000");
            await stablecoin.connect(impersonatedSigner).approve(pool.address, amountToDeposit); //usdc
            await pool.connect(impersonatedSigner)._userDeposit(amountToDeposit);
            const poolStatePct = await pool.returnPctPoolState();
            expect(poolStatePct[2].toNumber()).to.be.within(85695*0.99, 85695*1.11);
            expect(poolStatePct[3].toNumber()).to.be.within(57142*0.99, 57142*1.11);
            expect(poolStatePct[4].toNumber()).to.be.within(428*0.99, 428*1.11);
        });
        it("Transfer usdc to contract and expect proper rebalancing", async () => {
            const transferAmount = ethers.BigNumber.from("10000000000");
            await stablecoin.connect(impersonatedSigner).approve(pool.address, transferAmount);
            await stablecoin.connect(impersonatedSigner).transfer(pool.address, transferAmount);
            const amountToDeposit = ethers.BigNumber.from("10000000");
            await stablecoin.connect(impersonatedSigner).approve(pool.address, amountToDeposit); //usdc
            await pool.connect(impersonatedSigner)._userDeposit(amountToDeposit);
            const poolStatePct = await pool.returnPctPoolState();
            expect(poolStatePct[2].toNumber()).to.be.within(85695*0.99, 85695*1.11);
            expect(poolStatePct[3].toNumber()).to.be.within(57142*0.99, 57142*1.11);
            expect(poolStatePct[4].toNumber()).to.be.within(428*0.99, 428*1.11);
        });
    });
    describe("Price movements", () => {
        it("Double the price of X with a swap, then rebalance", async () => {
            // Swap in Uniswap
            const transferAmountIn = ethers.BigNumber.from("200000000000");
            const transferAmountOut = ethers.BigNumber.from("10000");
            let exchangeRate = await pool.returnPoolState()
            console.log("Old exchange rate: ",exchangeRate[6].toNumber());
            await stablecoin.connect(impersonatedSigner).approve(uniswapRouterInstance.address, transferAmountIn);
            await uniswapRouterInstance.connect(impersonatedSigner).swapExactTokensForTokens(transferAmountIn, transferAmountOut, [USDC, WBTC], impersonatedSigner.getAddress(), 1707400000);
            exchangeRate = await pool.returnPoolState()
            console.log("New exchange rate: ",exchangeRate[6].toNumber());

            // Make a deposit
            const amountToDeposit = ethers.BigNumber.from("10000000");
            await stablecoin.connect(impersonatedSigner).approve(pool.address, amountToDeposit); //usdc
            await pool.connect(impersonatedSigner)._userDeposit(amountToDeposit);
        });
    });
    
    describe("Random Deposits and Withdrawals", () => {
        let totalDeposits: number;
        it("Make 100 random deposits from the same account", async () => {
            let counter = 0;
            for (let i = 0; i < 100; i++) {
                // random number generator between 100 USDC and 1000 USDC
                let randomNumber = Math.floor((Math.random() * 1000000000) + 100000000);
                totalDeposits += randomNumber;
                const amountToDeposit = ethers.BigNumber.from(randomNumber);
                await stablecoin.connect(impersonatedSigner).approve(pool.address, amountToDeposit); //usdc
                await pool.connect(impersonatedSigner)._userDeposit(amountToDeposit);
                counter += 1;
                console.log(counter);
                const poolStatePct = await pool.returnPctPoolState();
                expect(poolStatePct[2].toNumber()).to.be.within(85695*0.99, 85695*1.11);
                expect(poolStatePct[3].toNumber()).to.be.within(57142*0.99, 57142*1.11);
                expect(poolStatePct[4].toNumber()).to.be.within(428*0.99, 428*1.11);
            }
        });
    });
    
});
