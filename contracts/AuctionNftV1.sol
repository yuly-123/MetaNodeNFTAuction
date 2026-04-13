// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-4.7.3/security/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AuctionNftV1 is Initializable, ReentrancyGuard
{
    struct Auction {
        IERC20 paymentToken;            // 竞价使用的代币合约地址
        IERC721 nft;                    // 要拍卖的 nft 代币的 合约地址
        address seller;                 // 要拍卖的 nft 代币的 卖家地址
        uint256 tokenId;                // 要拍卖的 nft 代币的 tokenId
        uint256 startingTime;           // 拍卖开始时间
        uint256 startingDollar;         // 拍卖起始价格，单位为美元，精确到小数点后8位，比如 100.12345678 美元，就存储为 10012345678
        uint256 duration;               // 拍卖持续时间，单位为秒
        uint256 highestBidToken;        // 最高竞价，单位为代币，ETH 或 ERC20
        uint256 highestBidDollar;       // 最高竞价，单位为美元，精确到小数点后8位，比如 100.12345678 美元，就存储为 10012345678
        address highestBidderEth;       // 最高竞价者，ETH 账户地址
        address highestBidderErc20;     // 最高竞价者，ERC20 代币地址
    }
    address public admin;                                           // 管理员地址
    uint256 public auctionId;                                       // 第几场拍卖，默认值0
    mapping(uint256 auctionId => Auction auction) public auctions;  // 拍卖数组
    mapping(address => address) public tokenToOracle;               // 代币地址 => 价格预言机地址，拍卖合约通过价格预言机获取代币的美元价格

    event StartBid(uint256 indexed auctionId, address nft, address seller, uint256 tokenId);    // 发起拍卖事件
    event Bid(uint256 indexed auctionId, address sender, uint256 amount);                       // 竞价事件
    event EndBid(uint256 indexed auctionId, address highestBidder, uint256 highestBidDollar);   // 结束拍卖事件
    event Aggregator(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);  // 价格预言机事件

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }
    // 初始化，禁止使用，
    constructor() {
       _disableInitializers();
    }
    // 初始化，代理合约调用，
    function initialize(address admin_) external initializer {
        require(admin_ != address(0), "invalid admin");
        admin = admin_;
    }
    // 设置代币的价格预言机地址，拍卖合约通过价格预言机获取代币的美元价格，必须是 Chainlink 价格预言机，且该预言机必须返回美元价格。
    function setTokenOracle(address token, address oracle) external onlyAdmin {
        require(oracle != address(0), "invalid oracle");
        tokenToOracle[token] = oracle;
    }
    // 发起拍卖
    function start(address paymentToken, address nft, address seller, uint256 tokenId, uint256 startingDollar, uint256 duration) external onlyAdmin {
        require(paymentToken != address(0), "invalid paymentToken");
        require(nft != address(0), "invalid nft");
        require(seller != address(0), "invalid seller");
        require(startingDollar > 0, "invalid startingDollar");
        require(duration >= 30, "invalid duration");

        Auction storage auction = auctions[auctionId];      // 构建拍卖数组，auctionId从0开始，每拍卖一场，auctionId就加1。
        auction.paymentToken = IERC20(paymentToken);
        auction.nft = IERC721(nft);
        auction.seller = seller;
        auction.tokenId = tokenId;
        auction.startingTime = block.timestamp;
        auction.startingDollar = startingDollar * 10**8;    // Chainlink 价格预言机的价格精度是 8 位小数，所以这里把起拍价也转换成 8 位小数
        auction.duration = duration;
        auction.highestBidToken = 0;
        auction.highestBidDollar = 0;
        auction.highestBidderEth = address(0);
        auction.highestBidderErc20 = address(0);

        IERC721(nft).transferFrom(seller, address(this), tokenId);  // 要拍卖的 tokenId 从卖家转到本合约，需提前授权本合约可操作。
        auctionId++;
        emit StartBid(auctionId - 1, nft, seller, tokenId);
    }

    // 竞价
    // auctionId_ : 拍卖场次
    // amount : 竞价金额
    function bid(uint256 auctionId_, uint256 amount) external payable nonReentrant {
        Auction storage auction = auctions[auctionId_];     // 拍卖数组
        require(block.timestamp < auction.startingTime + auction.duration, "ended");
        require(amount > 0, "amount must greater than 0");
        require(msg.sender != auction.seller, "seller cannot bid");
        require(msg.sender != auction.highestBidderEth, "already highest bidder");
        require(msg.sender != auction.highestBidderErc20, "already highest bidder");

        // 如果有人出过价，给上一个最高竞价者退款，退 ETH 还是 ERC20
        if (auction.highestBidderEth != address(0)) {
            if (auction.highestBidderErc20 == address(0)) {
                (bool success, ) = payable(auction.highestBidderEth).call{value: auction.highestBidToken}("");
                require(success, "refund failed");
            } else {
                bool success = IERC20(address(auction.paymentToken)).transfer(auction.highestBidderErc20, auction.highestBidToken);
                require(success, "refund failed");
            }
        }

        uint256 bidPrice;       // 竞价金额，单位为美元
        if (msg.value > 0) {    // ETH 竞价，还是 ERC20 竞价
            require(amount == msg.value, "amount mismatch");
            uint256 tokenPrice = getPriceInDollar(address(0));              // 获取 ETH 的美元价格，本合约中，美元价格都精确到小数点后8位。
            uint8 tokenDecimals = 18;                                       // ETH 的 decimals
            bidPrice = (amount * tokenPrice) / (10 ** tokenDecimals);       // amount 是 ETH 的最小单位 Wei，黄金准则：先乘后除。
            require(bidPrice > auction.startingDollar, "eth amount must greater than startingDollar");      // 出价大于起拍价格
            require(bidPrice > auction.highestBidDollar, "eth amount must greater than highestBidDollar");  // 出价大于最高价格

            auction.highestBidToken = msg.value;
            auction.highestBidDollar = bidPrice;
            auction.highestBidderEth = msg.sender;
            auction.highestBidderErc20 = address(0);    // ETH 竞价，最高竞价者 ERC20 地址置空
        } else {
            IERC20(address(auction.paymentToken)).transferFrom(msg.sender, address(this), amount);  // 付款的 ERC20 从买家转到本合约，需提前授权本合约可操作。
            uint256 tokenPrice = getPriceInDollar(address(auction.paymentToken));                   // 获取 ERC20 的美元价格，
            uint8 tokenDecimals = IERC20Metadata(address(auction.paymentToken)).decimals();         // ERC20 的 decimals
            bidPrice = (amount * tokenPrice) / (10 ** tokenDecimals);                               // amount 是 ERC20 的最小单位，黄金准则：先乘后除。
            require(bidPrice > auction.startingDollar, "erc20 amount must greater than startingDollar");      // 出价大于起拍价格
            require(bidPrice > auction.highestBidDollar, "erc20 amount must greater than highestBidDollar");  // 出价大于最高价格

            auction.highestBidToken = amount;
            auction.highestBidDollar = bidPrice;
            auction.highestBidderEth = address(0);      // erc20 竞价，最高竞价者 ETH 地址置空
            auction.highestBidderErc20 = msg.sender;
        }

        emit Bid(auctionId_, msg.sender, amount);
    }

    // 结束拍卖，tokenId 转给最高竞价者，tokenId 的卖家收钱，收 ETH 还是 ERC20
    function end(uint256 auctionId_) external nonReentrant {
        Auction storage auction = auctions[auctionId_];
        require(block.timestamp > auction.startingTime + auction.duration, "not ended");
        require(auction.highestBidderEth != address(0), "no bids"); // 至少有一个竞价者，才能结束拍卖

        // tokenId 转给最高竞价者，需提前授权本合约可操作。
        auction.nft.transferFrom(address(this), auction.highestBidderEth, auction.tokenId);

        if (auction.highestBidderErc20 == address(0)) {
            (bool success, ) = payable(auction.seller).call{value: auction.highestBidToken}("");
            require(success, "refund failed");
        } else {
            bool success = IERC20(address(auction.paymentToken)).transfer(auction.seller, auction.highestBidToken);
            require(success, "refund failed");
        }

        emit EndBid(auctionId_, auction.highestBidderEth, auction.highestBidDollar);
    }

    function getPriceInDollar(address token) public returns (uint256) {
        address oracle = tokenToOracle[token];
        require(oracle != address(0), "oracle not set");
        AggregatorV3Interface dataFeed = AggregatorV3Interface(oracle);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = dataFeed.latestRoundData();
        emit Aggregator(roundId, answer, startedAt, updatedAt, answeredInRound);    // 价格预言机事件，方便测试验证。
        return uint256(answer);
    }

    function getVersion() external pure virtual returns (string memory) {
        return "AuctionNft V1";
    }
}
