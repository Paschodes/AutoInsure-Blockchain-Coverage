
;; AutoInsure Blockchain Coverage
;; Decentralized automotive insurance claims and coverage verification

(define-data-var admin principal tx-sender)

;; Policy status enum values
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-EXPIRED u2)
(define-constant STATUS-CANCELLED u3)
(define-constant STATUS-SUSPENDED u4)

;; Claim status enum values
(define-constant CLAIM-SUBMITTED u1)
(define-constant CLAIM-REVIEWING u2)
(define-constant CLAIM-APPROVED u3)
(define-constant CLAIM-REJECTED u4)
(define-constant CLAIM-PAID u5)

;; Map of insurance policies
(define-map policies
  {policy-id: uint}
  {
    owner: principal,
    vehicle-vin: (string-ascii 17),
    coverage-type: (string-ascii 50),
    start-date: uint,
    end-date: uint,
    premium-amount: uint,
    coverage-amount: uint,
    status: uint,
    last-update: uint
  }
)

;; Map of policy claims
(define-map claims
  {claim-id: uint}
  {
    policy-id: uint,
    claimant: principal,
    date-of-incident: uint,
    description: (string-ascii 500),
    amount-requested: uint,
    amount-approved: uint,
    status: uint,
    submission-date: uint,
    last-update: uint
  }
)

;; Counter for policy IDs
(define-data-var next-policy-id uint u1)

;; Counter for claim IDs
(define-data-var next-claim-id uint u1)

;; Map of authorized insurers
(define-map authorized-insurers
  {address: principal}
  {name: (string-ascii 100), is-active: bool}
)

;; Function to register an insurer
(define-public (register-insurer (insurer principal) (name (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u1)) ;; Error code 1: Not authorized
    (map-set authorized-insurers
      {address: insurer}
      {name: name, is-active: true}
    )
    (ok true)
  )
)

;; Function to issue a new policy
(define-public (issue-policy 
                (vehicle-vin (string-ascii 17))
                (coverage-type (string-ascii 50))
                (start-date uint)
                (end-date uint)
                (premium-amount uint)
                (coverage-amount uint))
  (let ((policy-id (var-get next-policy-id))
        (insurer-data (map-get? authorized-insurers {address: tx-sender})))
    
    (asserts! (and (is-some insurer-data) 
                  (get is-active (unwrap-panic insurer-data))) 
             (err u2)) ;; Error code 2: Not an authorized insurer
    (asserts! (< start-date end-date) (err u3)) ;; Error code 3: Invalid date range
    
    (map-set policies
      {policy-id: policy-id}
      {
        owner: tx-sender,
        vehicle-vin: vehicle-vin,
        coverage-type: coverage-type,
        start-date: start-date,
        end-date: end-date,
        premium-amount: premium-amount,
        coverage-amount: coverage-amount,
        status: STATUS-ACTIVE,
        last-update: stacks-block-height
      }
    )
    
    (var-set next-policy-id (+ policy-id u1))
    (ok policy-id)
  )
)

;; Function to update policy status
(define-public (update-policy-status (policy-id uint) (new-status uint))
  (let ((policy (map-get? policies {policy-id: policy-id})))
    (asserts! (is-some policy) (err u4)) ;; Error code 4: Policy not found
    (asserts! (is-eq tx-sender (get owner (unwrap-panic policy))) (err u1)) ;; Error code 1: Not authorized
    (asserts! (and (>= new-status STATUS-ACTIVE) (<= new-status STATUS-SUSPENDED)) 
             (err u5)) ;; Error code 5: Invalid status
    
    (map-set policies
      {policy-id: policy-id}
      (merge (unwrap-panic policy)
             {
               status: new-status,
               last-update: stacks-block-height
             }
      )
    )
    (ok true)
  )
)

;; Function to file a claim
(define-public (file-claim 
                (policy-id uint)
                (date-of-incident uint)
                (description (string-ascii 500))
                (amount-requested uint))
  (let ((claim-id (var-get next-claim-id))
        (policy (map-get? policies {policy-id: policy-id})))
    
    (asserts! (is-some policy) (err u4)) ;; Error code 4: Policy not found
    (asserts! (is-eq (get status (unwrap-panic policy)) STATUS-ACTIVE) 
             (err u6)) ;; Error code 6: Policy not active
    
    ;; Check if the incident date is within policy coverage period
    (asserts! (and (>= date-of-incident (get start-date (unwrap-panic policy)))
                  (<= date-of-incident (get end-date (unwrap-panic policy))))
             (err u7)) ;; Error code 7: Incident date outside policy period
    
    ;; Create the claim
    (map-set claims
      {claim-id: claim-id}
      {
        policy-id: policy-id,
        claimant: tx-sender,
        date-of-incident: date-of-incident,
        description: description,
        amount-requested: amount-requested,
        amount-approved: u0,
        status: CLAIM-SUBMITTED,
        submission-date: stacks-block-height,
        last-update: stacks-block-height
      }
    )
    
    (var-set next-claim-id (+ claim-id u1))
    (ok claim-id)
  )
)

;; Function to process a claim
(define-public (process-claim 
                (claim-id uint) 
                (new-status uint) 
                (approved-amount uint))
  (let ((claim (map-get? claims {claim-id: claim-id}))
        (policy-id (get policy-id (unwrap-panic claim)))
        (policy (map-get? policies {policy-id: policy-id})))
    
    (asserts! (is-some claim) (err u8)) ;; Error code 8: Claim not found
    (asserts! (is-eq tx-sender (get owner (unwrap-panic policy))) (err u1)) ;; Error code 1: Not authorized
    (asserts! (and (>= new-status CLAIM-REVIEWING) (<= new-status CLAIM-PAID)) 
             (err u9)) ;; Error code 9: Invalid claim status
    
    ;; If approving, check that amount is within coverage limit
    (if (is-eq new-status CLAIM-APPROVED)
        (asserts! (<= approved-amount (get coverage-amount (unwrap-panic policy))) 
                 (err u10)) ;; Error code 10: Amount exceeds coverage
        true
    )
    
    (map-set claims
      {claim-id: claim-id}
      (merge (unwrap-panic claim)
             {
               status: new-status,
               amount-approved: (if (is-eq new-status CLAIM-APPROVED) 
                                   approved-amount 
                                   (get amount-approved (unwrap-panic claim))),
               last-update: stacks-block-height
             }
      )
    )
    (ok true)
  )
)

;; Read-only function to get policy information
(define-read-only (get-policy (policy-id uint))
  (map-get? policies {policy-id: policy-id})
)

;; Read-only function to get claim information
(define-read-only (get-claim (claim-id uint))
  (map-get? claims {claim-id: claim-id})
)

;; Read-only function to check if an address is an authorized insurer
(define-read-only (is-authorized-insurer (address principal))
  (let ((insurer-data (map-get? authorized-insurers {address: address})))
    (if (is-some insurer-data)
        (get is-active (unwrap-panic insurer-data))
        false
    )
  )
)

;; Read-only function to check if a policy is active
(define-read-only (is-policy-active (policy-id uint))
  (let ((policy (map-get? policies {policy-id: policy-id})))
    (if (is-some policy)
        (is-eq (get status (unwrap-panic policy)) STATUS-ACTIVE)
        false
    )
  )
)