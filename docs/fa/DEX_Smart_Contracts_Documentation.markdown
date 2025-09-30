# BETA
# سند فنی اجرایی برای توسعه قراردادهای هوشمند صرافی غیرمتمرکز (DEX)

**تاریخ**: 27 سپتامبر 2025  
**هدف**: ارائه مشخصات فنی و اجرایی قراردادهای هوشمند برای یک صرافی غیرمتمرکز (DEX) مبتنی بر مدل AMM (مانند Uniswap V3) با قابلیت‌هایی مانند تعویض توکن، مدیریت نقدینگی،治理، اوراکل و پاداش‌دهی.  
**بلاکچین**: Ethereum یا EVM-compatible (مانند BSC).  
**ابزارها**: Solidity (^0.8.0)، Hardhat، OpenZeppelin، Chainlink.  

## 1. معماری کلی  
- **Core Contracts**: Factory و Pool برای مدیریت استخرها و عملیات اصلی.  
- **Periphery Contracts**: Router و Position Manager برای تعامل کاربرپسند.  
- **Additional Contracts**: Governance (برای DAO)، Oracle (برای قیمت‌ها)، Staking (برای پاداش).  
- **مدل**: AMM با Concentrated Liquidity (مانند Uniswap V3) برای بازدهی بالاتر.  
- **استانداردها**: ERC-20 (توکن‌ها)، ERC-721 (موقعیت‌های نقدینگی)، Proxy Pattern برای Upgradeability.  

---

## 2. قرارداد Factory  
**توضیح**: ایجاد و مدیریت استخرهای نقدینگی برای جفت‌های توکن. مالکیت برای به‌روزرسانی‌ها دارد.  

### فانکشن‌های کلیدی  
- **createPool**  
  - **پارامترها**: address tokenA, address tokenB, uint24 fee  
  - **بازگشت**: address pool  
  - **Visibility**: external  
  - **توضیح**: ایجاد استخر جدید برای جفت توکن با کارمزد مشخص (مثلاً 0.3%). اگر استخر وجود داشته باشد، خطا می‌دهد.  
  - **کد نمونه**:  
    ```solidity
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        require(tokenA != tokenB, "Tokens must be different");
        // محاسبه آدرس و deploy استخر
    }
    ```

- **setOwner**  
  - **پارامترها**: address _owner  
  - **بازگشت**: none  
  - **Visibility**: external  
  - **توضیح**: تغییر مالک کارخانه. فقط مالک فعلی می‌تواند فراخوانی کند.  

- **enableFeeAmount**  
  - **پارامترها**: uint24 fee, int24 tickSpacing  
  - **بازگشت**: none  
  - **Visibility**: public  
  - **توضیح**: فعال‌سازی سطح کارمزد جدید با فاصله تیک.  

- **getPool**  
  - **پارامترها**: address tokenA, address tokenB, uint24 fee  
  - **بازگشت**: address  
  - **Visibility**: public view  
  - **توضیح**: بازگشت آدرس استخر موجود.  

---

## 3. قرارداد Pool  
**توضیح**: مدیریت نقدینگی، تعویض‌ها، و اوراکل قیمت برای یک جفت توکن. از فرمول x * y = k یا Concentrated Liquidity استفاده می‌کند.  

### فانکشن‌های کلیدی  
- **swap**  
  - **پارامترها**: address recipient, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, bytes calldata data  
  - **بازگشت**: int256 amount0, int256 amount1  
  - **Visibility**: external  
  - **توضیح**: اجرای تعویض توکن. amountSpecified مثبت برای exact input و منفی برای exact output.  

- **mint**  
  - **پارامترها**: address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data  
  - **بازگشت**: uint256 amount0, uint256 amount1  
  - **Visibility**: external  
  - **توضیح**: افزودن نقدینگی در محدوده تیک. توکن LP به‌صورت NFT صادر می‌شود.  

- **burn**  
  - **پارامترها**: int24 tickLower, int24 tickUpper, uint128 amount  
  - **بازگشت**: uint256 amount0, uint256 amount1  
  - **Visibility**: external  
  - **توضیح**: حذف نقدینگی و سوزاندن LP.  

- **collect**  
  - **پارامترها**: address recipient, int24 tickLower, int24 tickUpper, uint128 amount0Requested, uint128 amount1Requested  
  - **بازگشت**: uint128 amount0, uint128 amount1  
  - **Visibility**: external  
  - **توضیح**: جمع‌آوری کارمزدهای انباشته.  

- **observe**  
  - **پارامترها**: uint32[] calldata secondsAgos  
  - **بازگشت**: int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s  
  - **Visibility**: external view  
  - **توضیح**: بازگشت داده‌های TWAP برای اوراکل قیمت.  

- **increaseObservationCardinalityNext**  
  - **پارامترها**: uint16 observationCardinalityNext  
  - **بازگشت**: none  
  - **Visibility**: external  
  - **توضیح**: افزایش ظرفیت اوراکل برای داده‌های بیشتر.  

---

## 4. قرارداد Router  
**توضیح**: واسطه برای تعویض‌های پیچیده و مدیریت نقدینگی. کاربران از طریق این قرارداد با Poolها تعامل می‌کنند.  

### فانکشن‌های کلیدی  
- **exactInputSingle**  
  - **پارامترها**: struct ExactInputSingleParams {address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96}  
  - **بازگشت**: uint256 amountOut  
  - **Visibility**: external payable  
  - **توضیح**: تعویض دقیق ورودی تک‌هوپ.  

