import axios from "axios";
import { ethers } from "ethers";

const ONEINCH_API_ENDPOINT = "https://api.1inch.dev/swap/v6.0";
const ONEINCH_API_KEY = "v0IsPOhQWKrDo7t1IZlOFibcSN41dc2n";
const SWAP_SELECTOR = "0x07ed2379"; // swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)
const UNOSWAP_TO_SELECTOR = "0xe2c95c82"; // unoswapTo(uint256,uint256,uint256,uint256,uint256)
const UNOSWAP_TO_2_SELECTOR = "0xea76dddf"; // unoswapTo2(uint256,uint256,uint256,uint256,uint256,uint256)
const ONE_INCH_ROUTER_V6 = "0x111111125421cA6dc452d289314280a0f8842A65";

const ONE_INCH_V6_ABI = [
  {
    type: "function",
    name: "swap",
    inputs: [
      {
        name: "executor",
        type: "address",
        internalType: "contract IAggregationExecutor",
      },
      {
        name: "desc",
        type: "tuple",
        internalType: "struct SwapDescription",
        components: [
          {
            name: "srcToken",
            type: "address",
            internalType: "contract IERC20",
          },
          {
            name: "dstToken",
            type: "address",
            internalType: "contract IERC20",
          },
          {
            name: "srcReceiver",
            type: "address",
            internalType: "address payable",
          },
          {
            name: "dstReceiver",
            type: "address",
            internalType: "address payable",
          },
          { name: "amount", type: "uint256", internalType: "uint256" },
          { name: "minReturnAmount", type: "uint256", internalType: "uint256" },
          { name: "flags", type: "uint256", internalType: "uint256" },
        ],
      },
      { name: "data", type: "bytes", internalType: "bytes" },
    ],
    outputs: [
      { name: "returnAmount", type: "uint256", internalType: "uint256" },
      { name: "spentAmount", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "unoswapTo",
    inputs: [
      { name: "to", type: "uint256", internalType: "uint256" },
      { name: "token", type: "uint256", internalType: "uint256" },
      { name: "amount", type: "uint256", internalType: "uint256" },
      { name: "minReturn", type: "uint256", internalType: "uint256" },
      { name: "dex", type: "uint256", internalType: "uint256" },
    ],
    outputs: [
      { name: "returnAmount", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "unoswapTo2",
    inputs: [
      { name: "to", type: "uint256", internalType: "uint256" },
      { name: "token", type: "uint256", internalType: "uint256" },
      { name: "amount", type: "uint256", internalType: "uint256" },
      { name: "minReturn", type: "uint256", internalType: "uint256" },
      { name: "dex", type: "uint256", internalType: "uint256" },
      { name: "dex2", type: "uint256", internalType: "uint256" },
    ],
    outputs: [
      { name: "returnAmount", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
];

export const getData = async () => {
  const args = process.argv;
  const chainId = args[2];
  const fromAddress = args[3];
  const toAddress = args[4];
  const fromAsset = args[5];
  const toAsset = args[6];
  const fromAmount = args[7];

  const data = await getIInchSwapData({
    chainId,
    fromAddress,
    toAddress,
    fromAsset,
    toAsset,
    fromAmount,
  });

  console.log(recodeSwapData(data));
};

/**
 * Re-encodes the 1Inch swap data to be used by the vault's swapper.
 * The first 4 bytes are the function selector to call on 1Inch's router.
 * If calling the swap function, the next 20 bytes is the executer's address and data.
 * If calling the unoswap or uniswapV3SwapTo functions, an array of Uniswap pools are encoded.
 * @param {string} apiEncodedData tx.data from 1inch's /v6.0/1/swap API
 * @returns {string} RLP encoded data for the Vault's `swapCollateral` function
 */
const recodeSwapData = (apiEncodedData: string): string => {
  try {
    const c1InchRouter = new ethers.Contract(
      ONE_INCH_ROUTER_V6,
      new ethers.utils.Interface(ONE_INCH_V6_ABI)
    );

    // decode the 1Inch tx.data that is RLP encoded
    const swapTx = c1InchRouter.interface.parseTransaction({
      data: apiEncodedData,
    });

    // log(`parsed tx ${JSON.stringify(swapTx)}}`);

    let encodedData = "";
    if (swapTx.sighash === SWAP_SELECTOR) {
      // If swap(IAggregationExecutor executor, SwapDescription calldata desc, bytes calldata data)
      encodedData = ethers.utils.defaultAbiCoder.encode(
        ["bytes4", "address", "bytes"],
        [swapTx.sighash, swapTx.args[0], swapTx.args[2]]
      );
    } else if (swapTx.sighash === UNOSWAP_TO_SELECTOR) {
      // If unoswapTo(uint256,uint256,uint256,uint256,uint256)
      encodedData = ethers.utils.defaultAbiCoder.encode(
        ["bytes4", "uint256"],
        [swapTx.sighash, swapTx.args[4]]
      );
    } else if (swapTx.sighash === UNOSWAP_TO_2_SELECTOR) {
      // If unoswapTo(uint256,uint256,uint256,uint256,uint256)
      encodedData = ethers.utils.defaultAbiCoder.encode(
        ["bytes4", "uint256", "uint256"],
        [swapTx.sighash, swapTx.args[4], swapTx.args[5]]
      );
    } else {
      throw Error(`Unknown 1Inch tx signature ${swapTx.sighash}`);
    }

    return encodedData;
  } catch (err: any) {
    throw Error(`Failed to recode 1Inch swap data: ${err.message}`);
  }
};

/**
 * Gets the tx.data in the response of 1inch's V5 swap API
 * @param vault The Origin vault contract address. eg OUSD or OETH Vaults
 * @param fromAsset The address of the asset to swap from.
 * @param toAsset The address of the asset to swap to.
 * @param fromAmount The unit amount of fromAsset to swap. eg 1.1 WETH = 1.1e18
 * @param slippage as a percentage. eg 0.5 is 0.5%
 * @param protocols The 1Inch liquidity sources as a comma separated list. eg UNISWAP_V1,UNISWAP_V2,SUSHI,CURVE,ONE_INCH_LIMIT_ORDER
 * See https://api.1inch.io/v5.0/1/liquidity-sources
 */
const getIInchSwapData = async ({
  chainId,
  fromAddress,
  toAddress,
  fromAsset,
  toAsset,
  fromAmount,
}: {
  chainId: string;
  fromAddress: string;
  toAddress: string;
  fromAsset: string;
  toAsset: string;
  fromAmount: string;
}) => {
  const params = {
    src: fromAsset,
    dst: toAsset,
    amount: fromAmount.toString(),
    fromAddress: fromAddress,
    receiver: toAddress,
    slippage: 1,
    disableEstimate: true,
    allowPartialFill: false,
  };

  let retries = 5;

  const API_ENDPOINT = `${ONEINCH_API_ENDPOINT}/${chainId}/swap`;

  while (retries > 0) {
    try {
      const response = await axios.get(API_ENDPOINT, {
        params,
        headers: {
          Authorization: `Bearer ${ONEINCH_API_KEY}`,
        },
      });

      if (!response.data.tx || !response.data.tx.data) {
        console.error(response.data);
        throw Error("response is missing tx.data");
      }

      return response.data.tx.data;
    } catch (err: any) {
      if (err.response) {
        console.error("Response data  : ", err.response.data);
        console.error("Response status: ", err.response.status);
      }
      if (err.response?.status == 429) {
        retries = retries - 1;
        // Wait for 2s before next try
        await new Promise((r) => setTimeout(r, 2000));
        continue;
      }
      throw Error(`Call to 1Inch swap API failed: ${err.message}`);
    }
  }

  throw Error(`Call to 1Inch swap API failed: Rate-limited`);
};

getData();
