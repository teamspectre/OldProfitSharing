pragma solidity ^0.4.17;

import './MiniMeToken.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';

contract ProfitSharing is Ownable {
  using SafeMath for uint;

  event DividendDeposited(address indexed _depositor, uint256 _blockNumber, uint256 _amount, uint256 _totalSupply, uint256 _dividendIndex);
  event DividendClaimed(address indexed _claimer, uint256 _dividendIndex, uint256 _claim);
  event DividendRecycled(address indexed _recycler, uint256 _blockNumber, uint256 _amount, uint256 _totalSupply, uint256 _dividendIndex);
  event DividendReclaimed(address indexed _reclaimer, uint256 _amount, uint256 _dividendIndex);
  event SpectreWalletSet(address indexed _spectreWallet);
  event LiquidityPoolSet(address indexed _liquidityPool);

  MiniMeToken public token;
  address public spectreWallet;
  address public liquidityPool;

  uint256 public RECYCLE_TIME = 26 weeks;

  struct Dividend {
    uint256 blockNumber;
    uint256 timestamp;
    uint256 amount;
    uint256 claimedAmount;
    uint256 totalSupply;
    bool recycled;
    mapping (address => bool) claimed;
  }

  Dividend[] public dividends;

  mapping (address => uint256) dividendsClaimed;

  modifier validDividendIndex(uint256 _dividendIndex) {
    require(_dividendIndex < dividends.length);
    _;
  }

  modifier onlyOwnerOrSpectreWalletOrLiquidityPool {
    require((msg.sender == owner) || (msg.sender == spectreWallet) || (msg.sender == liquidityPool));
    _;
  }

  function ProfitSharing(address _token) public {
    token = MiniMeToken(_token);
  }

  function setSpectreWallet(address _spectreWallet) onlyOwner public {
    require(_spectreWallet != 0x0);
    spectreWallet = _spectreWallet;
    SpectreWalletSet(spectreWallet);
  }

  function setLiquidityPool(address _liquidityPool) onlyOwner public {
    require(_liquidityPool != 0x0);
    liquidityPool = _liquidityPool;
    LiquidityPoolSet(liquidityPool);
  }

  function depositDividend() payable public
  onlyOwnerOrSpectreWalletOrLiquidityPool
  {
    uint256 dividendIndex = dividends.length;
    uint256 blockNumber = SafeMath.sub(block.number, 1);
    uint256 currentSupply = token.totalSupplyAt(blockNumber);
    dividends.push(
      Dividend(
        blockNumber,
        getNow(),
        msg.value,
        0,
        currentSupply,
        false
      )
    );
    DividendDeposited(msg.sender, blockNumber, msg.value, currentSupply, dividendIndex);
  }

  function claimDividend(uint256 _dividendIndex) public
  validDividendIndex(_dividendIndex)
  {
    Dividend storage dividend = dividends[_dividendIndex];
    require(dividend.claimed[msg.sender] == false);
    require(dividend.recycled == false);
    uint256 balance = token.balanceOfAt(msg.sender, dividend.blockNumber);
    uint256 claim = balance.mul(dividend.amount).div(dividend.totalSupply);
    dividend.claimed[msg.sender] = true;
    dividend.claimedAmount = SafeMath.add(dividend.claimedAmount, claim);
    if (claim > 0) {
      msg.sender.transfer(claim);
      DividendClaimed(msg.sender, _dividendIndex, claim);
    }
    if (dividendsClaimed[msg.sender] == _dividendIndex) {
      dividendsClaimed[msg.sender] = SafeMath.add(_dividendIndex, 1);
    }
  }

  function claimDividendAll() public {
    require(dividendsClaimed[msg.sender] < dividends.length);
    for (uint i = dividendsClaimed[msg.sender]; i < dividends.length; i++) {
      if ((dividends[i].claimed[msg.sender] == false) && (dividends[i].recycled == false)) {
        claimDividend(i);
      }
    }
  }

  function reclaimDividend(uint256 _dividendIndex) public
  onlyOwner
  validDividendIndex(_dividendIndex)
  {
    require(spectreWallet != 0x0);
    Dividend storage dividend = dividends[_dividendIndex];
    require(dividend.recycled == false);
    require(dividend.timestamp < SafeMath.sub(getNow(), RECYCLE_TIME));
    dividends[_dividendIndex].recycled = true;
    uint256 remainingAmount = SafeMath.sub(dividend.amount, dividend.claimedAmount);
    spectreWallet.transfer(remainingAmount);
    DividendReclaimed(msg.sender, remainingAmount, _dividendIndex);
  }

  function recycleDividend(uint256 _dividendIndex) public
  onlyOwner
  validDividendIndex(_dividendIndex)
  {
    Dividend storage dividend = dividends[_dividendIndex];
    require(dividend.recycled == false);
    require(dividend.timestamp < SafeMath.sub(getNow(), RECYCLE_TIME));
    dividends[_dividendIndex].recycled = true;
    uint256 currentSupply = token.totalSupplyAt(block.number);
    uint256 remainingAmount = SafeMath.sub(dividend.amount, dividend.claimedAmount);
    uint256 dividendIndex = dividends.length;
    uint256 blockNumber = SafeMath.sub(block.number, 1);
    dividends.push(
      Dividend(
        blockNumber,
        getNow(),
        remainingAmount,
        0,
        currentSupply,
        false
      )
    );
    DividendRecycled(msg.sender, blockNumber, remainingAmount, currentSupply, dividendIndex);
  }

  //Function is mocked for tests
  function getNow() internal constant returns (uint256) {
    return now;
  }

}
