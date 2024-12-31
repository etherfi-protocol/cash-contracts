import SafeApiKit from "@safe-global/api-kit";
import Safe from "@safe-global/protocol-kit";
import {MetaTransactionData, OperationType} from "@safe-global/types-kit";
import {config} from "dotenv";

config();

async function propose() {
    const args = process.argv;
    const message = args[2];

    const scrollRpc = process.env.SCROLL_RPC;
    const proposerPrivateKey = process.env.PROPOSER_PRIVATE_KEY;
    const proposerAddress = process.env.PROPOSER_ADDRESS;
    const recoverySafeAddress = "0xa265C271adbb0984EFd67310cfe85A77f449e291";
    const safeSignMessageLib = "0xd53cd0aB83D845Ac265BE939c57F53AD838012c9";
    
    if (scrollRpc === undefined) throw new Error("SCROLL_RPC not found in .env");
    if (proposerPrivateKey === undefined) throw new Error("PROPOSER_PRIVATE_KEY not found in .env");
    if (proposerAddress === undefined) throw new Error("PROPOSER_ADDRESS not found in .env");
    
    const apiKit = new SafeApiKit({
        chainId: 534352n
    });
    
    const protocolKitOwner1 = await Safe.init({
        provider: scrollRpc,
        signer: proposerPrivateKey,
        safeAddress: recoverySafeAddress
    });

    const safeTransactionData: MetaTransactionData = {
        to: safeSignMessageLib,
        value: "0", 
        data: "0x85a5affe00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020" + message.slice(2),
        operation: OperationType.DelegateCall
    };
    
    const safeTransaction = await protocolKitOwner1.createTransaction({
        transactions: [safeTransactionData]
    });
    
    const safeTxHash = await protocolKitOwner1.getTransactionHash(safeTransaction);
    const signature = await protocolKitOwner1.signHash(safeTxHash);
    
    await apiKit.proposeTransaction({
        safeAddress: recoverySafeAddress,
        safeTransactionData: safeTransaction.data,
        safeTxHash,
        senderAddress: proposerAddress,
        senderSignature: signature.data
    });
}

propose();