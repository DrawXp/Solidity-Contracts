import { useAccount, useReadContract, useWriteContract, usePublicClient } from "wagmi"
import { useEffect, useMemo, useRef, useState } from "react"
import { formatUnits, parseUnits, type Hex } from "viem"
import toast from "react-hot-toast"
// ... imports (hooks, ABIs, utils)

// ... helper functions (fmtDur, short, toDateTime) omitted

export default function SafidoPrize() {
  const { address } = useAccount()
  const publicClient = usePublicClient()
  const { writeContractAsync, isPending } = useWriteContract()
  
  // Custom hook for gamified yield distribution
  const { pending, claim, claimable } = useVaultReward()

  // ... (Contract Reads: ticketPrice, currentRound, pot size omitted)

  // Real-time Countdown Logic
  const [nowSec, setNowSec] = useState(() => Math.floor(Date.now() / 1000))
  useEffect(() => {
    const t = setInterval(() => setNowSec(Math.floor(Date.now() / 1000)), 1000)
    return () => clearInterval(t)
  }, [])
  
  const eta = useMemo(() => (endTs ? Math.max(0, endTs - nowSec) : null), [endTs, nowSec])
  
  // ⚡ SMART REFETCHING: Detects round transition to sync UI with Blockchain latency
  const prevEtaRef = useRef<number | null>(null)
  useEffect(() => {
    const prev = prevEtaRef.current
    prevEtaRef.current = eta
    if (eta === null) return

    // If countdown hits zero, trigger staggered refetches to ensure data availability
    if (prev !== null && prev > 0 && eta === 0) {
      setTimeout(() => { refetchCurrentRound(); refetchCurId() }, 500)
      setTimeout(() => { refetchCurrentRound(); refetchCurId() }, 3000)
      setTimeout(() => { refetchCurrentRound(); refetchCurId() }, 8000)
    }
  }, [eta, refetchCurrentRound, refetchCurId])

  // ... (Winner verification logic omitted)

  // ⚡ COMPLEX DATA PARSING: Handling dynamic extra rewards (Tokens/NFTs) from Solidity arrays
  useEffect(() => {
    if (lastId <= 0 || !isWinner || lastClaimed) return

    let cancelled = false
    async function loadExtras() {
      if (!publicClient) return
      setExtrasLoading(true)
      
      try {
        // Raw read of dynamic tuple data
        const res = (await publicClient.readContract({
          address: LUCK_ADDR,
          abi: LuckAbi,
          functionName: "viewRoundExtras",
          args: [BigInt(lastId)],
        })) as any
        
        const tokens = (res?.tokens ?? []) as `0x${string}`[]
        const amounts = (res?.amounts ?? []) as bigint[]

        // Parallel fetching of metadata for unknown tokens
        const items: string[] = []
        for (let i = 0; i < tokens.length; i++) {
          const token = tokens[i]
          const amt = amounts[i] ?? 0n
          if (!token || amt === 0n) continue

          try {
             // Resolves Symbol and Decimals on-the-fly
            const [sym, dec] = await Promise.all([
              publicClient.readContract({ ...contractToken, functionName: "symbol" }),
              publicClient.readContract({ ...contractToken, functionName: "decimals" }),
            ])
            // ... formatting logic
            items.push(`${human} ${sym}`)
          } catch {}
        }
        if (!cancelled) setExtraPrizesHuman(items)
      } catch {
        // ... error handling
      }
    }
    loadExtras()
    return () => { cancelled = true }
  }, [publicClient, lastId, isWinner])

  // ...

  // ⚡ UX OPTIMIZATION: Auto-Approve flow
  async function buyTickets() {
    if (!address || qtyInt === 0) return
    
    // Check allowance before transaction
    if (needApprove) {
        await approveTickets() // Handles approval tx first
    }
    
    // Execute Buy
    const h = (await writeContractAsync({
      chainId: CHAIN_ID,
      abi: LuckAbi,
      address: LUCK_ADDR,
      functionName: "buyTickets",
      args: [qtyInt],
    } as any)) as Hex
    showTxToast(h)
  }

  return (
    <div className="page-card space-y-4">
       {/* ... Header and Pot Display */}
       
       {/* Conditional Rendering based on Protocol State */}
       <div className="flex flex-wrap items-stretch justify-center gap-3">
          <button
            onClick={buyTickets}
            disabled={isPending || qtyInt === 0}
            className="btn-primary..."
          >
            <span>Buy tickets</span>
          </button>
          
          {/* Input for Quantity */}
          <input
            className="input-type"
            value={qty}
            onChange={(e) => setQty(...)}
          />

          {/* Claim Button with intelligent disabled states (Expired/Not Winner) */}
          <button
            onClick={claimLottery}
            className={canClaimLottery ? "btn-rgb" : "btn-primary-wip"}
            disabled={!canClaimLottery || isPending}
            title={canClaimLottery ? "" : expired ? "Expired on-chain" : "Not eligible"}
          >
            Claim prize
          </button>
       </div>

       {/* ... Dynamic List of Extra Prizes */}
       {canClaimLottery && !extrasLoading && extraPrizesHuman.length > 0 && (
          <div className="text-xs mt-1">
            <div className="font-semibold">Extra prize:</div>
            <ul>
              {extraPrizesHuman.map((line) => <li key={line}>{line}</li>)}
            </ul>
          </div>
       )}

       {/* ... Footer Stats */}
    </div>
  )
}
