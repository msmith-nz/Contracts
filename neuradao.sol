// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract Setup {
    NeuraDAO public dao;
    uint256 public initialBalance;
    
    constructor() payable {
        dao = new NeuraDAO();
        payable(address(dao)).transfer(msg.value);
        initialBalance = address(dao).balance;
    }
    
    function isSolved() external view returns (bool) {
        return dao.hasGainedMajorityControl();
    }
}

contract NeuraDAO {
    
    enum MembershipTier { Citizen, Administrator, SupremeCouncil }
    
    struct Member {
        uint256 stakedTokens;
        MembershipTier tier;
        uint256 votingPower;
        address delegatedTo;
        uint256 delegatedVotes;
        bool isActive;
    }
    
    struct Proposal {
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
    }
    
    mapping(address => Member) public members;
    mapping(uint256 => Proposal) public proposals;
    
    address public founder;
    uint256 public totalSupply;
    uint256 public proposalCount;
    uint256 public totalActiveVotingPower;
    
    uint256 constant CITIZEN_MULTIPLIER = 1;
    uint256 constant ADMIN_MULTIPLIER = 3;
    uint256 constant SUPREME_MULTIPLIER = 5;
    
    uint256 constant ADMIN_UPGRADE_COST = 1 ether;
    uint256 constant SUPREME_UPGRADE_COST = 3 ether;
    
    event MemberJoined(address indexed member, uint256 stakedAmount);
    event MembershipUpgraded(address indexed member, MembershipTier newTier);
    event VotesDelegated(address indexed from, address indexed to, uint256 amount);
    event ProposalCreated(uint256 indexed proposalId, string description);
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool support, uint256 votingPower);
    
    modifier onlyFounder() {
        require(msg.sender == founder, "Only founder can call this function");
        _;
    }
    
    modifier onlyActiveMember() {
        require(members[msg.sender].isActive, "Only active members can call this function");
        _;
    }
    
    constructor() {
        founder = msg.sender;
        totalSupply = 10000 ether;
    }
    
    receive() external payable {
    }
    
    function joinDao() external payable {
        require(msg.value >= 0.1 ether, "Minimum stake is 0.1 ETH");
        require(!members[msg.sender].isActive, "Already a member");
        
        Member storage member = members[msg.sender];
        member.stakedTokens = msg.value;
        member.tier = MembershipTier.Citizen;
        member.isActive = true;
        
        member.votingPower = msg.value * CITIZEN_MULTIPLIER;
        totalActiveVotingPower += member.votingPower;
        
        emit MemberJoined(msg.sender, msg.value);
    }
    
    function upgradeMembership(MembershipTier newTier) external payable onlyActiveMember {
        Member storage member = members[msg.sender];
        require(uint8(newTier) > uint8(member.tier), "Can only upgrade to higher tier");
        
        uint256 cost = 0;
        uint256 newMultiplier = 0;
        
        if (newTier == MembershipTier.Administrator) {
            cost = ADMIN_UPGRADE_COST;
            newMultiplier = ADMIN_MULTIPLIER;
        } else if (newTier == MembershipTier.SupremeCouncil) {
            cost = SUPREME_UPGRADE_COST;
            newMultiplier = SUPREME_MULTIPLIER;
        }
        
        require(msg.value >= cost, "Insufficient payment for upgrade");
        
        uint256 oldMultiplier = _getTierMultiplier(member.tier);
        
        totalActiveVotingPower -= member.votingPower;
        
        member.tier = newTier;
        
        uint256 newBaseVotingPower = member.stakedTokens * newMultiplier;
        
        member.votingPower = newBaseVotingPower + (member.delegatedVotes * newMultiplier);
        
        totalActiveVotingPower += member.votingPower;
        
        emit MembershipUpgraded(msg.sender, newTier);
    }
    
    function delegateVotes(address to) external onlyActiveMember {
        require(to != msg.sender, "Cannot delegate to yourself");
        require(members[to].isActive, "Delegate must be active member");
        require(members[msg.sender].delegatedTo == address(0), "Already delegated");
        
        Member storage delegator = members[msg.sender];
        Member storage delegatee = members[to];
        
        totalActiveVotingPower -= delegator.votingPower;
        
        uint256 delegatedAmount = delegator.votingPower;
        delegator.delegatedTo = to;
        delegator.votingPower = 0;
        
        delegatee.delegatedVotes += delegatedAmount;
        delegatee.votingPower += delegatedAmount;
        
        totalActiveVotingPower += delegatee.votingPower;
        
        emit VotesDelegated(msg.sender, to, delegatedAmount);
    }
    
    function undelegateVotes() external onlyActiveMember {
        address delegatee = members[msg.sender].delegatedTo;
        require(delegatee != address(0), "No delegation exists");
        
        Member storage delegator = members[msg.sender];
        Member storage delegateeStruct = members[delegatee];
        
        uint256 originalPower = delegator.stakedTokens * _getTierMultiplier(delegator.tier);
        
        totalActiveVotingPower -= delegateeStruct.votingPower;
        delegateeStruct.delegatedVotes -= originalPower;
        delegateeStruct.votingPower -= originalPower;
        totalActiveVotingPower += delegateeStruct.votingPower;
        
        delegator.delegatedTo = address(0);
        delegator.votingPower = originalPower;
        totalActiveVotingPower += delegator.votingPower;
    }
    
    function createProposal(string memory description) external onlyActiveMember returns (uint256) {
        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.description = description;
        proposal.endTime = block.timestamp + 7 days;
        
        emit ProposalCreated(proposalId, description);
        return proposalId;
    }
    
    function vote(uint256 proposalId, bool support) external onlyActiveMember {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp <= proposal.endTime, "Voting period ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(!proposal.executed, "Proposal already executed");
        
        uint256 votingPower = members[msg.sender].votingPower;
        require(votingPower > 0, "No voting power");
        
        proposal.hasVoted[msg.sender] = true;
        
        if (support) {
            proposal.votesFor += votingPower;
        } else {
            proposal.votesAgainst += votingPower;
        }
        
        emit VoteCast(msg.sender, proposalId, support, votingPower);
    }
    
    function _getTierMultiplier(MembershipTier tier) internal pure returns (uint256) {
        if (tier == MembershipTier.Administrator) {
            return ADMIN_MULTIPLIER;
        } else if (tier == MembershipTier.SupremeCouncil) {
            return SUPREME_MULTIPLIER;
        }
        return CITIZEN_MULTIPLIER;
    }
    
    function hasGainedMajorityControl() external view returns (bool) {
        if (totalActiveVotingPower == 0) return false;
        return totalActiveVotingPower > 10 ether;
    }
    
    function getMemberInfo(address member) external view returns (
        uint256 stakedTokens,
        MembershipTier tier,
        uint256 votingPower,
        address delegatedTo,
        uint256 delegatedVotes,
        bool isActive
    ) {
        Member storage m = members[member];
        return (
            m.stakedTokens,
            m.tier,
            m.votingPower,
            m.delegatedTo,
            m.delegatedVotes,
            m.isActive
        );
    }
    
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    function getTotalActiveVotingPower() external view returns (uint256) {
        return totalActiveVotingPower;
    }
}