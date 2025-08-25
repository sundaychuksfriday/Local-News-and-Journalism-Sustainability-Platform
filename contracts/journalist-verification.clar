;; Journalist Verification Contract
;; Handles journalist registration, verification, credentialing, and reputation management

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-JOURNALIST-NOT-FOUND (err u201))
(define-constant ERR-JOURNALIST-ALREADY-EXISTS (err u202))
(define-constant ERR-INVALID-VERIFICATION-LEVEL (err u203))
(define-constant ERR-VERIFICATION-PENDING (err u204))
(define-constant ERR-VERIFICATION-REJECTED (err u205))
(define-constant ERR-INVALID-RATING (err u206))
(define-constant ERR-INSUFFICIENT-ARTICLES (err u207))
(define-constant ERR-INVALID-EXPERIENCE (err u208))

;; Verification levels
(define-constant VERIFICATION-NONE u0)
(define-constant VERIFICATION-PENDING u1)
(define-constant VERIFICATION-BASIC u2)
(define-constant VERIFICATION-PROFESSIONAL u3)
(define-constant VERIFICATION-EXPERT u4)

;; Reputation thresholds
(define-constant MIN-REPUTATION-PROFESSIONAL u75)
(define-constant MIN-REPUTATION-EXPERT u90)
(define-constant MIN-ARTICLES-PROFESSIONAL u10)
(define-constant MIN-ARTICLES-EXPERT u50)

;; Data structures
(define-map journalists
  { journalist: principal }
  {
    name: (string-ascii 100),
    bio: (string-ascii 500),
    specialization: (string-ascii 100),
    years-experience: uint,
    verification-level: uint,
    verification-status: (string-ascii 20),
    registration-date: uint,
    last-updated: uint,
    total-articles: uint,
    reputation-score: uint,
    total-earnings: uint,
    active: bool
  }
)

(define-map journalist-credentials
  { journalist: principal, credential-id: uint }
  {
    credential-type: (string-ascii 50),
    issuing-organization: (string-ascii 100),
    issue-date: uint,
    expiry-date: uint,
    verified: bool,
    verification-date: uint
  }
)

(define-map journalist-portfolio
  { journalist: principal, article-id: uint }
  {
    title: (string-ascii 200),
    publication: (string-ascii 100),
    publication-date: uint,
    article-url: (string-ascii 300),
    category: (string-ascii 50),
    views: uint,
    engagement-score: uint
  }
)

(define-map verification-requests
  { journalist: principal }
  {
    request-date: uint,
    requested-level: uint,
    supporting-documents: (string-ascii 500),
    reviewer: (optional principal),
    review-date: (optional uint),
    review-notes: (string-ascii 300),
    status: (string-ascii 20)
  }
)

(define-map journalist-ratings
  { journalist: principal, rater: principal }
  {
    rating: uint,
    review: (string-ascii 200),
    rating-date: uint,
    article-id: (optional uint)
  }
)

(define-map performance-metrics
  { journalist: principal, month: uint, year: uint }
  {
    articles-published: uint,
    total-views: uint,
    average-engagement: uint,
    subscriber-growth: uint,
    revenue-generated: uint,
    quality-score: uint
  }
)

;; Data variables
(define-data-var total-journalists uint u0)
(define-data-var next-credential-id uint u1)
(define-data-var next-article-id uint u1)
(define-data-var verification-fee uint u1000000) ;; 1 STX
(define-data-var min-experience-years uint u1)

;; Authorized verifiers list
(define-map authorized-verifiers
  { verifier: principal }
  { authorized: bool, specialization: (string-ascii 100) }
)

;; Initialize contract owner as authorized verifier
(map-set authorized-verifiers
  { verifier: CONTRACT-OWNER }
  { authorized: true, specialization: "General Journalism" }
)

;; Public functions

