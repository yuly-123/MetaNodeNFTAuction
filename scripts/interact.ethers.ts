import { ethers } from "ethers";
import hre from "hardhat";
import * as dotenv from "dotenv";
import { readFileSync } from "node:fs";
import { join } from "node:path";

dotenv.config();

function loadOzArtifact(contractName: string): { abi: any[]; bytecode: string } {
  const artifactPath = join(
    process.cwd(),
    "node_modules",
    "@openzeppelin",
    "contracts",
    "build",
    "contracts",
    `${contractName}.json`
  );
  const raw = readFileSync(artifactPath, "utf8");
  const parsed = JSON.parse(raw);
  return { abi: parsed.abi, bytecode: parsed.bytecode };
}

async function main() {
  const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545");
  // 逻辑合约管理员
  // Account #0:  0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266 (10000 ETH)
  // Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
  const implAdminWallet = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider);
  // 代理合约管理员
  // Account #1:  0x70997970c51812dc3a010c7d01b50e0d17dc79c8 (10000 ETH)
  // Private Key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
  const proxyAdminWallet = new ethers.Wallet("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", provider);
  // 卖家钱包
  // Account #2:  0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc (10000 ETH)
  // Private Key: 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
  const sellerWallet = new ethers.Wallet("0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a", provider);
  // 买家钱包
  // Account #3:  0x90f79bf6eb2c4f870365e785982e1f101e93b906 (10000 ETH)
  // Private Key: 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
  const buyerWallet = new ethers.Wallet("0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6", provider);
  // 代理合约管理员地址存储在 EIP-1967 规定的这个 slot 上
  // const adminSlot = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";

  // 避免本地并发/缓存导致的 nonce 冲突
  const implAdmin = new ethers.NonceManager(implAdminWallet);
  const proxyAdmin = new ethers.NonceManager(proxyAdminWallet);
  const seller = new ethers.NonceManager(sellerWallet);
  const buyer = new ethers.NonceManager(buyerWallet);

  console.log("逻辑合约管理员地址:", implAdminWallet.address);  // 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
  console.log("代理合约管理员地址:", proxyAdminWallet.address); // 0x70997970c51812dc3a010c7d01b50e0d17dc79c8
  console.log("卖家地址:", sellerWallet.address);              // 0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc
  console.log("买家地址:", buyerWallet.address);               // 0x90f79bf6eb2c4f870365e785982e1f101e93b906

  // 部署逻辑合约
  const auctionNftV1Artifact = await hre.artifacts.readArtifact("AuctionNftV1");
  const contractFactory = new ethers.ContractFactory(auctionNftV1Artifact.abi, auctionNftV1Artifact.bytecode, implAdmin);
  const auctionNftV1 = await contractFactory.deploy();
  await auctionNftV1.waitForDeployment();
  const auctionNftV1Address = await auctionNftV1.getAddress();
  // 部署代理合约
  const initData = auctionNftV1.interface.encodeFunctionData("initialize", [implAdminWallet.address]);
  const proxyArtifact = loadOzArtifact("TransparentUpgradeableProxy");
  const proxyFactory = new ethers.ContractFactory(proxyArtifact.abi, proxyArtifact.bytecode, implAdmin);
  const proxy = await proxyFactory.deploy(auctionNftV1Address, proxyAdminWallet.address, initData);
  await proxy.waitForDeployment();
  const proxyAddress = await proxy.getAddress();

  console.log("逻辑合约地址:", auctionNftV1Address);
  console.log("代理合约地址:", proxyAddress);

  // 用代理地址当成 AuctionNftV1 来交互
  const auctionV1 = new ethers.Contract(proxyAddress, auctionNftV1Artifact.abi, implAdmin);
  console.log("auctionV1.getVersion():", await auctionV1.getFunction("getVersion")());
  console.log("auctionV1.admin():", await auctionV1.getFunction("admin")());
  console.log("auctionV1.auctionId():", await auctionV1.getFunction("auctionId")());

  // 部署 ERC20
  const erc20Artifact = await hre.artifacts.readArtifact("AuctionERC20");
  const erc20Factory = new ethers.ContractFactory(erc20Artifact.abi, erc20Artifact.bytecode, implAdmin);
  const erc20 = await erc20Factory.deploy("USDC", "USDC");
  await erc20.waitForDeployment();
  console.log("ERC20:", await erc20.getAddress());

  // 部署 ERC721
  const erc721Artifact = await hre.artifacts.readArtifact("AuctionERC721");
  const erc721Factory = new ethers.ContractFactory(erc721Artifact.abi, erc721Artifact.bytecode, implAdmin);
  const erc721 = await erc721Factory.deploy("NFT", "NFT");
  await erc721.waitForDeployment();
  console.log("ERC721:", await erc721.getAddress());

  // mint 三个 token 给卖家地址
  await erc721.getFunction("mint")(sellerWallet.address, 1);
  await erc721.getFunction("mint")(sellerWallet.address, 2);
  await erc721.getFunction("mint")(sellerWallet.address, 9);
  console.log("minted tokenIds: 1,2,9 to seller");

  // 授权代理合约地址可以操作卖家的 nft（必须由卖家发起）
  const erc721AsSeller = erc721.connect(seller);
  await erc721AsSeller.getFunction("setApprovalForAll")(proxyAddress, true);

  // 部署预言机喂价，并设置预言机地址（这里直接部署了两个 MockOracle，一个模拟 ETH/USD，一个模拟 USDC/USD）
  const ethOracleArtifact = await hre.artifacts.readArtifact("MockOracle");
  const ethOracleFactory = new ethers.ContractFactory(ethOracleArtifact.abi, ethOracleArtifact.bytecode, implAdmin);
  const ethOracle = await ethOracleFactory.deploy(3000e8);  // 3000 美元，精确到小数点后8位

  const usdcOracleArtifact = await hre.artifacts.readArtifact("MockOracle");
  const usdcOracleFactory = new ethers.ContractFactory(usdcOracleArtifact.abi, usdcOracleArtifact.bytecode, implAdmin);
  const usdcOracle = await usdcOracleFactory.deploy(1e8);   // 1 美元，精确到小数点后8位

  await auctionV1.getFunction("setTokenOracle")(ethers.ZeroAddress, await ethOracle.getAddress());
  await auctionV1.getFunction("setTokenOracle")(await erc20.getAddress(), await usdcOracle.getAddress());

  // 监听事件
  console.log("监听事件...");
  auctionV1.on("StartBid", (auctionId, nft, seller, tokenId) => {
    console.log("新拍卖启动:", { auctionId: auctionId.toString(), nft, seller, tokenId: tokenId.toString(), });
  });
  auctionV1.on("Bid", (auctionId, sender, amount) => {
    console.log("新出价:", { auctionId: auctionId.toString(), sender, amount: ethers.formatEther(amount), });
  });
  auctionV1.on("EndBid", (auctionId, highestBidder, highestBidDollar) => {
    console.log("新拍卖结束:", { auctionId: auctionId.toString(), highestBidder, highestBidDollar: ethers.formatUnits(highestBidDollar, 8), });
  });

  // 启动拍卖
  console.log("启动拍卖...");
  const tx1 = await auctionV1.getFunction("start")(await erc20.getAddress(), await erc721.getAddress(), sellerWallet.address, 1, 1, 120);
  console.log("交易哈希:", tx1.hash);
  await tx1.wait();
  console.log("启动拍卖成功");

  // 打印拍卖详情
  const auctionId = await auctionV1.getFunction("auctionId")() - 1n;
  const auctionData = await auctionV1.getFunction("auctions")(auctionId);
  console.log("\n3. 拍卖 ", auctionId, " 详情:");
  console.log("   - 竞价使用的代币合约地址:", auctionData[0]);
  console.log("   - 要拍卖的 nft 代币的 合约地址:", auctionData[1]);
  console.log("   - 要拍卖的 nft 代币的 卖家地址:", auctionData[2]);
  console.log("   - 要拍卖的 nft 代币的 tokenId:", auctionData[3]);
  console.log("   - 拍卖开始时间:", new Date(Number(auctionData[4]) * 1000).toISOString());
  console.log("   - 拍卖起始价格(美元):", ethers.formatUnits(auctionData[5], 8));
  console.log("   - 拍卖持续时间(秒):", auctionData[6].toString());
  console.log("   - 最高竞价(代币):", ethers.formatEther(auctionData[7]));
  console.log("   - 最高竞价(美元):", ethers.formatUnits(auctionData[8], 8));
  console.log("   - 最高竞价者地址(钱包):", auctionData[9]);
  console.log("   - 最高竞价者地址(代币):", auctionData[10]);

  // 出价
  const auctionV1Buyer = auctionV1.connect(buyer);
  console.log("出价...");
  const tx2 = await auctionV1Buyer.getFunction("bid")(0, ethers.parseEther("0.001"), { value: ethers.parseEther("0.001") });
  console.log("交易哈希:", tx2.hash);
  await tx2.wait();
  console.log("出价成功");

  // 结束拍卖
  await provider.send("evm_increaseTime", [Number(auctionData[6]) + 1]);  // 增加时间，确保拍卖结束
  await provider.send("evm_mine", []);
  console.log("结束拍卖...");
  const tx3 = await auctionV1.getFunction("end")(0);
  console.log("交易哈希:", tx3.hash);
  await tx3.wait();
  console.log("结束拍卖成功");

  console.log("脚本执行完成!");

  await new Promise(r => setTimeout(r, 6000));  // 强制程序暂停执行（挂起）6000 毫秒（即 6 秒）。等待事件日志输出完毕
}

// 运行脚本并处理错误
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
