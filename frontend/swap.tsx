import { useEffect, useMemo, useState } from "react"
import { useAccount, useWriteContract, useReadContracts, usePublicClient } from "wagmi"
import { parseUnits, formatUnits, type Hex } from "viem"
import toast from "react-hot-toast"
// ... imports (ABIs, API types, Constants)

// Core AMM Math: Constant Product Formula (x * y = k)
function getAmountOutUniV2(amountIn: bigint, reserveIn: bigint, reserveOut: bigint): bigint {
  if (amountIn <= 0n || reserveIn <= 0n || reserveOut <= 0n) return 0n
  const feeNum = 997n // 0.3% fee
  const feeDen = 1000n
  const amountInWithFee = amountIn * feeNum
  const num = amountInWithFee * reserveOut
  const den = reserveIn * feeDen + amountInWithFee
  return den <= 0n ? 0n : num / den
}

export default function Swap() {
  const pub = usePublicClient()
  const { writeContractAsync, isPending } = useWriteContract()

  // ⚡ PERFORMANCE: LocalStorage caching for Token Metadata (prevents UI flicker)
  const [catalog, setCatalog] = useState<Record<string, TokenMeta>>(() => {
    try {
      const raw = window.localStorage.getItem(CATALOG_STORAGE_KEY)
      return raw ? JSON.parse(raw) : INITIAL_CATALOG
    } catch { return INITIAL_CATALOG }
  })

  // ... (Data fetching for pairs and reserves omitted)

  // 🧠 ALGORITHM: Client-side Pathfinding (BFS) to find routes between tokens
  // Avoids external API dependency for routing
  function findRoute(aKey: string, bKey: string): `0x${string}`[] | undefined {
    const a = addrForKey(aKey)
    const b = addrForKey(bKey)
    
    // Direct Pair Check
    if (hasPair(a, b)) return [a, b]

    // Multi-hop routing (Graph Traversal)
    const vis = new Set<string>([a])
    const q: string[] = [a]
    const parent = new Map<string, string>()
    
    while (q.length) {
      const cur = q.shift()!
      if (!neighbors.has(cur)) continue
      
      for (const nb of neighbors.get(cur)!) {
        if (vis.has(nb)) continue
        vis.add(nb)
        parent.set(nb, cur)
        
        if (nb === b) {
          // Reconstruct path backwards
          const path = [b]
          let x = b
          while (parent.has(x)) {
            x = parent.get(x)!
            path.push(x)
          }
          return path.reverse().length <= 3 ? path as `0x${string}`[] : undefined
        }
        q.push(nb)
      }
    }
    return undefined
  }

  // ⚡ REACTIVE ENGINE: Calculates Output Amount across multiple Hops
  const outWei = useMemo(() => {
    if (!path || !hop0Resv) return 0n

    // Hop 0 Calculation
    const [r0, r1] = hop0Resv as [bigint, bigint, number]
    const reserveIn = inIs0 ? r0 : r1
    const reserveOut = inIs0 ? r1 : r0
    
    if (path.length === 2) {
      return getAmountOutUniV2(amtInWei, reserveIn, reserveOut)
    }

    // Hop 1 Calculation (Multi-hop)
    if (path.length === 3 && hop1Resv) {
      const midAmount = getAmountOutUniV2(amtInWei, reserveIn, reserveOut)
      if (midAmount === 0n) return 0n

      const [r0b, r1b] = hop1Resv as [bigint, bigint, number]
      const reserveIn1 = midIs0 ? r0b : r1b
      const reserveOut1 = midIs0 ? r1b : r0b
      
      return getAmountOutUniV2(midAmount, reserveIn1, reserveOut1)
    }
    return 0n
  }, [amtInWei, path, hop0Resv, hop1Resv])

  // ... (Slippage and Price Impact logic omitted)

  // 🛡️ SECURITY: Execution Guard
  async function doSwap() {
    if (!address || amtInWei === 0n) return

    // 1. Re-fetch data to prevent "Stale Price" attacks/failures
    if (isRouterSwap) {
      setIsRecalcChecking(true)
      const fresh = await refetchHops()
      
      // Calculate diff between UI price and Real-time Chain price
      const freshOut = calculateFreshOut(fresh.data) 
      const diffBps = calculateDiff(lastQuotedOutWei, freshOut)

      if (diffBps > 100n) { // If price moved > 1% in last second
         toast.error("Price updated. Please confirm new quote.")
         setAmountOut(formatUnits(freshOut, toDec))
         setIsRecalcChecking(false)
         return
      }
    }

    try {
      // 2. Handle Native Wrapping/Unwrapping
      if (isWrap) {
        await writeContractAsync({ ...WPHRSAbi, functionName: "deposit", value: amtInWei })
        return
      }

      // 3. Router Swap Execution
      const hash = await writeContractAsync({
        address: ADDR.router,
        abi: RouterAbi,
        functionName: "swapExactTokensForTokens",
        args: [amtInWei, minOutWei, path, address, deadline],
      })
      showTxToast(hash)
    } catch (e: any) {
      toast.error(e?.shortMessage || "Swap failed")
    } finally {
      setIsRecalcChecking(false)
    }
  }

  return (
    <div className="page-card space-y-4">
      {/* UI: Token Selectors & Inputs */}
      <div className="panel-card">
         {/* ... From Input Component */}
         {/* ... To Input Component */}
         
         {/* Route Visualization */}
         {isRouterSwap && path && (
            <div className="text-xs opacity-80 text-center">
               Route: {routeLabels.join(" → ")}
            </div>
         )}
      </div>

      {/* UI: Slippage & Price Impact settings */}
      
      {/* Action Button with Dynamic State */}
      <button
        onClick={doSwap}
        disabled={disabled || isRecalcChecking}
        className={disabled ? "btn-primary-wip" : "btn-primary"}
      >
        {isRecalcChecking 
          ? "Verifying price..." 
          : isWrap ? "Wrap" : `Swap ${fromLabel} → ${toLabel}`
        }
      </button>
    </div>
  )
}