- **exactInput**  
  - **پارامترها**: struct ExactInputParams {bytes path, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum}  
  - **بازگشت**: uint256 amountOut  
  - **Visibility**: external payable  
  - **توضیح**: تعویض دقیق ورودی چند‌هوپ.  

- **exactOutputSingle**  
  - **پارامترها**: struct ExactOutputSingleParams {address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 deadline, uint256 amountOut, uint256 amountInMaximum, uint160 sqrtPriceLimitX96}  
  - **بازگشت**: uint256 amountIn  
  - **Visibility**: external payable  
  - **توضیح**: تعویض دقیق خروجی تک‌هوپ.  

- **exactOutput**  
  - **پارامترها**: struct ExactOutputParams {bytes path, address recipient, uint256 deadline, uint256 amountOut, uint256 amountInMaximum}  
  - **بازگشت**: uint256 amountIn  
  - **Visibility**: external payable  
  - **توضیح**: تعویض دقیق خروجی چند‌هوپ.  

- **uniswapV3SwapCallback**  
  - **پارامترها**: int256 amount0Delta, int256 amount1Delta, bytes calldata data  
  - **بازگشت**: none  
  - **Visibility**: external  
  - **توضیح**: کال‌بک برای پرداخت پس از تعویض.  

---

## 5. قرارداد Position Manager  
**توضیح**: مدیریت موقعیت‌های نقدینگی به‌صورت NFT (ERC-721). برای مدل V3 ضروری است.  

### فانکشن‌های کلیدی  
- **positions**  
  - **پارامترها**: uint256 tokenId  
  - **بازگشت**: uint96 nonce, address operator, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1  
  - **Visibility**: external view  
  - **توضیح**: بازگشت جزئیات موقعیت نقدینگی.  

- **mint**  
  - **پارامترها**: struct MintParams {address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address recipient, uint256 deadline}  
  - **بازگشت**: uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1  
  - **Visibility**: external payable  
  - **توضیح**: ایجاد موقعیت جدید و صدور NFT.  

- **tokenURI**  
  - **پارامترها**: uint256 tokenId  
  - **بازگشت**: string memory  
  - **Visibility**: public view  
  - **توضیح**: بازگشت URI متادیتا برای NFT.  

---

## 6. قرارداد Governance  
**توضیح**: مدیریت رأی‌گیری غیرمتمرکز (DAO) با توکن‌های حاکمیتی (ERC-20).  

### فانکشن‌های کلیدی  
- **propose**  
  - **پارامترها**: address[] targets, uint[] values, string[] signatures, bytes[] calldatas, string description  
  - **بازگشت**: uint proposalId  
  - **Visibility**: public  
  - **توضیح**: ایجاد پیشنهاد جدید برای تغییرات (مانند کارمزد).  

- **vote**  
  - **پارامترها**: uint proposalId, bool support  
  - **بازگشت**: none  
  - **Visibility**: public  
  - **توضیح**: رأی‌دهی با وزن توکن‌های stake‌شده.  

- **execute**  
  - **پارامترها**: uint proposalId  
  - **بازگشت**: none  
  - **Visibility**: public  
  - **توضیح**: اجرای پیشنهاد پس از quorum و دوره رأی‌گیری.  

**کد نمونه ساده**:  
```solidity
contract Governance is Ownable {
    struct Proposal { /* جزئیات پیشنهاد */ }
    function propose(address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) public returns (uint) {
        // منطق پیشنهاد
    }
}
```

---

## 7. قرارداد Oracle Integration  
**توضیح**: ادغام با Chainlink برای دریافت قیمت‌های واقعی و جلوگیری از manipulation.  

### فانکشن‌های کلیدی  
- **getLatestPrice**  
  - **پارامترها**: address aggregator (مانند Chainlink ETH/USD)  
  - **بازگشت**: int256 price  
  - **Visibility**: public view  
  - **توضیح**: بازگشت قیمت آخرین از اوراکل.  

**کد نمونه**:  
```solidity
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
contract Oracle {
    AggregatorV3Interface internal priceFeed;
    constructor(address _aggregator) {
        priceFeed = AggregatorV3Interface(_aggregator);
    }
    function getLatestPrice() public view returns (int) {
        (,int price,,,) = priceFeed.latestRoundData();
        return price;
    }
}
```

---

## 8. قرارداد Staking/Farming  
**توضیح**: پاداش‌دهی به ارائه‌دهندگان نقدینگی با stake توکن‌های LP.  

### فانکشن‌های کلیدی  
- **stake**  
  - **پارامترها**: uint256 amount  
  - **بازگشت**: none  
  - **Visibility**: external  
  - **توضیح**: stake توکن‌های LP و شروع محاسبه پاداش.  

- **withdraw**  
  - **پارامترها**: uint256 amount  
  - **بازگشت**: none  
  - **Visibility**: external  
  - **توضیح**: برداشت stake و ادعای پاداش.  

- **claimReward**  
  - **پارامترها**: none  
  - **بازگشت**: uint256 reward  
  - **Visibility**: external  
  - **توضیح**: ادعای پاداش انباشته.  

**کد نمونه**:  
```solidity
contract Staking {
    mapping(address => uint) public balances;
    function stake(uint256 amount) external {
        // انتقال توکن‌ها و بروزرسانی بالانس
    }
}
```