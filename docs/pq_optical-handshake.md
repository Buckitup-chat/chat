# Post-Quantum Optical Handshake

## Given
Alice has PQ sign keypair (sign_pubA, sign_secA), PQ encrypt keypair (enc_pubA, enc_secA) and userhash hashA.
Bob has PQ sign keypair (sign_pubB, sign_secB), PQ encrypt keypair (enc_pubB, enc_secB) and userhash hashB.


## Optical Handshake 
Alice creates ephemeral ECC keypair (ecc_pubA, ecc_secA) and random nonceA.
Bob creates ephemeral ECC keypair (ecc_pubB, ecc_secB) and random nonceB.

Alice and Bob exchange public ECC keys and random nonces.

Alice signs nonceB with secret key and sends it to Bob. Alice also sends hashA and signs of hashA + nonceB with Alice's secret key.
Bob verifies nonceB with Alice's public key.
-> Confirms Alice has ECC key she claims.
Bob recieves unencrypted hashA and verifies the signature of hashA + nonceB with Alice's public key. 
-> Confirms Alice claims her user hash is hashA and it was singed right now with Bob nonce and Alice secret key.


Bob does the same symmetrically.

```mermaid
sequenceDiagram
    participant Alice
    participant Bob
    
    Note over Alice, Bob: 1. Generation
    Alice->>Alice: Create ecc_pubA, ecc_secA, nonceA
    Bob->>Bob: Create ecc_pubB, ecc_secB, nonceB
    
    Note over Alice, Bob: 2. Exchange
    Alice->>Bob: ecc_pubA, nonceA
    Bob->>Alice: ecc_pubB, nonceB
    
    Note over Alice, Bob: 3. Verification (Alice Side)
    Note right of Alice: Sign nonceB with ecc_secA
    Note right of Alice: Sign (hashA + nonceB) with ecc_secA
    Alice->>Bob: Sig(nonceB), hashA, Sig(hashA + nonceB)
    
    Note right of Bob: Verify Sig(nonceB) with ecc_pubA
    Note right of Bob: Verify Sig(hashA + nonceB) with ecc_pubA
    Note right of Bob: Confirms sender owns ecc_pubA & claims hashA
    
    Note over Alice, Bob: 4. Verification (Bob Side - Symmetric)
    Note left of Bob: Sign nonceA with ecc_secB
    Note left of Bob: Sign (hashB + nonceA) with ecc_secB
    Bob->>Alice: Sig(nonceA), hashB, Sig(hashB + nonceA)
    
    Note left of Alice: Verify Sig(nonceA) with ecc_pubB
    Note left of Alice: Verify Sig(hashB + nonceA) with ecc_pubB
```

## ContactCandidate

Alice saves hashB and ecc_pubB. Also signs ecc_pubA with her secret key(sign_secA).
When Alice discovers Usercard that has hashB, she sends ecc_pubA she signed to Bob.
Bob verifies the signature of ecc_pubA with Alice's public key. confirms that optical handshake he did to hashA is valid to sign_pubA and optically handshaked with ecc_pubA.
ContactCandidate becomes (trusted?) Contact

Bob does the same symmetrically.

```mermaid
sequenceDiagram
    participant Alice
    participant Bob
    
    Note over Alice, Bob: Pre-requisite: Optical Handshake Complete
    
    Note over Alice: Discovers Usercard(hashB, sign_pubB)
    Note over Alice: Sign ecc_pubA with sign_secA (Identity Key)
    
    Alice->>Bob: Sig(ecc_pubA, sign_secA)
    
    Note right of Bob: Has Usercard(hashA, sign_pubA)
    Note right of Bob: Verify Sig(ecc_pubA) with sign_pubA
    Note right of Bob: Validates: hashA -> sign_pubA -> ecc_pubA
    Note right of Bob: Promotes ContactCandidate to Trusted Contact
    
    Note over Bob: Symmetric Process
    Note over Bob: Sign ecc_pubB with sign_secB
    Bob->>Alice: Sig(ecc_pubB, sign_secB)
    
    Note left of Alice: Verify Sig(ecc_pubB) with sign_pubB
    Note left of Alice: Validates: hashB -> sign_pubB -> ecc_pubB
```


## Note
Ephemeral keys are not stored and one time per handshake.