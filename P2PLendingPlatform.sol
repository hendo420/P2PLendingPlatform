// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract P2PLendingPlatform is ERC721, Ownable, Initializable {
    using SafeMath for uint256;

    IERC20 public usdt;
    AggregatorV3Interface public ethPriceFeed;
    uint256 private constant LOAN_TO_COLLATERAL_RATIO = 60;
    
    struct LendingPosition {
        address lender;
        uint256 amount;
        uint256 interestRate;
    }

    struct BorrowingPosition {
        address borrower;
        uint256 collateral;
        uint256 loanAmount;
        uint256 dueAmount;
        uint256 lendingPositionId;
    }

    mapping(uint256 => LendingPosition) public lendingPositions;
    mapping(uint256 => BorrowingPosition) public borrowingPositions;

    // Initialize the contract with the USDT token address and the Chainlink Oracle address
    function initialize(IERC20 _usdt, AggregatorV3Interface _ethPriceFeed) public initializer {
        __ERC721_init("LendingPosition", "LP");
        __Ownable_init();
        
        usdt = _usdt;
        ethPriceFeed = _ethPriceFeed;
    }

    function createLendingPosition(uint256 _amount, uint256 _interestRate) external {
        require(_amount > 0, "Amount should be greater than 0");
        require(_interestRate <= 100, "Interest rate should be less than or equal to 100");
        
        uint256 tokenId = totalSupply().add(1);
        
        lendingPositions[tokenId] = LendingPosition(msg.sender, _amount, _interestRate);
        usdt.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, tokenId);
    }

    function takeLoan(uint256 _lendingPositionId, uint256 _loanAmount) external payable {
        LendingPosition storage lendingPosition = lendingPositions[_lendingPositionId];
        require(lendingPosition.amount >= _loanAmount, "Insufficient amount available in lending position");

        uint256 collateral = msg.value;
        uint256 collateralValue = collateral.mul(getEthPriceInUsdt());
        require(collateralValue >= _loanAmount.mul(100).div(LOAN_TO_COLLATERAL_RATIO), "Collateral not sufficient");

        lendingPosition.amount = lendingPosition.amount.sub(_loanAmount);
        uint256 dueAmount = _loanAmount.add((_loanAmount.mul(lendingPosition.interestRate)).div(100));

        uint256 tokenId = totalSupply().add(1);
        
        borrowingPositions[tokenId] = BorrowingPosition(msg.sender, collateral, _loanAmount, dueAmount, _lendingPositionId);
        _mint(msg.sender, tokenId);

        usdt.transfer(msg.sender, _loanAmount);
    }



    function payLoan(uint256 _borrowingPositionId, uint256 _amount) external {
        BorrowingPosition storage borrowingPosition = borrowingPositions[_borrowingPositionId];
        require(borrowingPosition.dueAmount >= _amount, "Amount exceeds the due amount");
        usdt.transferFrom(msg.sender, address(this), _amount);
        borrowingPosition.dueAmount = borrowingPosition.dueAmount.sub(_amount);

        if (borrowingPosition.dueAmount == 0) {
            uint256 collateral = borrowingPosition.collateral;
            borrowingPosition.collateral = 0;
            payable(borrowingPosition.borrower).transfer(collateral);
            _burn(_borrowingPositionId);
        }
    }

    function liquidateLoan(uint256 _borrowingPositionId) external {
        BorrowingPosition storage borrowingPosition = borrowingPositions[_borrowingPositionId];
        LendingPosition storage lendingPosition = lendingPositions[borrowingPosition.lendingPositionId];

        require(lendingPosition.lender == msg.sender, "Only lender can liquidate the loan");
        require(borrowingPosition.collateral.mul(getEthPriceInUsdt()).mul(100) < borrowingPosition.loanAmount.mul(LOAN_TO_COLLATERAL_RATIO), "Collateral is still sufficient");

        uint256 remainingCollateralValue = (borrowingPosition.collateral.mul(getEthPriceInUsdt())).sub(borrowingPosition.dueAmount);
        uint256 remainingCollateral = remainingCollateralValue.div(getEthPriceInUsdt());

        lendingPosition.amount = lendingPosition.amount.add(borrowingPosition.dueAmount);
        usdt.transfer(lendingPosition.lender, borrowingPosition.dueAmount);
    
        payable(borrowingPosition.borrower).transfer(remainingCollateral);
    
        delete borrowingPositions[_borrowingPositionId];
        _burn(_borrowingPositionId);
    }

    function addCollateral(uint256 _borrowingPositionId) external payable {
        BorrowingPosition storage borrowingPosition = borrowingPositions[_borrowingPositionId];
        require(borrowingPosition.borrower == msg.sender, "Only borrower can add collateral");
        borrowingPosition.collateral = borrowingPosition.collateral.add(msg.value);
    }

    function withdrawAvailableUsdt(uint256 _lendingPositionId) external {
        LendingPosition storage lendingPosition = lendingPositions[_lendingPositionId];
        require(lendingPosition.lender == msg.sender, "Only lender can withdraw available USDT");
        uint256 availableUsdt = lendingPosition.amount;
        lendingPosition.amount = 0;
        usdt.transfer(msg.sender, availableUsdt);
    }

    function getEthPriceInUsdt() public view returns (uint256) {
        (, int256 price, , , ) = ethPriceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

// Functions to update the USDT and Chainlink oracle addresses

    function setUsdtAddress(IERC20 _usdt) external onlyOwner {
        usdt = _usdt;
    }

    function setEthPriceFeed(AggregatorV3Interface _ethPriceFeed) external onlyOwner {
        ethPriceFeed = _ethPriceFeed;
    }

}