;; Register as a journalist
(define-public (register-journalist (name (string-ascii 100)) (bio (string-ascii 500)) (specialization (string-ascii 100)) (years-experience uint))
  (let (
    (journalist tx-sender)
    (current-block block-height)
  )
    ;; Validate inputs
    (asserts! (> (len name) u0) ERR-INVALID-EXPERIENCE)
    (asserts! (>= years-experience (var-get min-experience-years)) ERR-INVALID-EXPERIENCE)
    (asserts! (is-none (map-get? journalists { journalist: journalist })) ERR-JOURNALIST-ALREADY-EXISTS)

    ;; Create journalist profile
    (map-set journalists
      { journalist: journalist }
      {
        name: name,
        bio: bio,
        specialization: specialization,
        years-experience: years-experience,
        verification-level: VERIFICATION-NONE,
        verification-status: "unverified",
        registration-date: current-block,
        last-updated: current-block,
        total-articles: u0,
        reputation-score: u50, ;; Start with neutral reputation
        total-earnings: u0,
        active: true
      }
    )

    ;; Update counter
    (var-set total-journalists (+ (var-get total-journalists) u1))

    (ok true)
  )
)

;; Request verification
(define-public (request-verification (requested-level uint) (supporting-documents (string-ascii 500)))
  (let (
    (journalist tx-sender)
    (journalist-info (unwrap! (map-get? journalists { journalist: journalist }) ERR-JOURNALIST-NOT-FOUND))
    (current-block block-height)
  )
    ;; Validate request
    (asserts! (<= requested-level VERIFICATION-EXPERT) ERR-INVALID-VERIFICATION-LEVEL)
    (asserts! (> requested-level (get verification-level journalist-info)) ERR-INVALID-VERIFICATION-LEVEL)
    (asserts! (get active journalist-info) ERR-NOT-AUTHORIZED)

    ;; Check requirements for higher levels
    (if (is-eq requested-level VERIFICATION-PROFESSIONAL)
      (begin
        (asserts! (>= (get reputation-score journalist-info) MIN-REPUTATION-PROFESSIONAL) ERR-INSUFFICIENT-ARTICLES)
        (asserts! (>= (get total-articles journalist-info) MIN-ARTICLES-PROFESSIONAL) ERR-INSUFFICIENT-ARTICLES)
      )
      true
    )

    (if (is-eq requested-level VERIFICATION-EXPERT)
      (begin
        (asserts! (>= (get reputation-score journalist-info) MIN-REPUTATION-EXPERT) ERR-INSUFFICIENT-ARTICLES)
        (asserts! (>= (get total-articles journalist-info) MIN-ARTICLES-EXPERT) ERR-INSUFFICIENT-ARTICLES)
      )
      true
    )

    ;; Process verification fee
    (try! (stx-transfer? (var-get verification-fee) journalist (as-contract tx-sender)))

    ;; Create verification request
    (map-set verification-requests
      { journalist: journalist }
      {
        request-date: current-block,
        requested-level: requested-level,
        supporting-documents: supporting-documents,
        reviewer: none,
        review-date: none,
        review-notes: "",
        status: "pending"
      }
    )

    ;; Update journalist status
    (map-set journalists
      { journalist: journalist }
      (merge journalist-info {
        verification-status: "pending",
        last-updated: current-block
      })
    )

    (ok true)
  )
)

;; Add credential
(define-public (add-credential (credential-type (string-ascii 50)) (issuing-organization (string-ascii 100)) (issue-date uint) (expiry-date uint))
  (let (
    (journalist tx-sender)
    (credential-id (var-get next-credential-id))
    (current-block block-height)
  )
    ;; Validate journalist exists
    (asserts! (is-some (map-get? journalists { journalist: journalist })) ERR-JOURNALIST-NOT-FOUND)

    ;; Add credential
    (map-set journalist-credentials
      { journalist: journalist, credential-id: credential-id }
      {
        credential-type: credential-type,
        issuing-organization: issuing-organization,
        issue-date: issue-date,
        expiry-date: expiry-date,
        verified: false,
        verification-date: u0
      }
    )

    ;; Update credential ID counter
    (var-set next-credential-id (+ credential-id u1))

    (ok credential-id)
  )
)

