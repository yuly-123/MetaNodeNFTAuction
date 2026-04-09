// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {AuctionERC20} from "./AuctionERC20.sol";
import {AuctionERC721} from "./AuctionERC721.sol";
import {AuctionNftV1} from "./AuctionNftV1.sol";
import {AuctionNftV2} from "./AuctionNftV2.sol";

contract AuctionNftV1Test is Test
{
    AuctionERC20 private usdc;
    AuctionERC721 private nft;
    AuctionNftV1 private auctionV1;
    AuctionNftV2 private auctionV2;
    ProxyAdmin private proxyAdminInstance;

    address private implAdmin = address(0xA11CE);
    address private proxyAdmin = address(0xBEEF);   // ProxyAdmin 合约管理员地址，负责升级合约
    address private seller = address(0xB0B);
    address private bidder1 = address(0xB0123);
    address private bidder2 = address(0xB0124);

    // 在每个测试函数执行前自动调用。
    function setUp() public {
        // 部署实现合约
        AuctionNftV1 impl = new AuctionNftV1();
        // 实现合约初始化数据，调用实现合约 initialize() 函数
        bytes memory initData = abi.encodeCall(AuctionNftV1.initialize, (implAdmin));
        // 部署代理合约，传入实现合约地址，delegatecall() 到实现合约 initialize() 函数
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyAdmin, initData);

        // proxy 代理合约强制转换为实现合约，通过使用 call 调用 proxy 代理合约中不存在的函数，
        // 触发 proxy 代理合约中的fallback()函数，再 delegatecall() 到实现合约函数，
        // 实现合约函数中的 storage 操作，实际上是操作代理合约的 storage，
        auctionV1 = AuctionNftV1(address(proxy));

        // 通过计算 storage slot，读取 proxy 代理合约中的 proxyAdmin 地址
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        address proxyAdminAddress = address(uint160(uint256(vm.load(address(proxy), adminSlot))));  // ProxyAdmin 合约地址
        proxyAdminInstance = ProxyAdmin(proxyAdminAddress);

        usdc = new AuctionERC20("USDC", "USDC");

        nft = new AuctionERC721("NFT", "NFT");
        nft.mint(seller, 1);
        nft.mint(seller, 2);
        nft.mint(seller, 9);
        
        vm.startPrank(seller);
        nft.setApprovalForAll(address(auctionV1), true);
        vm.stopPrank();

        // console2.log(nft.isApprovedForAll(seller, address(auctionV1))); // 查询授权状态，应该输出 true
        // console2.log("setUp() completed");
    }

    // 测试 getVersion() 函数，应该返回 "AuctionNft V1"
    function test_getVersion() public view {
        assertEq(auctionV1.getVersion(), "AuctionNft V1");
        console2.log("auctionV1.getVersion():", auctionV1.getVersion());
    }

    // 测试 initialize() 函数只能调用一次，setUp() 函数中已经调用一次， 这里第二次调用应该 revert。
    function test_initializeOnlyOnce() public {
        vm.startPrank(implAdmin);
        vm.expectRevert();
        auctionV1.initialize(implAdmin);
        vm.stopPrank();
        console2.log("AuctionNftV1.admin:", auctionV1.admin());  // 输出管理员地址，应该是 implAdmin 地址
    }

    // 测试 start() 函数只能由管理员调用，非管理员调用应该 revert。
    function test_startOnlyAdmin() public {
        vm.startPrank(seller);
        vm.expectRevert("not admin");
        auctionV1.start(address(usdc), address(nft), seller, 1, 1000, 120);
        vm.stopPrank();
        console2.log("tokenId:", uint256(1));

        // (
        //     IERC20 paymentToken_,
        //     IERC721 nft_,
        //     address seller_,
        //     uint256 tokenId_,
        //     uint256 startingTime_,
        //     uint256 startingDollar_,
        //     uint256 duration_,
        //     uint256 highestBidToken_,
        //     uint256 highestBidDollar_,
        //     address highestBidderEth_,
        //     address highestBidderErc20_
        // ) = auctionV1.auctions(0);
        // console2.log("auctionV1.auctions[0].tokenId:", tokenId_);
    }

    // 每发起一场拍卖，auctionId 就加1，测试 auctionId 是否正确自增。
    function test_startIncrementsAuctionId() public {
        vm.startPrank(implAdmin);
        auctionV1.start(address(usdc), address(nft), seller, 1, 1000, 120);
        assertEq(auctionV1.auctionId(), 1);
        auctionV1.start(address(usdc), address(nft), seller, 2, 1000, 120);
        assertEq(auctionV1.auctionId(), 2);
        vm.stopPrank();
        console2.log("auctionV1.auctionId():", auctionV1.auctionId());
    }

    // 超过拍卖持续时间竞价
    function test_startAuctionGtDuration() public {
        vm.startPrank(implAdmin);
        auctionV1.start(address(usdc), address(nft), seller, 1, 1000, 120);
        vm.warp(block.timestamp + 1500);
        console2.log("current time : ", block.timestamp);
        vm.startPrank(seller);
        vm.deal(seller, 1 ether);   // 把 seller 地址的 ETH 余额直接设置为 1 ether
        uint256 currentAuctionId = auctionV1.auctionId() - 1;   // 当前 auctionId，start() 函数中用完会自增1，所以要减1。
        vm.expectRevert("ended");
        auctionV1.bid{value: 1 ether}(currentAuctionId, 1 ether);
        vm.stopPrank();
    }

    // 竞价金额低于当前最高竞价金额
    function test_bidLowerThanHighestBid() public {
        vm.startPrank(implAdmin);
        auctionV1.start(address(usdc), address(nft), seller, 1, 1000, 120);
        uint256 currentAuctionId = auctionV1.auctionId() - 1;
        
        vm.deal(bidder1, 2 ether);
        vm.deal(bidder2, 2 ether);
        
        vm.startPrank(bidder1);
        auctionV1.bid{value: 2 ether}(currentAuctionId, 2 ether);
        vm.startPrank(bidder2);
        vm.expectRevert("invalid amount");
        auctionV1.bid{value: 1.2 ether}(currentAuctionId, 1.2 ether);
        vm.stopPrank();
    }

    // 轮翻竞价后的结果
    function test_bidResult() public {
        vm.startPrank(implAdmin);
        auctionV1.start(address(usdc), address(nft), seller, 1, 1000, 120);
        uint256 currentAuctionId = auctionV1.auctionId() - 1;

        vm.deal(bidder1, 20 ether);
        vm.deal(bidder2, 20 ether);

        vm.startPrank(bidder1);
        auctionV1.bid{value: 2 ether}(currentAuctionId, 2 ether);
        vm.startPrank(bidder2);
        auctionV1.bid{value: 3 ether}(currentAuctionId, 3 ether);
        vm.startPrank(bidder1);
        auctionV1.bid{value: 4 ether}(currentAuctionId, 4 ether);

        (, , , , , , , uint256 highestBidToken, , address highestBidderEth, ) = auctionV1.auctions(currentAuctionId);

        assertEq(highestBidToken, 4 ether);
        assertEq(highestBidderEth, bidder1);
        vm.stopPrank();
    }

    // 测试升级到 V2 版本后，新的函数 getVersion() 和 newFeature() 是否正常工作。
    function test_upgrade() public {
        vm.startPrank(implAdmin);
        auctionV1.start(address(usdc), address(nft), seller, 9, 1000, 120);
        uint256 oldAuctionId = auctionV1.auctionId();
        vm.stopPrank();

        AuctionNftV2 newImpl = new AuctionNftV2();

        vm.prank(proxyAdmin);
        // ITransparentUpgradeableProxy(payable(address(auctionV1))).upgradeToAndCall{value: msg.value}(address(newImpl), "");
        // TransparentUpgradeableProxy 合约并未继承 ITransparentUpgradeableProxy 接口
        // 而是通过 _fallback 中的自定义分发机制隐式实现了 upgradeToAndCall。
        proxyAdminInstance.upgradeAndCall(ITransparentUpgradeableProxy(payable(address(auctionV1))), address(newImpl), "");

        AuctionNftV2 upgradedAuction = AuctionNftV2(payable(address(auctionV1)));

        assertEq(upgradedAuction.auctionId(), oldAuctionId);
        assertEq(keccak256(abi.encodePacked(upgradedAuction.getVersion())), keccak256(abi.encodePacked("AuctionNft V2")));
        
        string memory newFeature = upgradedAuction.newFeature();
        assertEq(keccak256(abi.encodePacked(newFeature)), keccak256(abi.encodePacked("This is a new feature in V2")));

        // 存储都在代理合约，并不在逻辑合约，auctionV1是代理合约地址，newImpl是新逻辑合约地址，upgradedAuction是升级后代理合约的接口类型转换，
        console2.log("auctionV1 address:", address(auctionV1));
        console2.log("newImpl address:", address(newImpl));
        console2.log("upgradedAuction address:", address(upgradedAuction));
        // console2.log("upgradedAuction.auctionId() : ", upgradedAuction.auctionId());
        // console2.log("upgradedAuction.getVersion() : ", upgradedAuction.getVersion());
        // console2.log("upgradedAuction.newFeature() : ", upgradedAuction.newFeature());
        // console2.log("newImpl.auctionId() : ", newImpl.auctionId());
        // console2.log("newImpl.getVersion() : ", newImpl.getVersion());
        // console2.log("newImpl.newFeature() : ", newImpl.newFeature());
    }

    // 测试非管理员地址升级合约，应该 revert。
    function test_upgradeByNonAdmin() public {
        vm.startPrank(implAdmin);
        auctionV1.start(address(usdc), address(nft), seller, 9, 1000, 120);
        vm.stopPrank();
        
        AuctionNftV2 newImpl = new AuctionNftV2();
        
        vm.startPrank(seller);
        vm.expectRevert();
        proxyAdminInstance.upgradeAndCall(ITransparentUpgradeableProxy(payable(address(auctionV1))), address(newImpl), "");
        vm.stopPrank();
    }
}
