//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract TheGame is IERC721Receiver, VRFConsumerBase, Ownable {
    struct Locations {
        string name;
        uint256 lucky;
        uint256 staminaRequired;
        uint256 rewardLowerLimit;
        uint256 rewardUpperLimit;
    }
    mapping(uint256 => Locations) public _locations;

    struct PlayerLog {
        bool gameJoined;
        bool staked;
        uint256 nftId;
        uint256 locationId;
        uint256 timestamp;
        uint256 reward;
        uint256 stamina;
        uint256 status;
    }
    mapping(address => PlayerLog) public _playerlog;

    bytes32 internal keyHash;
    uint256 internal fee;

    mapping(bytes32 => address) requestToSender;

    IERC20 public gameToken;
    IERC721 public gameNFT;

    //constructor
    constructor(
        address _gameTokenAddress,
        address _gameNFTAddress,
        address _VRFcoordinator,
        address _linkToken,
        bytes32 _keyHash
    ) VRFConsumerBase(_VRFcoordinator, _linkToken) {
        gameToken = IERC20(_gameTokenAddress);
        gameNFT = IERC721(_gameNFTAddress);
        keyHash = _keyHash;
        fee = 0.0001 * 10**18;
    }

    //internal
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    //users

    function joinGame() public {
        require(
            _playerlog[msg.sender].gameJoined != true,
            "You already Joined"
        );
        _playerlog[msg.sender] = PlayerLog(true, false, 0, 0, 0, 0, 100, 0);
    }

    function startHunting(uint256 _nftId, uint256 _locationId)
        public
        payable
        returns (bytes32)
    {
        require(_playerlog[msg.sender].gameJoined, "join the game first");
        require(
            block.timestamp - _playerlog[msg.sender].timestamp > 1 minutes,
            "wait for your time"
        );
        require(
            _playerlog[msg.sender].staked != true,
            "you are already on the game"
        );
        require(
            gameNFT.ownerOf(_nftId) == msg.sender,
            "you are not owner of the NFT"
        );

        require(
            _playerlog[msg.sender].stamina >=
                _locations[_locationId].staminaRequired,
            "you don't have enough stamina"
        );

        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );

        _playerlog[msg.sender].nftId = _nftId;
        _playerlog[msg.sender].locationId = _locationId;
        _playerlog[msg.sender].timestamp = block.timestamp;

        _playerlog[msg.sender].stamina =
            _playerlog[msg.sender].stamina -
            _locations[_locationId].staminaRequired;

        bytes32 requestId = requestRandomness(keyHash, fee);
        requestToSender[requestId] = msg.sender;
        return requestId;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        uint256 totalLucky = _locations[
            _playerlog[requestToSender[requestId]].locationId
        ].lucky;
        if ((randomness % 100) <= totalLucky) {
            gameNFT.safeTransferFrom(
                requestToSender[requestId],
                address(this),
                _playerlog[requestToSender[requestId]].nftId
            );
            _playerlog[requestToSender[requestId]].staked = true;
            _playerlog[requestToSender[requestId]].status = 2;
            _playerlog[requestToSender[requestId]].reward =
                _playerlog[requestToSender[requestId]].reward +
                _locations[_playerlog[requestToSender[requestId]].locationId]
                    .rewardLowerLimit;
        } else {
            _playerlog[requestToSender[requestId]].status = 1;
        }
    }

    function redeemReward() public payable {
        require(_playerlog[msg.sender].staked);
        require(block.timestamp - _playerlog[msg.sender].timestamp > 1 minutes);

        gameNFT.safeTransferFrom(
            address(this),
            msg.sender,
            _playerlog[msg.sender].nftId
        );
        _playerlog[msg.sender].staked = false;

        gameToken.transfer(msg.sender, _playerlog[msg.sender].reward);
        _playerlog[msg.sender].reward = 0;
        _playerlog[msg.sender].status = 0;
    }

    function increaseStamina(uint256 _amount) public payable {
        gameToken.transferFrom(msg.sender, address(this), _amount);
        _playerlog[msg.sender].stamina =
            _playerlog[msg.sender].stamina +
            (_amount / 1 ether);
    }

    function getReward() public view returns (uint256) {
        return _playerlog[msg.sender].reward;
    }

    function getStamina() public view returns (uint256) {
        return _playerlog[msg.sender].stamina;
    }

    function getStatus() public view returns (uint256) {
        return _playerlog[msg.sender].status;
    }

    function getTimestamp() public view returns (uint256) {
        return _playerlog[msg.sender].timestamp;
    }

    //only owner
    function setLocations(
        uint256 _id,
        string memory _name,
        uint256 _lucky,
        uint256 _staminaRequired,
        uint256 _rewardLowerLimit,
        uint256 _rewardUpperLimit
    ) public onlyOwner {
        _locations[_id] = Locations(
            _name,
            _lucky,
            _staminaRequired,
            _rewardLowerLimit,
            _rewardUpperLimit
        );
    }

    function withdrawETH() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success);
    }

    function withdrawERC20() public payable onlyOwner {
        gameToken.transfer(msg.sender, gameToken.balanceOf(address(this)));
    }
}
