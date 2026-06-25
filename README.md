# mpl-dnft-foundry-tests

Unit testing suite untuk smart contract **Dynamic NFT (dNFT) Kartu Pemain MPL Indonesia** menggunakan framework [Foundry](https://book.getfoundry.sh/). Repositori ini merupakan bagian dari skripsi berjudul:

> **"Implementasi Non-Fungible Token Dinamis (dNFT) pada Kartu Pemain Menggunakan Chainlink Oracle Berbasis Blockchain Ethereum"**

Dua arsitektur smart contract dibandingkan dalam penelitian ini dan diuji secara terpisah:

| Model | File Kontrak | File Test | Jumlah TC |
|---|---|---|---|
| Model A (Monolitik) | PlayerCard_NonLayered.sol | PlayerCard_NonLayered.t.sol | 20 |
| Model B (Berlapis) | MplPlayerCard_Optimized.sol | PlayerCard_Layered.t.sol | 25 |

---

## Prasyarat

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- Git
- Node.js (opsional, hanya jika install dependensi via npm)

Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verifikasi instalasi:

```bash
forge --version
```

---

## Instalasi

```bash
# Clone repositori
git clone https://github.com/<username>/mpl-foundry-test.git
cd mpl-foundry-test

# Install dependensi Solidity
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink-brownie-contracts
```

Tambahkan remapping di `foundry.toml`:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
remappings = [
  "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
  "@chainlink/contracts/=lib/chainlink-brownie-contracts/contracts/"
]
```

---

## Struktur Proyek

```
mpl-foundry-test/
├── src/
│   ├── PlayerCard_NonLayered.sol       # Kontrak Model A (Monolitik)
│   └── MplPlayerCard_Optimized.sol     # Kontrak Model B (Berlapis)
├── test/
│   ├── PlayerCard_NonLayered.t.sol     # Test suite Model A (20 TC)
│   └── PlayerCard_Layered.t.sol        # Test suite Model B (25 TC)
├── lib/
│   ├── openzeppelin-contracts/
│   ├── chainlink-brownie-contracts/
│   └── forge-std/
├── foundry.toml
└── README.md
```

---

## Menjalankan Test

### Semua test sekaligus

```bash
forge test -vv
```

### Per model

```bash
# Model A — Monolitik
forge test --match-contract PlayerCard_NonLayeredTest -vv

# Model B — Berlapis
forge test --match-contract PlayerCard_LayeredTest -vv
```

### Simpan output ke file (untuk dokumentasi laporan)

```bash
forge test -vv 2>&1 | tee hasil_test.txt
```

### Per kontrak, simpan ke file terpisah

```bash
forge test --match-contract PlayerCard_NonLayeredTest -vv 2>&1 | tee hasil_test_NonLayered.txt
forge test --match-contract PlayerCard_LayeredTest    -vv 2>&1 | tee hasil_test_Layered.txt
```

---

## Cakupan Test Case

### Model A: PlayerCard_NonLayeredTest (20 TC)

| Kode TC | Fungsi yang Diuji | Skenario |
|---|---|---|
| TC-NL-01 | `safeMint()` | Mint token pertama berhasil |
| TC-NL-02 | `safeMint()` | Data pemain tersimpan benar setelah mint |
| TC-NL-03 | `safeMint()` | Revert jika bukan owner |
| TC-NL-04 | `safeMint()` | Mint beberapa token, tokenId sequential |
| TC-NL-05 | `getPlayerData()` | Revert jika token tidak ada |
| TC-NL-06 | `getPlayerData()` | Data benar setelah update stats |
| TC-NL-07 | `fulfillRequest()` | Bit-unpacking packed uint256 benar |
| TC-NL-08 | `fulfillRequest()` | Boundary uint64 tidak overflow |
| TC-NL-09 | `generateSVG()` | Output SVG tidak kosong |
| TC-NL-10 | `generateSVG()` | KDA dihitung benar |
| TC-NL-11 | `generateSVG()` | Division by zero guard aktif saat deaths=0 |
| TC-NL-12 | `generateSVG()` | Leading zero pada desimal KDA < 0.10 |
| TC-NL-13 | `setSourceCode()` | Source code tersimpan benar |
| TC-NL-14 | `setSourceCode()` | Revert jika bukan owner |
| TC-NL-15 | `setAutomationSettings()` | Berhasil dengan nilai valid |
| TC-NL-16 | `setAutomationSettings()` | Revert jika interval terlalu pendek |
| TC-NL-17 | `setAutomationSettings()` | Revert jika belum ada token |
| TC-NL-18 | `setAutomationSettings()` | Revert jika targetTokenId tidak valid |
| TC-NL-19 | `checkUpkeep()` | Mengembalikan false sebelum interval lewat |
| TC-NL-20 | `checkUpkeep()` | Mengembalikan true setelah interval lewat |

### Model B: PlayerCard_LayeredTest (25 TC)

| Kode TC | Fungsi yang Diuji | Skenario |
|---|---|---|
| TC-L-01 | `safeMint()` | Mint token pertama berhasil |
| TC-L-02 | `safeMint()` | Data pemain tersimpan benar setelah mint |
| TC-L-03 | `safeMint()` | Revert jika bukan owner |
| TC-L-04 | `safeMint()` | Mint beberapa token, tokenId sequential |
| TC-L-05 | `getPlayerData()` | Revert jika token tidak ada |
| TC-L-06 | `getPlayerData()` | Data benar setelah update stats |
| TC-L-07 | `fulfillRequest()` | Bit-unpacking packed uint256 benar |
| TC-L-08 | `fulfillRequest()` | Boundary uint64 tidak overflow |
| TC-L-09 | `generateSVG()` | Output SVG tidak kosong |
| TC-L-10 | `generateSVG()` | Output mengandung ketiga layer SVG |
| TC-L-11 | `getBackgroundLayer()` | Layer 1 menghasilkan output tidak kosong |
| TC-L-12 | `getBackgroundLayer()` | Layer 1 mengandung header kartu |
| TC-L-13 | `getPixelArtLayer()` | Layer 2 menghasilkan output tidak kosong |
| TC-L-14 | `getStatsLayer()` | Layer 3 mengandung data pemain yang benar |
| TC-L-15 | `generateSVG()` | KDA dihitung benar |
| TC-L-16 | `generateSVG()` | Division by zero guard aktif saat deaths=0 |
| TC-L-17 | `generateSVG()` | Leading zero pada desimal KDA < 0.10 |
| TC-L-18 | `setSourceCode()` | Source code tersimpan benar |
| TC-L-19 | `setSourceCode()` | Revert jika bukan owner |
| TC-L-20 | `setAutomationSettings()` | Berhasil dengan nilai valid |
| TC-L-21 | `setAutomationSettings()` | Revert jika interval terlalu pendek |
| TC-L-22 | `setAutomationSettings()` | Revert jika belum ada token |
| TC-L-23 | `setAutomationSettings()` | Revert jika targetTokenId tidak valid |
| TC-L-24 | `checkUpkeep()` | Mengembalikan false sebelum interval lewat |
| TC-L-25 | `checkUpkeep()` | Mengembalikan true setelah interval lewat |

Model B memiliki 5 test case tambahan (TC-L-10 s.d. TC-L-14) karena arsitektur berlapis memungkinkan pengujian setiap layer SVG dari library `PlayerCardRenderer` secara independen.

---

## Catatan Arsitektur Test

Karena kontrak asli bergantung pada dependensi eksternal (`FunctionsClient` Chainlink dan ERC-721 OpenZeppelin), file test menggunakan pendekatan **stub testable contract** — yaitu versi kontrak yang mereplikasi seluruh logika bisnis namun mengganti dependensi eksternal dengan mock minimal agar dapat di-compile dan dijalankan di lingkungan lokal tanpa jaringan.

Komponen yang **tidak** diuji di sini karena memerlukan oracle eksternal:

- `requestStatsUpdate()` dan `_requestStatsInternal()` — memanggil Chainlink DON
- `fulfillRequest()` secara langsung — hanya dapat dipanggil oleh Chainlink router
- `performUpkeep()` — bergantung pada `_requestStatsInternal()`

Ketiga komponen tersebut diverifikasi melalui **Integration Testing** pada jaringan Sepolia Testnet dengan data statistik pemain MPL Indonesia yang sebenarnya.

---

## Hasil Test

```
Ran 20 tests for test/PlayerCard_NonLayered.t.sol:PlayerCard_NonLayeredTest
...
Suite result: ok. 20 passed; 0 failed; 0 skipped; finished in 16.40ms

Ran 25 tests for test/PlayerCard_Layered.t.sol:PlayerCard_LayeredTest
...
Suite result: ok. 25 passed; 0 failed; 0 skipped; finished in 15.22ms
```

---

## Lisensi

