// SPDX-License-Identifier: Unlicesed
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IAaveProtocolDataProvider.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IERC20.sol";

contract Pool is
    Initializable,
    ERC20Upgradeable,
    AutomationCompatibleInterface
{
    /***
    STORAGE VARIABLES
    */
    //using WadRayMath for uint256;
    address private constant FACTORY =
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; //goerli, mainnnet
    address private constant ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; //goerli, mainnet
    address private constant LENDINGPOOL =
        0x4bd5643ac6f66a5237E18bfA7d47cF22f1c9F210; //goerli
    address private constant AAVEPROTOCOLDATAPROVIDER =
        0x927F584d4321C1dCcBf5e2902368124b02419a1E; //goerli

    uint256 public constant UINT_MAX_VALUE = 2 ** 256 - 1;

    address public underlyingAssetAddressA;
    address public underlyingAssetAddressB;
    address private uniswapPair;
    address private aToken;
    address private dToken;
    uint8 private _decimals; // decimals of diatomix pool issued token
    uint256 public loanPercentage;
    uint256 private aaveInterestMode; //can be constant = 2
    uint256 private assetAZapThreshold;
    uint256 private assetBZapThreshold;

    /***
     Chainlink Variables
    */

    // Public counter
    uint256 public counter;
    // Use an interval in seconds and a timestamp to slow execution of Upkeep
    uint public interval;
    // Last timestamp
    uint256 public lastTimestamp;
    // Last poolValueDenotedInY
    uint256 private lastPoolValueDenotedInY;

    /***
    MODIFIERS
    */

    /**
     * @dev Initialized upgradeable contract. Replaced the constructor
     * @param _underlyingAssetAddressA The address of the underlying token X.
     * @param _underlyingAssetAddressB The address of the underlying token Y.
     * @param _loanpct The percentage represented in basis points that will be used in Aave for the loan to value ratio.
     * @param _aaveInterestMode 1 is stable interest rate debt, 2 is variable. Variable is preferred due to lower interest rates in general.
     * @param _assetAZapThreshold The threshold used to determine the minimum amount of underlying asset A in zaps.
     * @param _assetBZapThreshold The threshold used to determine the minimum amount of underlying asset B in zaps.
     * @param _name The name of the ERC20 token.
     * @param _symbol The symbol of the ERC20 token.
     * @param _updateInterval The interval between Chainlink Automation executions.
     **/
    function initialize(
        address _underlyingAssetAddressA,
        address _underlyingAssetAddressB,
        uint256 _loanpct,
        uint256 _aaveInterestMode,
        uint256 _assetAZapThreshold,
        uint256 _assetBZapThreshold,
        string memory _name,
        string memory _symbol,
        uint256 _updateInterval
    ) public initializer {
        underlyingAssetAddressA = _underlyingAssetAddressA;
        underlyingAssetAddressB = _underlyingAssetAddressB;
        // Initialize ERC20 token
        __ERC20_init(_name, _symbol);
        // Get Uniswap Pair
        uniswapPair = IUniswapV2Factory(FACTORY).getPair(
            _underlyingAssetAddressA,
            _underlyingAssetAddressB
        );
        (aToken, , ) = IAaveProtocolDataProvider(AAVEPROTOCOLDATAPROVIDER)
            .getReserveTokensAddresses(underlyingAssetAddressB);
        (, , dToken) = IAaveProtocolDataProvider(AAVEPROTOCOLDATAPROVIDER)
            .getReserveTokensAddresses(underlyingAssetAddressA);
        // Set Aave risk params for this pool
        aaveInterestMode = _aaveInterestMode;
        loanPercentage = _loanpct;
        _decimals = IERC20(underlyingAssetAddressB).decimals();
        assetAZapThreshold = _assetAZapThreshold;
        assetBZapThreshold = _assetBZapThreshold;

        // Chainlink
        interval = _updateInterval;
        lastTimestamp = block.timestamp;
        counter = 0;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev External function called by the user to deposit an amount of underlying token Y in the pool. DTX pool tokens are minted
     * @notice Approval is required on the underlying token Y contract from msg.sender for the amount
     * @param amount The amount of the underlying token Y to deposit.
     **/
    function _userDeposit(uint256 amount) public {
        // calculate value of the pool -
        require(amount > 0, "Error: Deposit amount cannot be 0");
        uint256 poolBalanceInYBeforeDeposit = getBalanceOfPoolDenotedInY();

        IERC20(underlyingAssetAddressB).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        rebalance();
        // get value of pool after rebalancing
        uint256 poolBalanceInYAfterDeposit = getBalanceOfPoolDenotedInY();
        if (totalSupply() == 0) {
            _mint(msg.sender, (poolBalanceInYAfterDeposit * 1000) / 1000); //We define the price of DXP to be equal to 1.
        } else {
            uint256 priceOfToken = (
                ((poolBalanceInYBeforeDeposit * (10 ** decimals())) /
                    (totalSupply()))
            );
            uint256 amountToMint = ((
                (poolBalanceInYAfterDeposit - poolBalanceInYBeforeDeposit)
            ) * 10 ** decimals()) / priceOfToken;
            _mint(msg.sender, amountToMint);
        }
    }

    function _userDepositOnBehalfOf(
        uint256 amount,
        address onBehalfOf,
        address supplier
    ) external {
        require(amount > 0, "Error: Deposit amount cannot be 0");
        uint256 poolBalanceInYBeforeDeposit = getBalanceOfPoolDenotedInY();
        IERC20(underlyingAssetAddressB).transferFrom(
            supplier,
            address(this),
            amount
        );
        rebalance();
        uint256 poolBalanceInYAfterDeposit = getBalanceOfPoolDenotedInY();
        if (totalSupply() == 0) {
            _mint(onBehalfOf, (poolBalanceInYAfterDeposit * 1000) / 1000); //We define the price of DXP to be equal to 1.
        } else {
            uint256 priceOfToken = (
                ((poolBalanceInYBeforeDeposit * (10 ** decimals())) /
                    (totalSupply()))
            );
            uint256 amountToMint = ((
                (poolBalanceInYAfterDeposit - poolBalanceInYBeforeDeposit)
            ) * 10 ** decimals()) / priceOfToken;
            _mint(onBehalfOf, amountToMint);
        }
    }

    /**
     * @dev External function called by the user to withdraw an amount of underlying token Y in the pool. DTX pool tokens are burned
     * @notice No approval is required
     * @param dxpAmount The amount of Diatomix pool tokens being returned.
     **/
    function _userWithdraw(uint256 dxpAmount) public {
        uint256 priceOfToken = (
            ((getBalanceOfPoolDenotedInY() * (10 ** decimals())) /
                (totalSupply()))
        );
        uint256 initialYneeded = (priceOfToken * (dxpAmount)) /
            (10 ** decimals());
        int256 liquidateLPshares;

        liquidateLPshares = howManySharesToGetYAmount(
            int(
                initialYneeded -
                    IERC20(underlyingAssetAddressB).balanceOf(address(this))
            )
        );
        if (
            liquidateLPshares >
            int(IERC20(uniswapPair).balanceOf(address(this)))
        ) {
            //TODO: this liquidates all positions. Might not be necessary. We can optimize this?
            liquidateLPshares = int(
                IERC20(uniswapPair).balanceOf(address(this))
            ); //TODO: pass zero to liquidate all.
            _redeemLP(uint(liquidateLPshares));
            _reduceLoan(
                IERC20(underlyingAssetAddressA).balanceOf(address(this))
            );
            _decreaseCollateral(
                initialYneeded -
                    IERC20(underlyingAssetAddressB).balanceOf(address(this))
            );
        } else {
            _redeemLP(uint((liquidateLPshares * 1001) / 1000));
        }
        IERC20(underlyingAssetAddressB).approve(msg.sender, initialYneeded);
        IERC20(underlyingAssetAddressB).transfer(msg.sender, initialYneeded);

        rebalance();
        _burn(msg.sender, dxpAmount); //This sends the tokens to the zeroAddress and the totalSupply is updated.
        priceOfToken = (
            ((getBalanceOfPoolDenotedInY() * (10 ** decimals())) /
                (totalSupply()))
        );
    }

    function _redeemLP(
        uint256 liquidityToRemove
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (liquidityToRemove < 2000) {
            return (0, 0);
        }

        //We can never liquidate more LP shares than we have in balance
        if (liquidityToRemove > IERC20(uniswapPair).balanceOf(address(this))) {
            liquidityToRemove = IERC20(uniswapPair).balanceOf(address(this));
        }

        address pair = IUniswapV2Factory(FACTORY).getPair(
            underlyingAssetAddressA,
            underlyingAssetAddressB
        );
        IERC20(pair).approve(ROUTER, liquidityToRemove);

        (amountA, amountB) = IUniswapV2Router(ROUTER).removeLiquidity(
            underlyingAssetAddressA,
            underlyingAssetAddressB,
            liquidityToRemove,
            1,
            1,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(
        uint256 _amountA,
        uint256 _amountB
    )
        internal
        returns (uint256 amountA, uint256 amountB, uint256 liquidityProvided)
    {
        IERC20(underlyingAssetAddressA).approve(ROUTER, _amountA);
        IERC20(underlyingAssetAddressB).approve(ROUTER, _amountB);
        (amountA, amountB, liquidityProvided) = IUniswapV2Router(ROUTER)
            .addLiquidity(
                underlyingAssetAddressA,
                underlyingAssetAddressB,
                _amountA,
                _amountB,
                1,
                1,
                address(this),
                block.timestamp
            );
        return (amountA, amountB, liquidityProvided);
    }

    function _reduceLoan(uint256 amountToRepay) internal {
        IERC20(underlyingAssetAddressA).approve(LENDINGPOOL, amountToRepay);
        ILendingPool(LENDINGPOOL).repay(
            underlyingAssetAddressA,
            amountToRepay,
            aaveInterestMode,
            address(this)
        );
    }

    function _increaseLoan(uint256 amountToBorrow) internal {
        ILendingPool(LENDINGPOOL).borrow(
            underlyingAssetAddressA,
            amountToBorrow,
            aaveInterestMode,
            0,
            address(this)
        );
    }

    function _increaseCollateral(uint256 amountToDeposit) internal {
        IERC20(underlyingAssetAddressB).approve(LENDINGPOOL, amountToDeposit);
        ILendingPool(LENDINGPOOL).deposit(
            underlyingAssetAddressB,
            amountToDeposit,
            address(this),
            0
        );
    }

    function _decreaseCollateral(uint256 amountToRemove) internal {
        IERC20(underlyingAssetAddressB).approve(LENDINGPOOL, amountToRemove);
        ILendingPool(LENDINGPOOL).withdraw(
            underlyingAssetAddressB,
            amountToRemove,
            address(this)
        );
    }

    function _swapForExact(
        address _from,
        address _to,
        uint _amountToReceive,
        uint _amountToSendOut
    ) internal returns (uint) {
        if (IERC20(_from).balanceOf(address(this)) < _amountToSendOut) {
            _amountToSendOut = IERC20(_from).balanceOf(address(this));
        }
        IERC20(_from).approve(ROUTER, _amountToSendOut);

        address[] memory path = new address[](2);
        path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        uint[] memory outputs = IUniswapV2Router(ROUTER)
            .swapTokensForExactTokens(
                _amountToReceive,
                _amountToSendOut,
                path,
                address(this),
                block.timestamp
            );
        uint256 outputsLenght = outputs.length - 1;
        return outputs[outputsLenght];
    }

    function _swapExactFor(
        address _from,
        address _to,
        uint _amount
    ) internal returns (uint) {
        if (IERC20(_from).balanceOf(address(this)) < _amount) {
            _amount = IERC20(_from).balanceOf(address(this));
        }
        IERC20(_from).approve(ROUTER, _amount);

        address[] memory path = new address[](2);
        path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        uint[] memory outputs = IUniswapV2Router(ROUTER)
            .swapExactTokensForTokens(
                _amount,
                1,
                path,
                address(this),
                block.timestamp
            );
        uint256 outputsLenght = outputs.length - 1;
        return outputs[outputsLenght];
    }

    function rebalance() internal {
        (
            int256 _xd,
            int256 _yd,
            int256 _Ld,
            int256 _yl,
            int256 _xl
        ) = calculatePoperator();
        applyPoperator(_xd, _yd, _Ld, _yl, _xl);
        lastPoolValueDenotedInY = getBalanceOfPoolDenotedInY();
    }

    function getReserves() public view returns (uint256, uint256, uint256) {
        // returns the reserves always with the correct order
        if (IUniswapV2Pair(uniswapPair).token0() == underlyingAssetAddressA) {
            return (IUniswapV2Pair(uniswapPair).getReserves());
        } else {
            (uint256 balanceA, uint256 balanceB, uint256 timestamp) = (
                IUniswapV2Pair(uniswapPair).getReserves()
            );
            return (balanceB, balanceA, timestamp);
        }
    }

    function getUnderlyingBalances(
        uint256 lpTokens
    ) public view returns (uint256, uint256) {
        (uint256 reserve0, uint256 reserve1, ) = getReserves();
        uint256 LPTokenSupply = IERC20(uniswapPair).totalSupply();
        if (lpTokens == 0) {
            lpTokens = IERC20(uniswapPair).balanceOf(address(this));
        }

        return (
            ((reserve0 * lpTokens) / LPTokenSupply),
            ((reserve1 * lpTokens) / LPTokenSupply)
        );
    }

    function howManySharesToGetXAmount(
        int256 _x
    ) internal view returns (int256) {
        (uint256 reserve0, , ) = getReserves();
        return (
            ((_x * int(IERC20(uniswapPair).totalSupply())) / int(reserve0))
        );
    }

    function howManySharesToGetYAmount(
        int256 _y
    ) internal view returns (int256) {
        (, uint256 reserve1, ) = getReserves();
        return (
            ((_y * int(IERC20(uniswapPair).totalSupply())) / int(reserve1))
        );
    }

    function getBalanceOfUniswapShareDenotedInY()
        internal
        view
        returns (uint256)
    {
        (uint256 reserve0, uint256 reserve1, ) = getReserves();
        //console.log("reserve0, reserve1, from getReserves: ",reserve0, reserve1);
        (uint256 balanceA, uint256 balanceB) = getUnderlyingBalances(0);
        //console.log("balanceA, balanceB from getUnderlyingBalances: ",balanceA, balanceB);
        if (balanceA != 0) {
            uint256 convertedBalanceA = IUniswapV2Router(ROUTER).quote(
                balanceA,
                reserve0,
                reserve1
            );
            return (convertedBalanceA + balanceB);
        }
        return (balanceB);
    }

    function getExchangeRateWithDecimalReduction(
        uint256 amount
    ) internal view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = getReserves();
        return ((amount *
            IUniswapV2Router(ROUTER).quote(
                1 * (10 ** IERC20(underlyingAssetAddressB).decimals()),
                reserve0,
                reserve1
            )) / (1 * (10 ** IERC20(underlyingAssetAddressA).decimals())));
    }

    function getBalanceOfPoolDenotedInY() public view returns (uint256) {
        (uint256 balanceA, uint256 balanceB) = getUnderlyingBalances(0);
        uint256 convertedBalanceA = getExchangeRateWithDecimalReduction(
            balanceA
        );

        uint256 convertedLoan = getExchangeRateWithDecimalReduction(
            IERC20(dToken).balanceOf(address(this))
        );
        uint256 collateral = IERC20(aToken).balanceOf(address(this));
        uint256 convertedBalanceDTXA = getExchangeRateWithDecimalReduction(
            IERC20(underlyingAssetAddressA).balanceOf(address(this))
        );
        uint256 balanceDTXB = IERC20(underlyingAssetAddressB).balanceOf(
            address(this)
        );
        return (convertedBalanceDTXA +
            balanceDTXB +
            convertedBalanceA +
            balanceB +
            collateral -
            convertedLoan);
    }

    function calculatePoperator()
        internal
        view
        returns (int256, int256, int256, int256, int256)
    {
        console.log("---- calculatePoperator ----");
        (uint256 reserve0, uint256 reserve1, ) = getReserves();
        int256 yl = int(
            (getBalanceOfPoolDenotedInY() * 10000) / (10000 + loanPercentage)
        ) - int(IERC20(aToken).balanceOf(address(this)));
        int256 xl = int256(
            (((getBalanceOfPoolDenotedInY() *
                (
                    IUniswapV2Router(ROUTER).quote(
                        1 * (10 ** IERC20(underlyingAssetAddressB).decimals()),
                        reserve1,
                        reserve0
                    )
                )) / (1 * (10 ** IERC20(underlyingAssetAddressB).decimals()))) *
                loanPercentage) / (10000 + loanPercentage)
        ) - int256(IERC20(dToken).balanceOf(address(this)));
        int256 Ld = int(
            howManySharesToGetXAmount(
                xl + int(IERC20(dToken).balanceOf(address(this)))
            ) - int(IERC20(uniswapPair).balanceOf(address(this)))
        );
        return (
            -int(IERC20(underlyingAssetAddressA).balanceOf(address(this))),
            -int(IERC20(underlyingAssetAddressB).balanceOf(address(this))),
            Ld,
            yl,
            xl
        );
    }

    function getNeededXYredeemAMMShares(
        int256 Ld
    ) internal view returns (int256, int256) {
        (uint256 x, uint256 y) = getUnderlyingBalances(0);
        return (
            -((int(x) / int(IERC20(uniswapPair).balanceOf(address(this)))) *
                Ld),
            (
                -((int(y) / int(IERC20(uniswapPair).balanceOf(address(this)))) *
                    Ld)
            )
        );
    }

    function calculateNeededXYforGivenPoperator(
        int256 _xd,
        int256 _yd,
        int256 _Ld,
        int256 _yl,
        int256 _xl
    ) internal view returns (int256, int256) {
        int256 xr = 0;
        int256 yr = 0;
        if (_Ld < 0) {
            (int256 x, int256 y) = getNeededXYredeemAMMShares(_Ld);
            xr += x;
            yr += y;
        }
        if (_Ld > 0) {
            (uint reserve0, uint reserve1, ) = getReserves();
            int y = (_Ld * int(reserve1)) /
                int(IERC20(uniswapPair).totalSupply());
            int x = (_Ld * int(reserve0)) /
                int(IERC20(uniswapPair).totalSupply());
            xr += x;
            yr += y;
        }
        xr += (-_xl);
        yr += _yl;
        return (xr, yr);
    }

    function applyPoperator(
        int256 _xd,
        int256 _yd,
        int256 _Ld,
        int256 _yl,
        int256 _xl
    ) internal {
        consoleLogPoolState();
        (int256 xneeded, int256 yneeded) = calculateNeededXYforGivenPoperator(
            _xd,
            _yd,
            _Ld,
            _yl,
            _xl
        );
        int256 xneeded1 = 0;
        if (xneeded < 0) {
            xneeded = 0;
        }
        int256 yneeded1 = 0;
        if (yneeded < 0) {
            yneeded = 0;
        }

        if (yneeded != 0 || xneeded != 0) {
            int256 liquidateLPshares = 0;
            (uint reserve0, uint reserve1, ) = getReserves();
            if (
                (xneeded -
                    int(
                        IERC20(underlyingAssetAddressA).balanceOf(address(this))
                    )) *
                    int(
                        IUniswapV2Router(ROUTER).quote(
                            1 *
                                (10 **
                                    IERC20(underlyingAssetAddressA).decimals()),
                            reserve0,
                            reserve1
                        )
                    ) >
                (yneeded -
                    int(
                        IERC20(underlyingAssetAddressB).balanceOf(address(this))
                    ))
            ) {
                liquidateLPshares = howManySharesToGetXAmount(
                    xneeded -
                        int(
                            IERC20(underlyingAssetAddressA).balanceOf(
                                address(this)
                            )
                        )
                );
            } else {
                liquidateLPshares = howManySharesToGetYAmount(
                    yneeded -
                        int(
                            IERC20(underlyingAssetAddressB).balanceOf(
                                address(this)
                            )
                        )
                );
            }

            if (liquidateLPshares > 0) {
                console.log("Action 3 --> ");
                if (_Ld < 0) {
                    liquidateLPshares -= _Ld;
                }
                _redeemLP(uint(liquidateLPshares));
            }
            consoleLogInt(liquidateLPshares);
        }

        bool enoughLiquidity = true;
        if (
            yneeded1 >
            int(IERC20(underlyingAssetAddressB).balanceOf(address(this)))
        ) {
            enoughLiquidity = false;
        }
        if (
            xneeded1 >
            int(IERC20(underlyingAssetAddressA).balanceOf(address(this)))
        ) {
            enoughLiquidity = false;
        }

        require(enoughLiquidity, "Error: Not enough liquidity!");

        // Actions execution
        if (_yl > 0) {
            _increaseCollateral(uint(_yl));
        }
        if (_xl < 0) {
            _reduceLoan(uint(-_xl));
        }
        if (_xl > 0) {
            _increaseLoan(uint(_xl));
        }
        if (_yl < 0) {
            _decreaseCollateral(uint(-_yl));
        }
        // the loan and collateral are correctly sized at this point

        _addLiquidity(
            IERC20(underlyingAssetAddressA).balanceOf(address(this)),
            IERC20(underlyingAssetAddressB).balanceOf(address(this))
        );
        if (
            IERC20(underlyingAssetAddressA).balanceOf(address(this)) >
            assetAZapThreshold
        ) {
            zap(
                underlyingAssetAddressA,
                IERC20(underlyingAssetAddressA).balanceOf(address(this))
            );
        }
        if (
            IERC20(underlyingAssetAddressB).balanceOf(address(this)) >
            assetBZapThreshold
        ) {
            zap(
                underlyingAssetAddressB,
                IERC20(underlyingAssetAddressB).balanceOf(address(this))
            );
        }
    }

    /***
    Internal Uniswap Functions
    */
    function zap(
        address _tokenAddressWithBalance,
        uint _amountWithBalance
    ) internal returns (uint256, uint256) {
        (uint reserve0, uint reserve1, ) = getReserves();

        uint swapAmount;
        if (underlyingAssetAddressA == _tokenAddressWithBalance) {
            swapAmount = getSwapAmount(reserve0, _amountWithBalance);
            swap(underlyingAssetAddressA, underlyingAssetAddressB, swapAmount);
        } else {
            swapAmount = getSwapAmount(reserve1, _amountWithBalance);
            swap(underlyingAssetAddressB, underlyingAssetAddressA, swapAmount);
        }
        (uint256 amountA, uint256 amountB, ) = _addLiquidity(
            IERC20(underlyingAssetAddressA).balanceOf(address(this)),
            IERC20(underlyingAssetAddressB).balanceOf(address(this))
        );
        return (amountA, amountB);
    }

    function swap(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        if (IERC20(_from).balanceOf(address(this)) < _amount) {
            _amount = IERC20(_from).balanceOf(address(this));
        }
        IERC20(_from).approve(ROUTER, _amount);

        address[] memory path = new address[](2);
        path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        uint256[] memory outputs = IUniswapV2Router(ROUTER)
            .swapExactTokensForTokens(
                _amount,
                1,
                path,
                address(this),
                block.timestamp
            );
        uint256 outputsLenght = outputs.length - 1;
        return outputs[outputsLenght];
    }

    /*
    s = optimal swap amount
    r = amount of reserve for token a
    a = amount of token a the user currently has (not added to reserve yet)
    f = swap fee percent
    s = (sqrt(((2 - f)r)^2 + 4(1 - f)ar) - (2 - f)r) / (2(1 - f))
    */
    function sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function getSwapAmount(
        uint256 r,
        uint256 a
    ) internal pure returns (uint256) {
        return (sqrt(r * (r * 3988009 + a * 3988000)) - r * 1997) / 1994;
    }

    function getDXPTokenPrice() external view returns (uint256) {
        return ((getBalanceOfPoolDenotedInY() * (10 ** decimals())) /
            (totalSupply()));
    }

    function returnPoolState()
        public
        view
        returns (uint, uint, uint, uint, uint, uint, uint)
    {
        // xd, yd, Ld, yl, xl, PoolValueInY , exchange rate,
        return (
            IERC20(underlyingAssetAddressA).balanceOf(address(this)),
            IERC20(underlyingAssetAddressB).balanceOf(address(this)),
            IERC20(uniswapPair).balanceOf(address(this)),
            IERC20(aToken).balanceOf(address(this)),
            IERC20(dToken).balanceOf(address(this)),
            getBalanceOfPoolDenotedInY(),
            getExchangeRateWithDecimalReduction(100000000)
        );
    }

    function returnPctPoolState()
        public
        view
        returns (uint, uint, uint, uint, uint)
    {
        uint poolValue = getBalanceOfPoolDenotedInY();
        return (
            (getExchangeRateWithDecimalReduction(
                IERC20(underlyingAssetAddressA).balanceOf(address(this))
            ) * 100000) / poolValue,
            (IERC20(underlyingAssetAddressB).balanceOf(address(this)) *
                100000) / poolValue,
            (getBalanceOfUniswapShareDenotedInY() * 100000) / poolValue,
            (IERC20(aToken).balanceOf(address(this)) * 100000) / poolValue,
            (getExchangeRateWithDecimalReduction(
                IERC20(dToken).balanceOf(address(this))
            ) * 100000) / poolValue
        );
    }

    function getExchangeRateWithDecimalReductionPublic(
        uint256 amount
    ) external view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = getReserves();
        return ((amount *
            IUniswapV2Router(ROUTER).quote(
                1 * (10 ** IERC20(underlyingAssetAddressB).decimals()),
                reserve0,
                reserve1
            )) / (1 * (10 ** IERC20(underlyingAssetAddressA).decimals())));
    }

    function shouldRebalance() internal view returns (bool) {
        bool intervalPassed = (block.timestamp - lastTimestamp) > interval;

        uint256 currentPoolValueDenotedInY = getBalanceOfPoolDenotedInY();
        if (
            (((lastPoolValueDenotedInY * 500) / 10000) <
                currentPoolValueDenotedInY) ||
            ((lastPoolValueDenotedInY * 500) / 10000) >=
            currentPoolValueDenotedInY
        ) {
            return true;
        }
        if (intervalPassed) {
            if (
                (((lastPoolValueDenotedInY * 300) / 10000) <
                    currentPoolValueDenotedInY) ||
                ((lastPoolValueDenotedInY * 300) / 10000) >=
                currentPoolValueDenotedInY
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     Chainlink Functions
     */

    /**
     * @dev contains the logic that will be executed off-chain to see if the `performUpkeep` function should be executed.
     * @return upkeepNeeded boolean that flags if upkeep is needed
     */
    function checkUpkeep(
        bytes calldata checkData
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        return (shouldRebalance(), "");
    }

    /**
     * @dev this function will be executed on-chain when `checkUpkeep` function returns `true`.
     */
    function performUpkeep(bytes calldata performData) external override {
        require(shouldRebalance(), "Pool: checkUpKeep conditions failed");
        rebalance();
        if ((block.timestamp - lastTimestamp) > interval) {
            lastTimestamp = block.timestamp;
            counter = counter + 1;
        }
    }
}
