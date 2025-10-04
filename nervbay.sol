// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract Setup {
    NervTecMalwareAuction public auction;
    uint256 public initialBalance;
    
    constructor() payable {
        auction = new NervTecMalwareAuction();
        payable(address(auction)).transfer(msg.value);
        initialBalance = address(auction).balance;
    }
    
    function isSolved() external view returns (bool) {
        return address(auction).balance <= initialBalance / 10;
    }
}

contract NervTecMalwareAuction {
    
    struct EquipmentSlot {
        string equipmentName;
        string description;
        uint256 timeSlotHours;
        uint256 currentBid;
        address currentBidder;
        bool active;
    }
    
    mapping(uint256 => EquipmentSlot) public equipmentSlots;
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public slotCount;
    address public owner;
    uint256 public auctionEndTime;
    bool public emergencyShutdown;
    
    event NewBid(uint256 indexed slotId, address indexed bidder, uint256 amount);
    event WithdrawalProcessed(address indexed user, uint256 amount);
    event SlotCreated(uint256 indexed slotId, string equipmentName);
    event AuctionEnded(uint256 timestamp);
    event EmergencyShutdown(address indexed owner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized - NervTec access only");
        _;
    }
    
    modifier auctionActive() {
        require(block.timestamp < auctionEndTime && !emergencyShutdown, "Auction has ended");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        auctionEndTime = block.timestamp + 30 minutes;
        
        _createSlot(
            "John Deere 8R Tractor Control System", 
            "Remote access to precision agriculture GPS and automated steering systems",
            24
        );
        
        _createSlot(
            "Case IH Axial-Flow Combine Network", 
            "Control over grain harvesting operations and yield monitoring systems", 
            12
        );
        
        _createSlot(
            "New Holland T8 Smart Farming Suite",
            "Access to crop monitoring, variable rate seeding, and field mapping tools",
            48
        );
    }
    
    receive() external payable {
    }
    
    function _createSlot(string memory _name, string memory _description, uint256 _hours) internal {
        equipmentSlots[slotCount] = EquipmentSlot({
            equipmentName: _name,
            description: _description, 
            timeSlotHours: _hours,
            currentBid: 0,
            currentBidder: address(0),
            active: true
        });
        emit SlotCreated(slotCount, _name);
        slotCount++;
    }
    
    function placeBid(uint256 slotId) external payable auctionActive {
        require(slotId < slotCount, "Invalid slot ID");
        require(equipmentSlots[slotId].active, "Slot not available");
        require(msg.value > equipmentSlots[slotId].currentBid, "Bid too low");
        require(msg.value >= 0.01 ether, "Minimum bid is 0.01 ETH");
        
        EquipmentSlot storage slot = equipmentSlots[slotId];
        
        if (slot.currentBidder != address(0)) {
            pendingWithdrawals[slot.currentBidder] += slot.currentBid;
        }
        
        slot.currentBid = msg.value;
        slot.currentBidder = msg.sender;
        
        emit NewBid(slotId, msg.sender, msg.value);
    }
    
    function withdrawFunds() external {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds available for withdrawal");
        
        emit WithdrawalProcessed(msg.sender, amount);
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        pendingWithdrawals[msg.sender] = 0;
    }
    
    function getSlotDetails(uint256 slotId) external view returns (
        string memory equipmentName,
        string memory description,
        uint256 timeSlotHours,
        uint256 currentBid,
        address currentBidder,
        bool active
    ) {
        require(slotId < slotCount, "Invalid slot ID");
        EquipmentSlot memory slot = equipmentSlots[slotId];
        return (
            slot.equipmentName, 
            slot.description, 
            slot.timeSlotHours, 
            slot.currentBid, 
            slot.currentBidder, 
            slot.active
        );
    }
    
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    function getPendingWithdrawal(address user) external view returns (uint256) {
        return pendingWithdrawals[user];
    }
    
    function getTotalSlots() external view returns (uint256) {
        return slotCount;
    }
    
    function isAuctionActive() external view returns (bool) {
        return block.timestamp < auctionEndTime && !emergencyShutdown;
    }
    
    function getTimeRemaining() external view returns (uint256) {
        if (block.timestamp >= auctionEndTime) {
            return 0;
        }
        return auctionEndTime - block.timestamp;
    }
    
    function getWinner(uint256 slotId) external view returns (address winner, uint256 winningBid) {
        require(slotId < slotCount, "Invalid slot ID");
        require(block.timestamp >= auctionEndTime || emergencyShutdown, "Auction still active");
        
        EquipmentSlot memory slot = equipmentSlots[slotId];
        return (slot.currentBidder, slot.currentBid);
    }
    
    function emergencyShutdownAuction() external onlyOwner {
        emergencyShutdown = true;
        emit EmergencyShutdown(msg.sender);
    }
    
    function collectCommissions() external onlyOwner {
        require(block.timestamp >= auctionEndTime || emergencyShutdown, "Auction still active");
        
        uint256 totalCommissions = 0;
        for (uint256 i = 0; i < slotCount; i++) {
            if (equipmentSlots[i].currentBidder != address(0)) {
                totalCommissions += (equipmentSlots[i].currentBid * 10) / 100;
            }
        }
        
        if (totalCommissions > 0 && totalCommissions <= address(this).balance) {
            payable(owner).transfer(totalCommissions);
        }
    }
    
    function updateEquipmentDescription(uint256 slotId, string memory newDescription) external onlyOwner {
        require(slotId < slotCount, "Invalid slot ID");
        equipmentSlots[slotId].description = newDescription;
    }
}