;; Add portfolio article
(define-public (add-portfolio-article (title (string-ascii 200)) (publication (string-ascii 100)) (publication-date uint) (article-url (string-ascii 300)) (category (string-ascii 50)))
  (let (
    (journalist tx-sender)
    (article-id (var-get next-article-id))
    (journalist-info (unwrap! (map-get? journalists { journalist: journalist }) ERR-JOURNALIST-NOT-FOUND))
  )
    ;; Add article to portfolio
    (map-set journalist-portfolio
      { journalist: journalist, article-id: article-id }
      {
        title: title,
        publication: publication,
        publication-date: publication-date,
        article-url: article-url,
        category: category,
        views: u0,
        engagement-score: u0
      }
    )

    ;; Update journalist article count
    (map-set journalists
      { journalist: journalist }
      (merge journalist-info {
        total-articles: (+ (get total-articles journalist-info) u1),
        last-updated: block-height
      })
    )

    ;; Update article ID counter
    (var-set next-article-id (+ article-id u1))

    (ok article-id)
  )
)

;; Rate a journalist
(define-public (rate-journalist (journalist principal) (rating uint) (review (string-ascii 200)) (article-id (optional uint)))
  (let (
    (rater tx-sender)
    (current-block block-height)
    (journalist-info (unwrap! (map-get? journalists { journalist: journalist }) ERR-JOURNALIST-NOT-FOUND))
  )
    ;; Validate rating
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
    (asserts! (not (is-eq rater journalist)) ERR-NOT-AUTHORIZED)

    ;; Add rating
    (map-set journalist-ratings
      { journalist: journalist, rater: rater }
      {
        rating: rating,
        review: review,
        rating-date: current-block,
        article-id: article-id
      }
    )

    ;; Update reputation score (simplified calculation)
    (let (
      (current-reputation (get reputation-score journalist-info))
      (new-reputation (/ (+ (* current-reputation u9) (* rating u20)) u10))
    )
      (map-set journalists
        { journalist: journalist }
        (merge journalist-info {
          reputation-score: new-reputation,
          last-updated: current-block
        })
      )
    )

    (ok true)
  )
)

;; Administrative functions

;; Approve verification (verifiers only)
(define-public (approve-verification (journalist principal) (approved-level uint) (review-notes (string-ascii 300)))
  (let (
    (verifier tx-sender)
    (verification-request (unwrap! (map-get? verification-requests { journalist: journalist }) ERR-JOURNALIST-NOT-FOUND))
    (journalist-info (unwrap! (map-get? journalists { journalist: journalist }) ERR-JOURNALIST-NOT-FOUND))
    (current-block block-height)
  )
    ;; Validate verifier authorization
    (asserts! (default-to false (get authorized (map-get? authorized-verifiers { verifier: verifier }))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status verification-request) "pending") ERR-VERIFICATION-PENDING)

    ;; Update verification request
    (map-set verification-requests
      { journalist: journalist }
      (merge verification-request {
        reviewer: (some verifier),
        review-date: (some current-block),
        review-notes: review-notes,
        status: "approved"
      })
    )

    ;; Update journalist verification
    (map-set journalists
      { journalist: journalist }
      (merge journalist-info {
        verification-level: approved-level,
        verification-status: "verified",
        last-updated: current-block
      })
    )

    (ok true)
  )
)

;; Reject verification (verifiers only)
(define-public (reject-verification (journalist principal) (review-notes (string-ascii 300)))
  (let (
    (verifier tx-sender)
    (verification-request (unwrap! (map-get? verification-requests { journalist: journalist }) ERR-JOURNALIST-NOT-FOUND))
    (journalist-info (unwrap! (map-get? journalists { journalist: journalist }) ERR-JOURNALIST-NOT-FOUND))
    (current-block block-height)
  )
    ;; Validate verifier authorization
    (asserts! (default-to false (get authorized (map-get? authorized-verifiers { verifier: verifier }))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status verification-request) "pending") ERR-VERIFICATION-PENDING)

    ;; Update verification request
    (map-set verification-requests
      { journalist: journalist }
      (merge verification-request {
        reviewer: (some verifier),
        review-date: (some current-block),
        review-notes: review-notes,
        status: "rejected"
      })
    )

    ;; Update journalist status
    (map-set journalists
      { journalist: journalist }
      (merge journalist-info {
        verification-status: "rejected",
        last-updated: current-block
      })
    )

    (ok true)
  )
)

