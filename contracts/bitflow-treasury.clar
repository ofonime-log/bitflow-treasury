;; Title: BitFlow Treasury
;; A Bitcoin-Native Decentralized Fund Management Protocol

;; Summary
;; BitFlow Treasury is a sophisticated on-chain asset management platform that transforms 
;; how communities handle collective funds on Bitcoin's Layer 2. Built with Stacks' Clarity 
;; smart contracts, it provides institutional-grade treasury operations while maintaining 
;; full decentralization and transparency.

;; Description
;; BitFlow Treasury addresses the critical need for trustless fund management in the Bitcoin 
;; ecosystem by combining the security of Bitcoin's base layer with Stacks L2's programmability.
;; The protocol enables organizations, DAOs, and investment communities to:
;;
;; Core Features:
;; - Non-Custodial Operations: Users maintain sovereignty over their assets while participating 
;;   in collective decision-making processes
;; - Democratic Governance: Token-weighted voting system ensures proportional influence based 
;;   on stake commitment
;; - Time-Lock Security: Anti-manipulation mechanisms with configurable withdrawal delays 
;;   protect against hostile actions
;; - Proposal-Driven Actions: All fund movements require community consensus through formal 
;;   proposal and voting cycles
;; - Bitcoin Settlement: Leverages Stacks' proof-of-transfer consensus for Bitcoin-grade 
;;   security guarantees
;;
;; Technical Innovation:
;; - Clarity-Based Logic: Utilizes Bitcoin's most secure smart contract language with 
;;   predictable gas costs and formal verification capabilities
;; - Block-Height Anchoring: Prevents front-running attacks by tying operations to Stacks 
;;   block confirmations
;; - Composable Architecture: Modular design allows integration with other Bitcoin DeFi 
;;   protocols and services
;; - Audit-Ready Transparency: Complete on-chain trail of all transactions and governance 
;;   decisions for regulatory compliance
;;
;; Use Cases:
;; - DAO Treasury Management for Bitcoin-focused organizations
;; - Community Investment Pools with democratic fund allocation
;; - Grant Distribution Systems with transparent approval processes
;; - Decentralized Venture Funds with collective investment strategies
;; - Multi-Stakeholder Project Funding with consensus-driven disbursements
;;
;; Security Model:
;; BitFlow Treasury implements multi-layered protection through time-delayed withdrawals,
;; proposal expiration windows, and voting threshold requirements. The protocol's design
;; eliminates single points of failure while ensuring legitimate operations can proceed
;; efficiently through community consensus.

;; CONSTANTS AND ERROR CODES

(define-constant contract-owner tx-sender)

;; Error Constants
(define-constant err-owner-only (err u100))
(define-constant err-not-initialized (err u101))
(define-constant err-already-initialized (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-proposal-not-found (err u106))
(define-constant err-proposal-expired (err u107))
(define-constant err-already-voted (err u108))
(define-constant err-below-minimum (err u109))
(define-constant err-locked-period (err u110))
(define-constant err-transfer-failed (err u111))
(define-constant err-invalid-duration (err u112))
(define-constant err-zero-amount (err u113))
(define-constant err-invalid-target (err u114))
(define-constant err-invalid-description (err u115))
(define-constant err-invalid-proposal-id (err u116))
(define-constant err-invalid-vote (err u117))

;; Protocol Constants
(define-constant minimum-duration u144) ;; Minimum 1 day (assuming 10min blocks)
(define-constant maximum-duration u20160) ;; Maximum 14 days

;; DATA VARIABLES

(define-data-var total-supply uint u0)
(define-data-var minimum-deposit uint u1000000) ;; In microSTX
(define-data-var lock-period uint u1440) ;; ~10 days in blocks
(define-data-var initialized bool false)
(define-data-var last-rebalance uint u0)
(define-data-var proposal-count uint u0)

;; DATA MAPS

(define-map balances
  principal
  uint
)

(define-map deposits
  principal
  {
    amount: uint,
    lock-until: uint,
    last-reward-block: uint,
  }
)

(define-map proposals
  uint
  {
    proposer: principal,
    description: (string-ascii 256),
    amount: uint,
    target: principal,
    expires-at: uint,
    executed: bool,
    yes-votes: uint,
    no-votes: uint,
  }
)

(define-map votes
  {
    proposal-id: uint,
    voter: principal,
  }
  bool
)

;; PRIVATE FUNCTIONS

(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (check-initialized)
  (ok (asserts! (var-get initialized) err-not-initialized))
)

(define-private (validate-proposal-id (proposal-id uint))
  (ok (asserts! (<= proposal-id (var-get proposal-count)) err-invalid-proposal-id))
)

(define-private (calculate-voting-power (voter principal))
  (default-to u0 (map-get? balances voter))
)

(define-private (transfer-tokens
    (sender principal)
    (recipient principal)
    (amount uint)
  )
  (let (
      (sender-balance (default-to u0 (map-get? balances sender)))
      (recipient-balance (default-to u0 (map-get? balances recipient)))
    )
    (asserts! (>= sender-balance amount) err-insufficient-balance)
    (map-set balances sender (- sender-balance amount))
    (map-set balances recipient (+ recipient-balance amount))
    (ok true)
  )
)

(define-private (mint-tokens
    (account principal)
    (amount uint)
  )
  (let ((current-balance (default-to u0 (map-get? balances account))))
    (map-set balances account (+ current-balance amount))
    (var-set total-supply (+ (var-get total-supply) amount))
    (ok true)
  )
)

(define-private (burn-tokens
    (account principal)
    (amount uint)
  )
  (let ((current-balance (default-to u0 (map-get? balances account))))
    (asserts! (>= current-balance amount) err-insufficient-balance)
    (map-set balances account (- current-balance amount))
    (var-set total-supply (- (var-get total-supply) amount))
    (ok true)
  )
)

;; PUBLIC FUNCTIONS

(define-public (initialize)
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (asserts! (not (var-get initialized)) err-already-initialized)
    (var-set initialized true)
    (ok true)
  )
)

