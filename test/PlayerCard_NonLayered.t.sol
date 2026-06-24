// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// =============================================================================
// MOCK CONTRACTS
// Chainlink FunctionsClient membutuhkan router saat konstruksi.
// Kita buat mock router agar kontrak bisa di-deploy secara lokal tanpa Chainlink.
// =============================================================================

/// @dev Mock router Chainlink Functions — hanya menerima panggilan sendRequest
///      dan mengembalikan requestId palsu tanpa meneruskan ke DON.
contract MockRouter {
    uint256 private _nonce;

    function sendRequest(
        uint64,        // subscriptionId
        bytes memory,  // data
        uint16,        // dataVersion
        uint32,        // callbackGasLimit
        bytes32        // donId
    ) external returns (bytes32) {
        // Buat requestId unik dari hash nonce + caller + timestamp
        return keccak256(abi.encodePacked(_nonce++, msg.sender, block.timestamp));
    }
}

// =============================================================================
// STUB KONTRAK — Meng-extend PlayerCard_NonLayered tanpa import path asli.
// Karena environment Foundry lokal tidak memiliki node_modules OpenZeppelin
// maupun Chainlink, kita definisikan ulang kontrak secara minimal di sini
// sebagai representasi untuk keperluan pengujian struktural.
//
// CATATAN UNTUK LAPORAN:
// Pada implementasi Foundry penuh, file ini cukup berisi:
//   import "../src/PlayerCard_NonLayered.sol";
// dan semua dependensi di-install via:
//   forge install OpenZeppelin/openzeppelin-contracts
//   forge install smartcontractkit/chainlink
// =============================================================================

// Representasi struct PlayerData (identik dengan kontrak asli)
struct PlayerData {
    string nickname;
    string lane;
    uint64 games;
    uint64 kills;
    uint64 deaths;
    uint64 assists;
}

/// @dev Versi testable dari PlayerCard_NonLayered.
///      Semua logika bisnis direplikasi identik; hanya dependensi eksternal
///      (OpenZeppelin ERC721, Chainlink) yang di-stub agar bisa di-compile lokal.
contract PlayerCard_NonLayered_Testable {
    using Strings for uint256;

    // --- Storage (identik dengan kontrak asli) ---
    uint256 private _tokenIds;
    uint64  public subscriptionId;
    string  public sourceCode;
    uint256 public lastTimeStamp;
    uint256 public constant MINIMUM_INTERVAL = 3600;
    uint256 public interval = 24 hours;
    uint256 public targetTokenIdToUpdate;
    address public owner;

    mapping(uint256 => PlayerData) public s_playerData;
    mapping(bytes32 => uint256)    public s_requestToTokenId;
    mapping(bytes32 => bool)       public s_requestExists;

    // --- Mock router ---
    MockRouter private _router;

    // --- Custom errors (identik dengan kontrak asli) ---
    error UnknownRequestId(bytes32 requestId);
    error OracleError(bytes err);
    error IntervalTooShort(uint256 provided, uint256 minimum);
    error NoTokensMinted();
    error NotOwner();

    // --- Events (identik dengan kontrak asli) ---
    event PlayerStatsUpdated(uint256 indexed tokenId, uint64 games, uint64 kills, uint64 deaths, uint64 assists, uint256 timestamp);
    event StatsRequested(uint256 indexed tokenId, bytes32 indexed requestId, string nickname);
    event AutomationSettingsChanged(uint256 newInterval, uint256 newTargetTokenId);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(uint64 _subscriptionId, address routerAddr) {
        subscriptionId = _subscriptionId;
        lastTimeStamp  = block.timestamp;
        owner          = msg.sender;
        _router        = MockRouter(routerAddr);
    }

    // -------------------------------------------------------------------------
    // FUNGSI YANG DIUJI
    // -------------------------------------------------------------------------

    /// @notice Mint token baru (identik logikanya dengan safeMint di kontrak asli)
    function safeMint(address, string memory _nickname, string memory _lane) public onlyOwner {
        uint256 tokenId = _tokenIds;
        s_playerData[tokenId] = PlayerData(_nickname, _lane, 0, 0, 0, 0);
        _tokenIds++;
    }

    /// @notice Simpan source code Chainlink JS
    function setSourceCode(string memory _sourceCode) public onlyOwner {
        sourceCode = _sourceCode;
    }

    /// @notice Konfigurasi Automation interval dan target token
    function setAutomationSettings(uint256 _intervalSeconds, uint256 _targetTokenId) public onlyOwner {
        if (_intervalSeconds < MINIMUM_INTERVAL) revert IntervalTooShort(_intervalSeconds, MINIMUM_INTERVAL);
        if (_tokenIds == 0) revert NoTokensMinted();
        require(_targetTokenId < _tokenIds, "Token ID tidak valid");
        interval = _intervalSeconds;
        targetTokenIdToUpdate = _targetTokenId;
        emit AutomationSettingsChanged(_intervalSeconds, _targetTokenId);
    }

    /// @notice Total token yang telah di-mint
    function totalSupply() public view returns (uint256) { return _tokenIds; }

    /// @notice Ambil data pemain berdasarkan tokenId
    function getPlayerData(uint256 tokenId) public view returns (PlayerData memory) {
        require(tokenId < _tokenIds, "Token ID tidak valid");
        return s_playerData[tokenId];
    }

    /// @notice checkUpkeep Chainlink Automation
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval && targetTokenIdToUpdate < _tokenIds;
        performData  = bytes("");
    }

    /// @notice Simulasi fulfillRequest — inject packed uint256 langsung ke storage
    ///         (Pada sistem nyata dipanggil oleh Chainlink DON router)
    function simulateFulfill(uint256 tokenId, uint256 packedData) public {
        require(tokenId < _tokenIds, "Token ID tidak valid");
        s_playerData[tokenId].assists = uint64(packedData);
        s_playerData[tokenId].deaths  = uint64(packedData >> 64);
        s_playerData[tokenId].kills   = uint64(packedData >> 128);
        s_playerData[tokenId].games   = uint64(packedData >> 192);
        PlayerData memory d = s_playerData[tokenId];
        emit PlayerStatsUpdated(tokenId, d.games, d.kills, d.deaths, d.assists, block.timestamp);
    }

    /// @notice Generate SVG on-chain (identik logikanya dengan kontrak asli)
    function generateSVG(uint256 tokenId) public view returns (string memory) {
        PlayerData memory d = s_playerData[tokenId];
        uint64 safeDeaths   = d.deaths == 0 ? 1 : d.deaths;
        uint256 kdaScaled   = (uint256(d.kills) + uint256(d.assists)) * 100 / safeDeaths;
        uint256 kdaDec      = kdaScaled % 100;
        string memory kdaStr = string.concat(
            Strings.toString(kdaScaled / 100), ".",
            kdaDec < 10
                ? string.concat("0", Strings.toString(kdaDec))
                : Strings.toString(kdaDec)
        );
        return string.concat(
            "<svg>",
            d.nickname, "|", d.lane, "|",
            Strings.toString(d.games), "|",
            Strings.toString(d.kills), "|",
            Strings.toString(d.deaths), "|",
            Strings.toString(d.assists), "|",
            kdaStr,
            "</svg>"
        );
    }
}