;; Add authorized verifier (admin only)
(define-public (add-authorized-verifier (verifier principal) (specialization (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-verifiers
      { verifier: verifier }
      { authorized: true, specialization: specialization }
    )
    (ok true)
  )
)

;; Verify credential (verifiers only)
(define-public (verify-credential (journalist principal) (credential-id uint))
  (let (
    (verifier tx-sender)
    (credential (unwrap! (map-get? journalist-credentials { journalist: journalist, credential-id: credential-id }) ERR-JOURNALIST-NOT-FOUND))
    (current-block block-height)
  )
    ;; Validate verifier authorization
    (asserts! (default-to false (get authorized (map-get? authorized-verifiers { verifier: verifier }))) ERR-NOT-AUTHORIZED)

    ;; Update credential
    (map-set journalist-credentials
      { journalist: journalist, credential-id: credential-id }
      (merge credential {
        verified: true,
        verification-date: current-block
      })
    )

    (ok true)
  )
)

;; Set verification fee (admin only)
(define-public (set-verification-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set verification-fee new-fee)
    (ok true)
  )
)

;; Read-only functions

;; Get journalist info
(define-read-only (get-journalist-info (journalist principal))
  (map-get? journalists { journalist: journalist })
)

;; Get journalist verification level
(define-read-only (get-verification-level (journalist principal))
  (match (map-get? journalists { journalist: journalist })
    info (some (get verification-level info))
    none
  )
)

;; Check if journalist is verified
(define-read-only (is-journalist-verified (journalist principal))
  (match (map-get? journalists { journalist: journalist })
    info (>= (get verification-level info) VERIFICATION-BASIC)
    false
  )
)

;; Get journalist reputation
(define-read-only (get-journalist-reputation (journalist principal))
  (match (map-get? journalists { journalist: journalist })
    info (some (get reputation-score info))
    none
  )
)

;; Get verification request
(define-read-only (get-verification-request (journalist principal))
  (map-get? verification-requests { journalist: journalist })
)

;; Get credential info
(define-read-only (get-credential (journalist principal) (credential-id uint))
  (map-get? journalist-credentials { journalist: journalist, credential-id: credential-id })
)

;; Get portfolio article
(define-read-only (get-portfolio-article (journalist principal) (article-id uint))
  (map-get? journalist-portfolio { journalist: journalist, article-id: article-id })
)

;; Get journalist rating
(define-read-only (get-journalist-rating (journalist principal) (rater principal))
  (map-get? journalist-ratings { journalist: journalist, rater: rater })
)

;; Check if user is authorized verifier
(define-read-only (is-authorized-verifier (verifier principal))
  (default-to false (get authorized (map-get? authorized-verifiers { verifier: verifier })))
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  {
    total-journalists: (var-get total-journalists),
    verification-fee: (var-get verification-fee),
    min-experience-years: (var-get min-experience-years),
    next-credential-id: (var-get next-credential-id),
    next-article-id: (var-get next-article-id)
  }
)

;; Check journalist eligibility for verification level
(define-read-only (check-verification-eligibility (journalist principal) (requested-level uint))
  (match (map-get? journalists { journalist: journalist })
    info
      (if (is-eq requested-level VERIFICATION-PROFESSIONAL)
        (and
          (>= (get reputation-score info) MIN-REPUTATION-PROFESSIONAL)
          (>= (get total-articles info) MIN-ARTICLES-PROFESSIONAL)
        )
        (if (is-eq requested-level VERIFICATION-EXPERT)
          (and
            (>= (get reputation-score info) MIN-REPUTATION-EXPERT)
            (>= (get total-articles info) MIN-ARTICLES-EXPERT)
          )
          true
        )
      )
    false
  )
)
