import { ethers } from "ethers";
import * as dotenv from "dotenv";
import { Pool } from "pg";

dotenv.config();

// ... database connection pool configuration

// Security: Validates Private Key format before usage
function normalizePk(raw: string) {
  const s = (raw || '').replace(/^['"]|['"]$/g, '').trim();
  // ... validation logic (regex checks)
  return s.startsWith('0x') ? s : ('0x' + s);
}

// Secure Signer Factory
export function requireSigner() {
  const raw = String(process.env.OWNER_PK || '');
  
  if (!raw) {
      // ... logging missing env var
      throw new Error('Critical: Backend signer missing configuration');
  }
  
  const pk = normalizePk(raw);
  // Returns authorized Wallet instance connected to Provider
  return new ethers.Wallet(pk, provider);
}

// ... other environment exports (RPC_URL, CHAIN_ID, CONTRACT_ADDRESSES)
