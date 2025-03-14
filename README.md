# 📜 Project Structure  

## TotemFactory.sol  
💡 **Purpose:** Creates totems and stores totem data.  

### Functions:  
- `createTotem(metaData, name, symbol)` – Creates a new totem with a new `TotemToken`.  
- `createTotemWithExistingToken(uint256 tokenId)` – Creates a new totem with an existing ERC20/ERC721 token. Merit system for the created totem activates immediately.  
- `addTokenToWhitelist(address tokenAddr)` – Adds an existing token to the whitelist.  
- `removeTokenFromWhitelist(address tokenAddr)` – Removes a token from the whitelist.  

---

## Totem.sol *(Governance Contract)*  
💡 **Purpose:** Governance logic for each totem. Uses `ProxyBeacon` as part of OpenZeppelin's `UpgradeableBeacon` system. All Totem contracts share a common implementation.  

### Functions:  
- `meritBoost()` – Earn merit for the totem holder during the Mythum subperiod.  
- `collectMYTH()` – Collect accumulated `MYTH` from `MeritManager`.  

---

## TotemDistributor.sol *(Totem Token Sale & Distribution)*  
💡 **Purpose:** Handles `TotemToken` distribution, sales, and burning. Uses an oracle for `MYTH/USD` conversion.  

### Functions:  
- `buy(uint256 amount)` – Buy `TotemTokens` during the sale period.  
  - **Limits:**  
    - Maximum **5,000,000** tokens per address.  
    - **Price:** $0.00004 per `TotemToken`.  
- `sell(uint256 amount)` – Sell `TotemTokens` during the sale period.  

### Conditions:  
- When all tokens are sold:  
  - Merit system **activates**.  
  - `Buy/Sell` **becomes unavailable**.  
  - `burnTotems()` **becomes available**.  
  - `TotemToken` **becomes transferable**.  

### MYTH Distribution:  
- **2.5%** → `revenuePool`.  
- **0.5%** → Totem creator.  
- **Remaining** → Totem's treasury.  
- **Send liquidity to AMM.**  
- **Received LP sent to Totem’s treasury.**  

### Additional Functions:  
- `burnTotems()` – Burn `TotemTokens` and receive `MYTH` tokens in return.  
  - `MYTH` share is proportional to the user's `TotemToken` share in circulation.  
- `exchangeTotems()` – Exchange custom tokens for `MYTH` from the Totem’s treasury.  
  - Custom tokens are sent to the Totem’s treasury.  

---

## MeritManager.sol *(Merit System Controller)*  
💡 **Purpose:** Manages merit accumulation and distribution. Tracks Mytho periods.  

### Functions:  
- `boostTotem(address totemAddress, uint256 amount)` – Called once per period by a `Totem` contract to increase merit balance.  
- `collectMYTH()` – Claim accumulated `MYTH` for a `Totem` contract.  
- `creditMerit(address totemAddress, uint256 amount)` – Credit merit manually to a selected `Totem` based on off-chain actions.  
- `addToBlacklist(address totemAddress)` – Add totem to blacklist.  
- `removeFromBlacklist(address totemAddress)` – Remove totem from blacklist.  

---

## MYTHVesting.sol *(MYTH Distribution Vesting Contract)*  
💡 **Purpose:** Handles `MYTH` distribution via vesting.  

---

## TotemToken.sol *(ERC20 Token with OP Compatibility)*  
💡 **Purpose:** Custom ERC20 token, non-transferable until the end of the sale period.  

### Functions:  
- `constructor()` – Mints **1,000,000,000** tokens, distributed as follows:  
  - **250,000** → Totem creator.  
  - **100,000,000** → Totem treasury.  
  - **899,750,000** → `TotemDistributor`.  
- `transfer()` – Disabled during the sale period.  

---

## MYTH.sol *(ERC20 Token with OP Compatibility)*  
💡 **Purpose:** `MYTH` token, distributed via `MYTHVesting`.  