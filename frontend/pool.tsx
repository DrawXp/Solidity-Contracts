import { useEffect, useMemo, useState } from "react";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { formatUnits, parseUnits, type Hex } from "viem";
import toast from "react-hot-toast";
// ... ABI imports and constants

type PairItem = {
  pair: `0x${string}`;
  t0: `0x${string}`;
  sym0: string;
  dec0: number;
  // ... strict typing for data safety
  hasLiq: boolean;
};

export default function Pool() {
  const { address } = useAccount();
  const { writeContractAsync, isPending } = useWriteContract();
  
  // ... (Hooks for reading reserves and balances omitted)

  // AMM Logic Example: Reactive input calculation based on reserves (Price Impact)
  useEffect(() => {
    if (!selected) return;
    if (editAdd !== "A") return; // Only calculate if user is editing field A
    if (r.rA === 0n || r.rB === 0n) return;
    if (!debouncedAIn) return;

    try {
      // Unit conversion and ratio calculation based on pair reserves
      const aWei = parseUnits(debouncedAIn, decA);
      const bWei = (aWei * r.rB) / r.rA; 
      setBIn(fixedDown(formatUnits(bWei, decB), 8));
    } catch {}
  }, [editAdd, aIn, debouncedAIn, selected, r.rA, r.rB]);

  // ...

  // Contract interaction: LP Token Approval
  async function approveLP() {
    if (!address || !ADDR.router || !selected) return;
    try {
      setIsApprovingLP(true);
      const tx = await writeContractAsync({
        chainId: CHAIN_ID,
        abi: ERC20Abi,
        address: selected.pair,
        functionName: "approve",
        args: [ADDR.router as `0x${string}`, (2n ** 255n) - 1n], // Infinite Approval
      });

      // Visual feedback for pending and successful transactions
      const hash = tx as Hex;
      showTxToast(hash);
      await pub.waitForTransactionReceipt({ hash });
      
      setTimeout(() => {
        setIsApprovingLP(false);
        setLpRecentlyApproved(true);
      }, 1200);
    } catch (err: any) {
      setIsApprovingLP(false);
      toast.error(err?.shortMessage || "Approve LP failed");
    }
  }

  // ...

  // Core Liquidity Addition Logic (Smart Routing)
  async function addLiquidity() {
    if (!selected || !ADDR.router) return;
    if (aAmt === 0n || bAmt === 0n) return;

    try {
      const [t0, t1] = [selected.t0, selected.t1];
      const w = ADDR.wphrs.toLowerCase();
      let tx: Hex | string;

      // Detects if pair involves Native Token (Wrapper) or standard ERC20
      if (t0.toLowerCase() === w || t1.toLowerCase() === w) {
        const phrsIsA = t0.toLowerCase() === w;
        const phrsAmt = phrsIsA ? aAmt : bAmt;
        const tokenAmt = phrsIsA ? bAmt : aAmt;
        const tokenAddr = phrsIsA ? t1 : t0;

        tx = await writeContractAsync({
          chainId: CHAIN_ID,
          abi: RouterAbi,
          address: ADDR.router,
          functionName: "addLiquidityPHRS", // Calls specific function for native tokens
          args: [tokenAddr, tokenAmt],
          value: phrsAmt,
        });
      } else {
        tx = await writeContractAsync({
          chainId: CHAIN_ID,
          abi: RouterAbi,
          address: ADDR.router,
          functionName: "addLiquidity", // Calls standard ERC20 function
          args: [t0, t1, aAmt, bAmt],
        });
      }
      
      const hash = tx as Hex;
      showTxToast(hash);
      await pub.waitForTransactionReceipt({ hash });
      await refreshSelected(); // Updates UI after block confirmation
    } catch (err: any) {
      toast.error(err?.shortMessage || "Add liquidity failed");
    }
  }

  // ...

  return (
    // ...
    // Conditional Button Rendering (Approval vs Execution State)
    {needsLpApproval ? (
      <button
        type="button"
        onClick={approveLP}
        disabled={isPending || isApprovingLP}
        className={isApprovingLP ? "btn-primary-wip" : "btn-primary"}
      >
        {isApprovingLP ? (
          <span className="flex items-center justify-center gap-2">
            <span className="animate-spin..." /> Waiting approval
          </span>
        ) : ( "Approve LP" )}
      </button>
    ) : (
      <button
        type="button"
        onClick={removeLiquidity}
        disabled={remDisabled}
        className="btn-primary"
      >
        Remove liquidity
      </button>
    )}
    // ...
  );
}
