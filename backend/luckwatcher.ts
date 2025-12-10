import { Contract, toUtf8Bytes } from "ethers";
import { ADDR, loadAbi } from "../config/env";
import { log } from "../libs/logger";

// Keeper service to monitor and finalize rounds automatically
async function checkRound(luckContract: Contract) {
  try {
    const id = Number(await luckContract.currentRoundId());
    if (id === 0) return;

    // Fetch on-chain data
    const r = await luckContract.currentRound();
    const now = Math.floor(Date.now() / 1000);

    // Logic 1: Finalize Round if time is up
    if (!r.finalized && now > Number(r.endTs)) {
      // Abstraction: Secret retrieval logic is hidden here
      const secret = await getSecureRoundSecret(id); 

      if (secret) {
        log(`Finalizing round ${id}...`);
        // Send transaction to blockchain
        const tx = await luckContract.finalize(toUtf8Bytes(secret));
        await tx.wait();
        log(`Round ${id} finalized: ${tx.hash}`);
      }
    }

    // Logic 2: Rollover (safety mechanism for expired rounds)
    const lastId = id - 1;
    if (lastId > 0) {
      const lr = await luckContract.rounds(BigInt(lastId));
      const cw = await luckContract.claimWindow();
      
      // Check if claim window has expired
      const expired = (!lr.finalized && now > Number(lr.endTs) + Number(cw));

      if (expired) {
        log(`Executing rollover for expired round ${lastId}`);
        const tx = await luckContract.rolloverIfExpired(BigInt(lastId));
        await tx.wait();
      }
    }
  } catch (e) {
    log("Automation Error", String(e));
  }
}
