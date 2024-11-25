import SafeApiKit from '@safe-global/api-kit';
import Safe, { buildContractSignature, buildSignatureBytes, EthSafeSignature, hashSafeMessage, SigningMethod } from '@safe-global/protocol-kit'
import { config } from "dotenv";
import { ethers } from 'ethers';

config();    

export const getSignatures = async () => {
    const args = process.argv;
    const message = args[2];

    const signer = "0x7D829d50aAF400B8B29B3b311F4aD70aD819DC6E".toLowerCase();
    const signerPrivateKey = process.env.PRIVATE_KEY;
    const rpc = process.env.SCROLL_RPC;

    if (!rpc) throw new Error("Add SCROLL_RPC to .env file");
    if (!signerPrivateKey) throw new Error("Add PRIVATE_KEY to .env file");

    const recoverySafe1 = "0xbfCe61CE31359267605F18dcE65Cb6c3cc9694A7";
    const recoverySafe2 = "0xa265C271adbb0984EFd67310cfe85A77f449e291";

    const protocolKitSafe1 = await Safe.init({
        provider: rpc,
        safeAddress: recoverySafe1,
        signer: signerPrivateKey
    });
    const protocolKitSafe2 = await Safe.init({
        provider: rpc,
        safeAddress: recoverySafe2,
        signer: signerPrivateKey
    });

    let safeMessage1 = protocolKitSafe1.createMessage(message);
    let safeMessage2 = protocolKitSafe2.createMessage(message);

    // Sign the safeMessage with OWNER_1_ADDRESS
    // After this, the safeMessage contains the signature from OWNER_1_ADDRESS
    safeMessage1 = await protocolKitSafe1.signMessage(
        safeMessage1,
        SigningMethod.ETH_SIGN_TYPED_DATA_V4
    );
    safeMessage2 = await protocolKitSafe2.signMessage(
        safeMessage2,
        SigningMethod.ETH_SIGN_TYPED_DATA_V4
    );

    const signatureOwner1 = safeMessage1.signatures.get(signer) as EthSafeSignature;
    const signatureOwner2 = safeMessage2.signatures.get(signer) as EthSafeSignature;

    const apiKit = new SafeApiKit({ chainId: BigInt("534352") })
    apiKit.addMessage(recoverySafe1, {
        message: message, 
        signature: buildSignatureBytes([signatureOwner1])
    });
    apiKit.addMessage(recoverySafe2, {
        message: message, 
        signature: buildSignatureBytes([signatureOwner2])
    });

    const encodedSignatures1 = safeMessage1.encodedSignatures();
    const encodedSignatures2 = safeMessage2.encodedSignatures();

    console.log(ethers.utils.defaultAbiCoder.encode(["bytes", "bytes"], [encodedSignatures1, encodedSignatures2]))

    const isValid1 = await protocolKitSafe1.isValidSignature(
        message,
        encodedSignatures1
      )
    const isValid2 = await protocolKitSafe1.isValidSignature(
        message,
        encodedSignatures1
      )
};

getSignatures();