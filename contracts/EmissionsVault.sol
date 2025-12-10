// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address,uint256) external returns (bool);
}

interface IStakingNotify {
    function notifyReward(uint256 amount) external;
}

contract SAFIVault {
    uint256 private constant BPS_DENOM  = 10_000;
    uint256 private constant FAUCET_BPS = 100;
    uint256 private constant MAX_DAYS_PER_CALL = 60;

    address public immutable owner;
    uint256 public lastStakeDay;

    IERC20  public safi;
    address public staking;
    address public faucet;
    uint16  public stakeBps = 30;

    event TokenSet(address token);
    event StakingSet(address staking);
    event FaucetSet(address faucet);
    event StakeBpsSet(uint16 bps);
    event DailyStakePayout(uint256 dayFrom, uint256 dayTo, uint256 transfers, uint256 lastAmount);
    event FaucetRefill(uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _owner, uint256 startTimestampUtc) {
        require(_owner != address(0), "zero owner");
        owner = _owner;
        lastStakeDay = startTimestampUtc / 1 days;
    }

    function setToken(address _safi) external onlyOwner {
        require(_safi != address(0), "zero token");
        safi = IERC20(_safi);
        emit TokenSet(_safi);
    }

    function setStaking(address _staking) external onlyOwner {
        require(_staking != address(0), "zero staking");
        staking = _staking;
        emit StakingSet(_staking);
    }

    function setFaucet(address _faucet) external onlyOwner {
        require(_faucet != address(0), "zero faucet");
        faucet = _faucet;
        emit FaucetSet(_faucet);
    }

    function setStakeBps(uint16 _bps) external onlyOwner {
        require(_bps <= BPS_DENOM, "bps");
        stakeBps = _bps;
        emit StakeBpsSet(_bps);
    }

    function run() external {
        require(address(safi) != address(0), "token unset");
        require(staking != address(0), "stake unset");
        uint256 today = block.timestamp / 1 days;
        require(today > lastStakeDay, "up-to-date");

        uint256 toProcess = today - lastStakeDay;
        if (toProcess > MAX_DAYS_PER_CALL) toProcess = MAX_DAYS_PER_CALL;

        uint256 transfers;
        uint256 lastAmt;
        for (uint256 i = 0; i < toProcess; i++) {
            uint256 amt = _percentOfVault(stakeBps);
            if (amt > 0) {
                require(safi.transfer(staking, amt), "transfer fail");
                IStakingNotify(staking).notifyReward(amt);
                lastAmt = amt;
                transfers++;
            }
            lastStakeDay += 1;
        }
        emit DailyStakePayout(today - toProcess + 1, today, transfers, lastAmt);
    }

    function requestFaucetRefill() external {
        require(msg.sender == faucet, "only faucet");
        uint256 amt = _percentOfVault(FAUCET_BPS);
        require(amt > 0, "zero amt");
        require(safi.transfer(faucet, amt), "transfer fail");
        emit FaucetRefill(amt);
    }

    function _percentOfVault(uint256 bps) internal view returns (uint256) {
        uint256 bal = safi.balanceOf(address(this));
        return (bal * bps) / BPS_DENOM;
    }

    function nextStakeDay() external view returns (uint256) { return lastStakeDay + 1; }

    function currentDayUTC() public view returns (uint32) {
        return uint32(block.timestamp / 86400);
    }

    function nextStakeEpochTs() public view returns (uint256) {
        return (uint256(lastStakeDay) + 1) * 86400;
    }

    function secondsToNextStakeEpoch() external view returns (uint256) {
        uint256 nowTs = block.timestamp;
        uint256 nextTs = nextStakeEpochTs();
        return nextTs > nowTs ? nextTs - nowTs : 0;
    }

    function previewStakeDaily() external view returns (uint256) {
        return (safi.balanceOf(address(this)) * stakeBps) / BPS_DENOM;
    }
}