// Impor library Strings untuk digunakan di kontrak testable
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// =============================================================================
// TEST CONTRACT
// =============================================================================

/// @title  PlayerCard_NonLayeredTest
/// @notice Unit test untuk kontrak Model A (Monolitik / Non-Layered)
///         Dijalankan dengan: forge test --match-contract PlayerCard_NonLayeredTest -vv
contract PlayerCard_NonLayeredTest is Test {

    PlayerCard_NonLayered_Testable public card;
    MockRouter                     public router;

    address public contractOwner = address(this);
    address public nonOwner      = address(0xBEEF);

    // -------------------------------------------------------------------------
    // SETUP — dijalankan sebelum setiap fungsi test_*
    // -------------------------------------------------------------------------
    function setUp() public {
        router = new MockRouter();
        card   = new PlayerCard_NonLayered_Testable(1, address(router));
    }

    // =========================================================================
    // GRUP 1: safeMint
    // =========================================================================

    /// @dev TC-NL-01: Mint token pertama berhasil, totalSupply bertambah
    function test_NL01_SafeMint_Sukses_TotalSupplyBertambah() public {
        assertEq(card.totalSupply(), 0);
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        assertEq(card.totalSupply(), 1);
    }

    /// @dev TC-NL-02: Data pemain tersimpan dengan benar setelah mint
    function test_NL02_SafeMint_DataPemainTersimpanBenar() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        PlayerData memory d = card.getPlayerData(0);
        assertEq(d.nickname, "Kairi");
        assertEq(d.lane,     "JUNGLE");
        assertEq(d.games,    0);
        assertEq(d.kills,    0);
        assertEq(d.deaths,   0);
        assertEq(d.assists,  0);
    }

    /// @dev TC-NL-03: Mint oleh non-owner harus revert
    function test_NL03_SafeMint_RevertJikaBukanOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(PlayerCard_NonLayered_Testable.NotOwner.selector);
        card.safeMint(nonOwner, "Kairi", "JUNGLE");
    }

    /// @dev TC-NL-04: Mint beberapa token, setiap tokenId unik dan sequential
    function test_NL04_SafeMint_MultipleToken_IdSequential() public {
        card.safeMint(contractOwner, "Kairi",   "JUNGLE");
        card.safeMint(contractOwner, "Udil",  "MID");
        card.safeMint(contractOwner, "Branz",  "GOLD");
        assertEq(card.totalSupply(), 3);
        assertEq(card.getPlayerData(0).nickname, "Kairi");
        assertEq(card.getPlayerData(1).nickname, "Udil");
        assertEq(card.getPlayerData(2).nickname, "Branz");
    }

    // =========================================================================
    // GRUP 2: getPlayerData
    // =========================================================================

    /// @dev TC-NL-05: getPlayerData token ID tidak valid harus revert
    function test_NL05_GetPlayerData_RevertJikaTokenTidakAda() public {
        vm.expectRevert(bytes("Token ID tidak valid"));
        card.getPlayerData(999);
    }

    /// @dev TC-NL-06: getPlayerData mengembalikan data yang benar setelah update stats
    function test_NL06_GetPlayerData_DataBenarSetelahUpdateStats() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");

        // games=30, kills=120, deaths=60, assists=200
        uint256 packed = (uint256(30)  << 192) |
                         (uint256(120) << 128) |
                         (uint256(60)  << 64)  |
                         uint256(200);
        card.simulateFulfill(0, packed);

        PlayerData memory d = card.getPlayerData(0);
        assertEq(d.games,   30);
        assertEq(d.kills,   120);
        assertEq(d.deaths,  60);
        assertEq(d.assists, 200);
    }

    // =========================================================================
    // GRUP 3: simulateFulfill (logika bit-unpacking fulfillRequest)
    // =========================================================================

    /// @dev TC-NL-07: Bit-unpacking packed uint256 → 4 field uint64 benar
    function test_NL07_FulfillRequest_BitUnpackingBenar() public {
        card.safeMint(contractOwner, "Kairi", "MID");

        uint64 expGames   = 50;
        uint64 expKills   = 300;
        uint64 expDeaths  = 100;
        uint64 expAssists = 450;

        uint256 packed = (uint256(expGames)   << 192) |
                         (uint256(expKills)   << 128) |
                         (uint256(expDeaths)  << 64)  |
                         uint256(expAssists);

        card.simulateFulfill(0, packed);

        PlayerData memory d = card.getPlayerData(0);
        assertEq(d.games,   expGames);
        assertEq(d.kills,   expKills);
        assertEq(d.deaths,  expDeaths);
        assertEq(d.assists, expAssists);
    }

    /// @dev TC-NL-08: Nilai boundary uint64 tidak overflow
    function test_NL08_FulfillRequest_BoundaryUint64_TidakOverflow() public {
        card.safeMint(contractOwner, "Branz", "GOLD");

        uint64 maxVal  = type(uint64).max;
        uint256 packed = (uint256(maxVal) << 192) |
                         (uint256(maxVal) << 128) |
                         (uint256(maxVal) << 64)  |
                         uint256(maxVal);

        card.simulateFulfill(0, packed);

        PlayerData memory d = card.getPlayerData(0);
        assertEq(d.games,   maxVal);
        assertEq(d.kills,   maxVal);
        assertEq(d.deaths,  maxVal);
        assertEq(d.assists, maxVal);
    }

    // =========================================================================
    // GRUP 4: generateSVG — KDA calculation & output
    // =========================================================================

    /// @dev TC-NL-09: generateSVG mengembalikan string tidak kosong setelah mint
    function test_NL09_GenerateSVG_OutputTidakKosong() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        string memory svg = card.generateSVG(0);
        assertTrue(bytes(svg).length > 0);
    }

    /// @dev TC-NL-10: KDA dihitung benar (kills+assists)/deaths x100, 2 desimal
    ///      kills=120, deaths=60, assists=200 → KDA = (120+200)/60 = 5.33
    function test_NL10_GenerateSVG_KDADiHitungBenar() public {
        card.safeMint(contractOwner, "KAIRI", "JUNGLE");
        uint256 packed = (uint256(30)  << 192) |
                         (uint256(120) << 128) |
                         (uint256(60)  << 64)  |
                         uint256(200);
        card.simulateFulfill(0, packed);

        string memory svg = card.generateSVG(0);
        // SVG harus mengandung "5.33"
        assertTrue(_contains(svg, "5.33"), "KDA harus 5.33");
    }

    /// @dev TC-NL-11: Division by zero guard — deaths=0 diganti safeDeaths=1
    ///      kills=10, deaths=0, assists=5 → KDA = (10+5)/1 = 15.00
    function test_NL11_GenerateSVG_DeathsNol_GuardAktif() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        // deaths=0 (nilai awal, tidak di-update)
        uint256 packed = (uint256(5)  << 192) |
                         (uint256(10) << 128) |
                         (uint256(0)  << 64)  |
                         uint256(5);
        card.simulateFulfill(0, packed);

        string memory svg = card.generateSVG(0);
        // KDA = (10+5)/1 = 15.00
        assertTrue(_contains(svg, "15.00"), "KDA harus 15.00 saat deaths=0");
    }

    /// @dev TC-NL-12: Leading zero pada desimal KDA < .10 (misal 4.05 bukan 4.5)
    ///      kills=4, deaths=1, assists=0 → KDA = 4/1 = 4.00
    function test_NL12_GenerateSVG_KDALeadingZeroDesimal() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        uint256 packed = (uint256(1) << 192) |
                         (uint256(4) << 128) |
                         (uint256(1) << 64)  |
                         uint256(0);
        card.simulateFulfill(0, packed);

        string memory svg = card.generateSVG(0);
        // KDA = (4+0)/1 = 4.00 — harus ada leading zero
        assertTrue(_contains(svg, "4.00"), "KDA harus format 4.00 bukan 4.0");
    }

    // =========================================================================
    // GRUP 5: setSourceCode
    // =========================================================================

    /// @dev TC-NL-13: setSourceCode tersimpan dengan benar
    function test_NL13_SetSourceCode_TersimpanBenar() public {
        string memory src = "const result = await fetch(args[0]);";
        card.setSourceCode(src);
        assertEq(card.sourceCode(), src);
    }

    /// @dev TC-NL-14: setSourceCode oleh non-owner harus revert
    function test_NL14_SetSourceCode_RevertJikaBukanOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(PlayerCard_NonLayered_Testable.NotOwner.selector);
        card.setSourceCode("malicious code");
    }

    // =========================================================================
    // GRUP 6: setAutomationSettings
    // =========================================================================

    /// @dev TC-NL-15: setAutomationSettings berhasil dengan nilai valid
    function test_NL15_SetAutomationSettings_Sukses() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        card.setAutomationSettings(7200, 0);
        assertEq(card.interval(),              7200);
        assertEq(card.targetTokenIdToUpdate(), 0);
    }

    /// @dev TC-NL-16: setAutomationSettings revert jika interval < MINIMUM (3600 detik)
    function test_NL16_SetAutomationSettings_RevertIntervalTerlalupendek() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        vm.expectRevert(
            abi.encodeWithSelector(
                PlayerCard_NonLayered_Testable.IntervalTooShort.selector,
                1800,
                3600
            )
        );
        card.setAutomationSettings(1800, 0);
    }

    /// @dev TC-NL-17: setAutomationSettings revert jika belum ada token yang di-mint
    function test_NL17_SetAutomationSettings_RevertJikaBelumAdaToken() public {
        vm.expectRevert(PlayerCard_NonLayered_Testable.NoTokensMinted.selector);
        card.setAutomationSettings(7200, 0);
    }

    /// @dev TC-NL-18: setAutomationSettings revert jika targetTokenId melebihi supply
    function test_NL18_SetAutomationSettings_RevertTargetTokenTidakValid() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        vm.expectRevert(bytes("Token ID tidak valid"));
        card.setAutomationSettings(7200, 5);
    }

    // =========================================================================
    // GRUP 7: checkUpkeep
    // =========================================================================

    /// @dev TC-NL-19: checkUpkeep false jika interval belum terlewati
    function test_NL19_CheckUpkeep_FalseJikaIntervalBelumTerlewati() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        card.setAutomationSettings(86400, 0); // 24 jam

        // Maju waktu 12 jam — belum melewati interval
        vm.warp(block.timestamp + 12 hours);
        (bool needed,) = card.checkUpkeep("");
        assertFalse(needed);
    }

    /// @dev TC-NL-20: checkUpkeep true jika interval sudah terlewati
    function test_NL20_CheckUpkeep_TrueJikaIntervalSudahTerlewati() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        card.setAutomationSettings(3600, 0); // 1 jam

        // Maju waktu 2 jam — melewati interval
        vm.warp(block.timestamp + 2 hours);
        (bool needed,) = card.checkUpkeep("");
        assertTrue(needed);
    }

    // =========================================================================
    // HELPER INTERNAL
    // =========================================================================

    /// @dev Cek apakah string `haystack` mengandung substring `needle`
    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) { found = false; break; }
            }
            if (found) return true;
        }
        return false;
    }
}