(define-public (deposit (amount uint))
  (begin
    (try! (check-initialized))
    (asserts! (>= amount (var-get minimum-deposit)) err-below-minimum)
    (asserts! (> amount u0) err-zero-amount)

    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    ;; Update deposit records
    (map-set deposits tx-sender {
      amount: amount,
      lock-until: (+ stacks-block-height (var-get lock-period)),
      last-reward-block: stacks-block-height,
    })

    ;; Mint fund tokens
    (mint-tokens tx-sender amount)
  )
)

(define-public (withdraw (amount uint))
  (begin
    (try! (check-initialized))
    (asserts! (> amount u0) err-zero-amount)

    (let (
        (deposit-info (unwrap! (map-get? deposits tx-sender) err-unauthorized))
        (user-balance (unwrap! (get-balance tx-sender) err-unauthorized))
      )
      (asserts! (>= stacks-block-height (get lock-until deposit-info))
        err-locked-period
      )
      (asserts! (>= user-balance amount) err-insufficient-balance)

      ;; Burn tokens first
      (try! (burn-tokens tx-sender amount))

      ;; Transfer STX back to user
      (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender))
    )
  )
)

(define-public (create-proposal
    (description (string-ascii 256))
    (amount uint)
    (target principal)
    (duration uint)
  )
  (begin
    (try! (check-initialized))

    ;; Input validation
    (asserts! (> (len description) u0) err-invalid-description)
    (asserts! (> amount u0) err-zero-amount)
    (asserts! (not (is-eq target (as-contract tx-sender))) err-invalid-target)
    (asserts! (and (>= duration minimum-duration) (<= duration maximum-duration))
      err-invalid-duration
    )

    (let (
        (proposer-balance (unwrap! (map-get? balances tx-sender) err-unauthorized))
        (proposal-id (+ (var-get proposal-count) u1))
      )
      (asserts! (> proposer-balance u0) err-unauthorized)

      ;; Create new proposal with validated inputs
      (map-set proposals proposal-id {
        proposer: tx-sender,
        description: description,
        amount: amount,
        target: target,
        expires-at: (+ stacks-block-height duration),
        executed: false,
        yes-votes: u0,
        no-votes: u0,
      })

      (var-set proposal-count proposal-id)
      (ok proposal-id)
    )
  )
)

(define-public (vote
    (proposal-id uint)
    (vote-for bool)
  )
  (begin
    (try! (check-initialized))
    (try! (validate-proposal-id proposal-id))

    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
        (voter-power (calculate-voting-power tx-sender))
      )
      (asserts! (> voter-power u0) err-unauthorized)
      (asserts! (< stacks-block-height (get expires-at proposal))
        err-proposal-expired
      )
      (asserts!
        (is-none (map-get? votes {
          proposal-id: proposal-id,
          voter: tx-sender,
        }))
        err-already-voted
      )

      ;; Record vote after all validations pass
      (map-set votes {
        proposal-id: proposal-id,
        voter: tx-sender,
      }
        vote-for
      )

      ;; Update vote counts
      (map-set proposals proposal-id
        (merge proposal {
          yes-votes: (if vote-for
            (+ (get yes-votes proposal) voter-power)
            (get yes-votes proposal)
          ),
          no-votes: (if vote-for
            (get no-votes proposal)
            (+ (get no-votes proposal) voter-power)
          ),
        })
      )

      (ok true)
    )
  )
)

(define-public (execute-proposal (proposal-id uint))
  (begin
    (try! (check-initialized))
    (try! (validate-proposal-id proposal-id))

    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
        (contract-balance (stx-get-balance (as-contract tx-sender)))
      )
      (asserts! (not (get executed proposal)) err-unauthorized)
      (asserts! (>= stacks-block-height (get expires-at proposal))
        err-proposal-expired
      )
      (asserts! (> (get yes-votes proposal) (get no-votes proposal))
        err-unauthorized
      )
      (asserts! (>= contract-balance (get amount proposal))
        err-insufficient-balance
      )

      ;; Execute proposal (transfer funds)
      (try! (as-contract (stx-transfer? (get amount proposal) (as-contract tx-sender)
        (get target proposal)
      )))

      ;; Mark proposal as executed
      (map-set proposals proposal-id (merge proposal { executed: true }))
      (ok true)
    )
  )
)

;; READ-ONLY FUNCTIONS

(define-read-only (get-balance (account principal))
  (ok (default-to u0 (map-get? balances account)))
)

(define-read-only (get-total-supply)
  (ok (var-get total-supply))
)

(define-read-only (get-proposal (proposal-id uint))
  (ok (map-get? proposals proposal-id))
)

(define-read-only (get-deposit-info (account principal))
  (ok (map-get? deposits account))
)

(define-read-only (get-vote
    (proposal-id uint)
    (voter principal)
  )
  (ok (map-get? votes {
    proposal-id: proposal-id,
    voter: voter,
  }))
)
