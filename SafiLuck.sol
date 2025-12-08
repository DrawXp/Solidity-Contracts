// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address,uint256) external returns (bool);
    function transferFrom(address,address,uint256) external returns (bool);
    function allowance(address,address) external view returns (uint256);
    function approve(address,uint256) external returns (bool);
}

library SafeERC20 {
    function safeTransfer(IERC20 t,address to,uint256 v) internal { require(t.transfer(to,v),"TRANSFER_FAIL"); }
    function safeTransferFrom(IERC20 t,address f,address to,uint256 v) internal { require(t.transferFrom(f,to,v),"TRANSFER_FROM_FAIL"); }
}

abstract contract Ownable {
    address public owner;
    modifier onlyOwner(){ require(msg.sender==owner,"OWN"); _; }
    constructor(){ owner=msg.sender; }
    function transferOwnership(address n) external onlyOwner { owner=n; }
}

abstract contract ReentrancyGuard {
    uint256 private s=1;
    modifier nonReentrant(){ require(s==1,"REENT"); s=2; _; s=1; }
}

interface ISwapVault {
    function lotteryBalanceOf(address token) external view returns (uint256);
    function pull(address token,uint256 amount,address to) external;
    function pullAsNative(uint256 amount,address to) external;
}

contract SAFILuck is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Span { uint256 endId; address buyer; }
    struct Round {
        uint64 id;
        uint64 startTs;
        uint64 endTs;
        uint64 anchorBlock;
        bytes32 commitHash;
        bool isSealed;
        bool finalized;
        uint256 totalTickets;
        uint256 pot;
        address winner;
        uint256 winnerTicket;
        uint64 claimDeadline;
        bool claimed;
    }
    struct RewardCfg { uint256 minT; uint256 maxT; bool enabled; }

    IERC20 public ticketToken;
    uint256 public ticketPrice;
    uint16 public feeBps;
    uint16 public maxFeeBps = 1000;
    address public keeper;
    uint32 public roundDurationSec = 300;
    uint32 public claimWindowSec = 240;
    bool public pauseNextRound;
    uint64 public currentRoundId;
    mapping(uint64=>Round) public rounds;
    mapping(uint64=>Span[]) private spans;
    mapping(address=>RewardCfg) public rewardCfg;
    address[] public rewardTokens;
    mapping(uint64=>mapping(address=>uint256)) public extraAmount;
    mapping(address=>uint256) public extraCarry;                  
    uint256 public ownerFeeAccrued;
    ISwapVault public vault;
    uint256 public carryPool;
    address public wNative;

    event KeeperSet(address);
    event FeeSet(uint16);
    event TicketPriceSet(uint256);
    event DurationSet(uint32);
    event ClaimWindowSet(uint32);
    event VaultSet(address);
    event RewardTokenAdded(address,uint256,uint256);
    event ThresholdRangeSet(address,uint256,uint256);
    event RoundOpened(uint64,uint64,uint64,uint256);
    event Committed(uint64,bytes32);
    event Sealed(uint64,uint64);
    event TicketsBought(uint64,address,uint256,uint256,uint256);
    event WinnerDrawn(uint64,address,uint256,uint256);
    event ExtrasSelected(uint64,address,uint256);
    event Claimed(uint64,address,uint256);
    event RolledOver(uint64,uint256);
    event WNativeSet(address);

    modifier onlyKeeper(){ require(msg.sender==keeper,"KEEP"); _; }

    constructor(address _ticketToken,uint256 _ticketPrice,uint16 _feeBps,address _vault) {
        ticketToken = IERC20(_ticketToken);
        ticketPrice = _ticketPrice;
        require(_feeBps<=maxFeeBps,"BPS");
        feeBps = _feeBps;
        vault = ISwapVault(_vault);
        _openNextRound();
    }

    function setKeeper(address a) external onlyOwner { keeper=a; emit KeeperSet(a); }
    function setFeeBps(uint16 bps) external onlyOwner { require(bps<=maxFeeBps,"BPS"); feeBps=bps; emit FeeSet(bps); }
    function setTicketPrice(uint256 p) external onlyOwner { ticketPrice=p; emit TicketPriceSet(p); }
    function setRoundDuration(uint32 s) external onlyOwner { require(s>=60,"DUR"); roundDurationSec=s; emit DurationSet(s); }
    function setClaimWindow(uint32 s) external onlyOwner { require(s>=60,"WIN"); claimWindowSec=s; emit ClaimWindowSet(s); }
    function setSwapVault(address a) external onlyOwner { vault=ISwapVault(a); emit VaultSet(a); }
    function setWNative(address a) external onlyOwner { wNative=a; emit WNativeSet(a); }
    function pauseNext(bool v) external onlyOwner { pauseNextRound=v; }

    function addRewardToken(address t,uint256 minT,uint256 maxT) external onlyOwner {
        require(minT<=maxT,"RNG");
        if(!rewardCfg[t].enabled) rewardTokens.push(t);
        rewardCfg[t]=RewardCfg(minT,maxT,true);
        emit RewardTokenAdded(t,minT,maxT);
    }

    function setThresholdRange(address t,uint256 minT,uint256 maxT) external onlyOwner {
        require(rewardCfg[t].enabled,"TOK");
        require(minT<=maxT,"RNG");
        rewardCfg[t].minT=minT;
        rewardCfg[t].maxT=maxT;
        emit ThresholdRangeSet(t,minT,maxT);
    }

    function currentRound() public view returns (Round memory r) { r=rounds[currentRoundId]; }

    function buyTickets(uint32 amount) external nonReentrant {
        Round storage r = rounds[currentRoundId];
        require(block.timestamp < r.endTs,"END");
        require(amount>0,"AMT");
        uint256 cost = uint256(amount)*ticketPrice;
        ticketToken.safeTransferFrom(msg.sender,address(this),cost);
        r.pot += cost;
        r.totalTickets += amount;
        uint256 last = spans[currentRoundId].length==0 ? 0 : spans[currentRoundId][spans[currentRoundId].length-1].endId;
        spans[currentRoundId].push(Span(last+amount,msg.sender));
        emit TicketsBought(currentRoundId,msg.sender,uint256(last)+1,amount,cost);
    }

    function commit(bytes32 h) external onlyKeeper {
        Round storage r = rounds[currentRoundId];
        require(!r.finalized,"FIN");
        require(r.commitHash == bytes32(0),"HAS");
        r.commitHash = h;
        emit Committed(currentRoundId,h);
    }

    function seal() external onlyKeeper {
        Round storage r = rounds[currentRoundId];
        require(block.timestamp >= r.endTs,"TIME");
        require(!r.isSealed,"SEALED");
        r.isSealed = true;
        r.anchorBlock = uint64(block.number);
        emit Sealed(currentRoundId,r.anchorBlock);
    }

    function finalize(bytes calldata secret) external onlyKeeper nonReentrant {
        Round storage r = rounds[currentRoundId];
        require(block.timestamp >= r.endTs,"TIME");
        require(!r.finalized,"FIN");
        if(!r.isSealed){
            r.isSealed = true;
            r.anchorBlock = uint64(block.number);
            emit Sealed(currentRoundId,r.anchorBlock);
        }
        if(r.commitHash==bytes32(0)){
            r.commitHash = keccak256(secret);
            emit Committed(currentRoundId,r.commitHash);
        }
        require(keccak256(secret)==r.commitHash,"REVEAL");
        if(r.totalTickets==0){
            uint256 fee0 = r.pot*feeBps/10000;
            ownerFeeAccrued += fee0;
            uint256 net0 = r.pot - fee0;
            r.finalized=true;
            r.claimed=true;
            carryPool += net0;
            emit RolledOver(r.id,net0);
            _openNextRound();
            return;
        }
        bytes32 bh = blockhash(r.anchorBlock);
        if(bh==bytes32(0)){
            bh = blockhash(block.number-1);
        }
        uint256 seed = uint256(keccak256(abi.encode(bh,secret,r.id,r.totalTickets)));
        uint256 winnerTicket = (seed % r.totalTickets) + 1;
        (address win,) = _ownerOfTicket(currentRoundId,winnerTicket);
        r.winner = win;
        r.winnerTicket = winnerTicket;
        uint256 fee = r.pot*feeBps/10000;
        uint256 net = r.pot - fee;
        ownerFeeAccrued += fee;
        r.claimDeadline = uint64(block.timestamp + claimWindowSec);
        r.finalized = true;
        emit WinnerDrawn(r.id,win,winnerTicket,net);

        for(uint256 i=0;i<rewardTokens.length;i++){
            address tok = rewardTokens[i];
            RewardCfg memory cfg = rewardCfg[tok];
            if(!cfg.enabled) continue;
            if(cfg.maxT<cfg.minT) continue;

            uint256 rT = uint256(keccak256(abi.encode(seed,tok,r.id)));
            uint256 th = cfg.minT + (rT % (cfg.maxT - cfg.minT + 1));

            uint256 internalAvail = extraCarry[tok];
            uint256 vaultAvail = ISwapVault(vault).lotteryBalanceOf(tok);

            if (internalAvail + vaultAvail >= th) {
                uint256 useFromCarry = internalAvail >= th ? th : internalAvail;
                if (useFromCarry > 0) {
                    extraCarry[tok] = internalAvail - useFromCarry;
                }
                uint256 needFromVault = th - useFromCarry;
                if (needFromVault > 0) {
                    if (tok == wNative) {
                        vault.pullAsNative(needFromVault, address(this));
                    } else {
                        vault.pull(tok, needFromVault, address(this));
                    }
                }
                extraAmount[r.id][tok] = th;
                emit ExtrasSelected(r.id, tok, th);
            }
        }

        _openNextRound();
    }

    function claim(uint64 roundId) external nonReentrant {
        Round storage r = rounds[roundId];
        require(r.finalized,"FIN");
        require(!r.claimed,"CLAIMED");
        require(r.winner==msg.sender,"WIN");
        require(block.timestamp <= r.claimDeadline,"EXP");
        uint256 fee = r.pot*feeBps/10000;
        uint256 net = r.pot - fee;
        r.claimed=true;
        ticketToken.safeTransfer(msg.sender,net);

        for(uint256 i=0;i<rewardTokens.length;i++){
            address tok = rewardTokens[i];
            uint256 amt = extraAmount[roundId][tok];
            if(amt>0){
                extraAmount[roundId][tok] = 0;
                if (tok == wNative) {
                    (bool ok,) = msg.sender.call{value: amt}("");
                    require(ok, "SEND_NATIVE");
                } else {
                    IERC20(tok).safeTransfer(msg.sender, amt);
                }
            }
        }
        emit Claimed(roundId,msg.sender,net);
    }

    function rolloverIfExpired(uint64 roundId) external nonReentrant {
        Round storage r = rounds[roundId];
        uint256 expTs = r.finalized ? uint256(r.claimDeadline) : uint256(r.endTs) + uint256(claimWindowSec);
        require(block.timestamp > expTs,"NOT_EXP");
        require(!r.claimed,"CLAIMED");
        uint256 fee = r.pot*feeBps/10000;
        uint256 net = r.pot - fee;
        ownerFeeAccrued += fee;
        r.finalized = true;
        r.claimed = true;
        carryPool += net;

        for(uint256 i=0;i<rewardTokens.length;i++){
            address tok = rewardTokens[i];
            uint256 amt = extraAmount[roundId][tok];
            if(amt>0){
                extraAmount[roundId][tok]=0;
                extraCarry[tok] += amt;
            }
        }

        emit RolledOver(roundId,net);
        if (roundId==currentRoundId) {
            _openNextRound();
        }
    }

    function withdrawOwnerFee(address to,uint256 amount) external onlyOwner nonReentrant {
        require(ownerFeeAccrued>=amount,"FEE");
        ownerFeeAccrued-=amount;
        ticketToken.safeTransfer(to,amount);
    }

    function rewardTokensCount() external view returns (uint256) { return rewardTokens.length; }

    function viewRoundExtras(uint64 roundId)
        external
        view
        returns (address[] memory tokens_, uint256[] memory amounts_)
    {
        uint256 count=0;
        for(uint256 i=0;i<rewardTokens.length;i++){
            if (extraAmount[roundId][rewardTokens[i]]>0) count++;
        }
        tokens_ = new address[](count);
        amounts_ = new uint256[](count);
        uint256 j=0;
        for(uint256 i=0;i<rewardTokens.length;i++){
            address tok = rewardTokens[i];
            uint256 amt = extraAmount[roundId][tok];
            if (amt>0){
                tokens_[j]=tok;
                amounts_[j]=amt;
                j++;
            }
        }
    }

    function viewCarryExtras()
        external
        view
        returns (address[] memory tokens_, uint256[] memory amounts_)
    {
        uint256 count=0;
        for(uint256 i=0;i<rewardTokens.length;i++){
            if (extraCarry[rewardTokens[i]]>0) count++;
        }
        tokens_ = new address[](count);
        amounts_ = new uint256[](count);
        uint256 j=0;
        for(uint256 i=0;i<rewardTokens.length;i++){
            address tok = rewardTokens[i];
            uint256 amt = extraCarry[tok];
            if (amt>0){
                tokens_[j]=tok;
                amounts_[j]=amt;
                j++;
            }
        }
    }

    function openNext() external onlyOwner {
        require(!pauseNextRound, "PAUSED");
        require(rounds[currentRoundId].finalized, "NOT_FINAL");
        _openNextRound();
    }

    function _ownerOfTicket(uint64 rid,uint256 ticketId) internal view returns (address,uint256) {
        Span[] storage a = spans[rid];
        uint256 lo=0; uint256 hi=a.length;
        while(lo<hi){
            uint256 mid=(lo+hi)/2;
            if(ticketId<=a[mid].endId) hi=mid; else lo=mid+1;
        }
        require(lo<a.length,"NF");
        return (a[lo].buyer, lo);
    }

    function _openNextRound() internal {
        if(pauseNextRound) return;
        currentRoundId += 1;
        Round storage n = rounds[currentRoundId];
        n.id = currentRoundId;
        n.startTs = uint64(block.timestamp);
        n.endTs = uint64(block.timestamp + roundDurationSec);
        if(carryPool>0){
            n.pot += carryPool;
            carryPool = 0;
        }
        emit RoundOpened(n.id,n.startTs,n.endTs,n.pot);
    }

    receive() external payable {}
}
