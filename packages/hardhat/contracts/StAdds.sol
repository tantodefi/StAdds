// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./lib/Errors.sol";
import "./lib/Events.sol"; 

/**@title StAdds
 * A contract that keeps track of published data
 */ 
contract StAdds is Events {
  // users can add Published Data every 10 minutes
  uint256 public constant timeLock = 10 minutes;
  address public owner;
  address public pendingOwner;

  // Elliptic Curve point
  struct Point {
    bytes32 x;
    bytes32 y;
  }
  struct PublishedData {
    bytes32 x;
    bytes32 y;
    address creator;
  }

  mapping (address => Point) publicKeys;
  mapping (address => PublishedData[]) publishedData;
  // cheaper than iterating over big arrays
  mapping (bytes => bool) isPublishedDataProvided;
  mapping (address => uint256) timeStamps;

  constructor() payable {
    owner = msg.sender;
  }

  /**
   * @dev Only sender can provide their public key
   * @param publicKeyX - x coordinate of the public key
   * @param publicKeyY - y coordinate of the public key
   */
  function addPublicKey(bytes32 publicKeyX, bytes32 publicKeyY) external {
    if (isPubKeyProvided(msg.sender)) revert Errors.PublicKeyProvided();
    bytes memory publicKey = abi.encodePacked(publicKeyX, publicKeyY);
    // 0x00FF... is a mask to get the address from the hashed public key
    bool isSender = (uint256(keccak256(publicKey)) & 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == uint256(uint160(msg.sender));
    if (!isSender) revert Errors.NotSender();
    publicKeys[msg.sender] = Point(publicKeyX, publicKeyY);
    emit NewPublicKey(msg.sender, publicKeyX, publicKeyY);
  }

  /**
   * @dev Remove sender's public key
   */
  function removePublicKey() external {
    if (!isPubKeyProvided(msg.sender)) revert Errors.PublicKeyNotProvided();
    delete publicKeys[msg.sender];
    emit PublicKeyRemoved(msg.sender);
  }

  /**
   * @dev Add published data
   * @param receiver - address of the receiver
   * @param publishedDataX - x coordinate of the published data
   * @param publishedDataY - y coordinate of the published data
   * @notice this creates a link between the sender and the receiver
   */
  function addPublishedData(
    address receiver,
    bytes32 publishedDataX, 
    bytes32 publishedDataY
  ) external {
    if (doesPublishedDataExist(
      publishedDataX, 
      publishedDataY
    )) revert Errors.PublishedDataExists();
    uint256 allowedTime = timeStamps[msg.sender];
    if (allowedTime != 0 && allowedTime > block.timestamp) revert Errors.PublishedDataCooldown();
    publishedData[receiver].push(PublishedData(
      publishedDataX, 
      publishedDataY,
      msg.sender
    ));
    timeStamps[msg.sender] = block.timestamp + timeLock;
    emit NewPublishedData(msg.sender, receiver, publishedDataX, publishedDataY); 
  }

  /**
   * @dev Remove published data
   * @param index - index of the published data
   * in the publishedData mapping
   */
  function removePublishedData(uint256 index) external {
    PublishedData[] storage PDs = publishedData[msg.sender];
    uint256 len = PDs.length;
    if (len == 0 || index >= len) revert Errors.WrongIndex();
    bytes32 PDx = PDs[index].x;
    bytes32 PDy = PDs[index].y;
    if (PDx == 0 && PDy == 0) revert Errors.WrongIndex();
    delete PDs[index];
    bytes memory data = abi.encodePacked(PDx, PDy);
    delete isPublishedDataProvided[data];
    emit PublishedDataRemoved(msg.sender, index);
  }

  function withdraw() external payable OnlyOwner {
    uint256 funds = address(this).balance;
    if (funds == 0) revert Errors.NotEnoughMATIC();
    (bool s,) = msg.sender.call{value: funds}("");
    if (!s) revert();
    emit FundsWithdrawn(msg.sender, funds);
  }

  function proposeOwner(address _addr) external payable OnlyOwner {
    pendingOwner = _addr;
    emit NewOwnerProposed(msg.sender, _addr);
  }

  function acceptOwnership() external payable {
    if (pendingOwner != msg.sender) revert Errors.NotOwner();
    owner = msg.sender;
    delete pendingOwner;
    emit OwnershipAccepted(msg.sender);
  }

  /**
   * @dev returns the public key of _addr
   */
  function getPublicKey(address _addr) external view returns (Point memory) {
    return publicKeys[_addr];
  }

  /**
   * @dev returns all published data of _addr
   */
  function getPublishedData(address _addr) external view returns (PublishedData[] memory) {
    return publishedData[_addr];
  }

  /**
   * @dev returns the timestamp of _addr
   */
  function getTimestamp(address _addr) external view returns (uint256) {
    return timeStamps[_addr];
  }

  function isPubKeyProvided(address _addr) internal view returns (bool) {
    Point storage PBK = publicKeys[_addr];
    return (PBK.x != 0 && PBK.y != 0);
  }

  function doesPublishedDataExist( 
    bytes32 dataX,
    bytes32 dataY
  ) internal view returns (bool) {
    bytes memory data = abi.encodePacked(dataX, dataY);
    return isPublishedDataProvided[data];
  } 

  modifier OnlyOwner {
    if (msg.sender != owner) revert Errors.NotOwner();
    _;
  }

  receive() external payable {}
}