import axios from "axios";
import { ethers } from "ethers";
import dotenv from "dotenv";
dotenv.config();

function chainIdToChainName(chainId:string) : string {
  if (chainId === "534352") return "scroll";
  else if (chainId === "42161") return "arbitrum";
  else throw new Error("Chain ID unidentified");
}

const OPEN_OCEAN_API_ENDPOINT =
  `https://open-api.openocean.finance/v3`;
const OPEN_OCEAN_ROUTER = "0x6352a56caadC4F1E25CD6c75970Fa768A3304e64";
const SELECTOR = "0x90411a32"

const ABI = [
  {
    "inputs": [
      {
        "internalType": "contract IOpenOceanCaller",
        "name": "caller",
        "type": "address"
      },
      {
        "components": [
          {
            "internalType": "contract IERC20",
            "name": "srcToken",
            "type": "address"
          },
          {
            "internalType": "contract IERC20",
            "name": "dstToken",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "srcReceiver",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "dstReceiver",
            "type": "address"
          },
          { "internalType": "uint256", "name": "amount", "type": "uint256" },
          {
            "internalType": "uint256",
            "name": "minReturnAmount",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "guaranteedAmount",
            "type": "uint256"
          },
          { "internalType": "uint256", "name": "flags", "type": "uint256" },
          { "internalType": "address", "name": "referrer", "type": "address" },
          { "internalType": "bytes", "name": "permit", "type": "bytes" }
        ],
        "internalType": "struct OpenOceanExchange.SwapDescription",
        "name": "desc",
        "type": "tuple"
      },
      {
        "components": [
          { "internalType": "uint256", "name": "target", "type": "uint256" },
          { "internalType": "uint256", "name": "gasLimit", "type": "uint256" },
          { "internalType": "uint256", "name": "value", "type": "uint256" },
          { "internalType": "bytes", "name": "data", "type": "bytes" }
        ],
        "internalType": "struct IOpenOceanCaller.CallDescription[]",
        "name": "calls",
        "type": "tuple[]"
      }
    ],
    "name": "swap",
    "outputs": [
      { "internalType": "uint256", "name": "returnAmount", "type": "uint256" }
    ],
    "stateMutability": "payable",
    "type": "function"
  }
];  

export const getData = async () => {
  const args = process.argv;
  const chainId = args[2];
  const fromAddress = args[3];
  const toAddress = args[4];
  const fromAsset = args[5];
  const toAsset = args[6];
  const fromAmount = args[7]; 
  const fromAssetDecimals = args[8];

  const data = await getOpenOceanSwapData({
    chainId,
    fromAddress,
    toAddress,
    fromAsset,
    toAsset,
    fromAmount,
    fromAssetDecimals
  });
  
  console.log(recodeSwapData(data));
};

const recodeSwapData = (apiEncodedData: string): string => {
  try {
    const cOpenOceanRouter = new ethers.Contract(
      OPEN_OCEAN_ROUTER,
      new ethers.utils.Interface(ABI)
    );

    // decode the 1Inch tx.data that is RLP encoded
    const swapTx = cOpenOceanRouter.interface.parseTransaction({
      data: apiEncodedData,
    });
    
    const encodedData = ethers.utils.defaultAbiCoder.encode(
      ["bytes4","address","tuple(uint256,uint256,uint256,bytes)[]"], 
      [SELECTOR, swapTx.args[0], swapTx.args[2]]
    );

    return encodedData;
  } catch (err: any) {
    throw Error(`Failed to recode OpenOcean swap data: ${err.message}`);
  }
}

const getOpenOceanSwapData = async ({
  chainId,
  fromAddress,
  toAddress,
  fromAsset,
  toAsset,
  fromAmount,
  fromAssetDecimals
}: {
  chainId: string;
  fromAddress: string;
  toAddress: string;
  fromAsset: string;
  toAsset: string;
  fromAmount: string;
  fromAssetDecimals: string;
}) => {
  const params = {
    inTokenAddress: fromAsset,
    outTokenAddress: toAsset,
    amount: ethers.utils.formatUnits(fromAmount.toString(), fromAssetDecimals.toString()).toString(),
    sender: fromAddress,
    account: toAddress,
    slippage: 1,
    gasPrice: 0.05,
  };

  let retries = 5;

  const API_ENDPOINT = `${OPEN_OCEAN_API_ENDPOINT}/${chainIdToChainName(chainId)}/swap_quote`;

  while (retries > 0) {
    try {
      const response = await axios.get(API_ENDPOINT, {
        params,
      });

      if (!response.data.data || !response.data.data.data) {
        console.error(response.data);
        throw Error("response is missing data.data");
      }   
      
      return response.data.data.data;
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
      throw Error(`Call to OpenOcean swap API failed: ${err.message}`);
    }
  }

  throw Error(`Call to OpenOcean swap API failed: Rate-limited`);
};

getData();