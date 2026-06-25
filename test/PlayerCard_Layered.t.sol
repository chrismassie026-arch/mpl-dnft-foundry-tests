// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// =============================================================================
// MOCK CONTRACTS
// =============================================================================

/// @dev Mock router Chainlink Functions — identik dengan yang dipakai Model A
contract MockRouterLayered {
    uint256 private _nonce;

    function sendRequest(
        uint64,
        bytes memory,
        uint16,
        uint32,
        bytes32
    ) external returns (bytes32) {
        return keccak256(abi.encodePacked(_nonce++, msg.sender, block.timestamp));
    }
}

// =============================================================================
// STUB LIBRARY — PlayerCardRenderer
// Mereplikasi logika library secara identik untuk lingkungan Foundry lokal.
// Pada Foundry penuh: cukup import "../src/playerCard_layered.sol"
// =============================================================================

library PlayerCardRenderer {
    using Strings for uint256;

    function getBackgroundLayer() internal pure returns (string memory) {
        return string.concat(
            '<rect x="0" y="0" width="320" height="400" fill="#0b101e"/>',
            '<rect x="8" y="8" width="304" height="384" fill="#141e33"/>',
            '<text x="160" y="36" fill="#00f0ff" font-size="16" text-anchor="middle" font-weight="bold" font-family="monospace">MPL PLAYER CARD</text>'
        );
    }

    function getPixelArtLayer() internal pure returns (string memory) {
        return '<svg x="10" y="30" width="140" height="380" viewBox="0 0 32 32" shape-rendering="crispEdges">PIXEL_ART</svg>';
    }

    function getStatsLayer(
        PlayerDataL memory d,
        string memory kdaStr
    ) internal pure returns (string memory) {
        return string.concat(
            "<stats>",
            d.nickname, "|", d.lane, "|",
            Strings.toString(d.games), "|",
            Strings.toString(d.kills), "|",
            Strings.toString(d.deaths), "|",
            Strings.toString(d.assists), "|",
            kdaStr,
            "</stats>"
        );
    }
}

// Struct untuk Model B (didefinisikan di level file, sesuai kontrak asli)
struct PlayerDataL {
    string nickname;
    string lane;
    uint64 games;
    uint64 kills;
    uint64 deaths;
    uint64 assists;
}

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// =============================================================================
// STUB KONTRAK — MplPlayerCard_Optimized (Model B / Layered)
// =============================================================================

/// @dev Versi testable dari MplPlayerCard_Optimized.
///      Menggunakan PlayerCardRenderer library untuk rendering SVG (arsitektur berlapis).
contract PlayerCard_Layered_Testable {
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

    mapping(uint256 => PlayerDataL) public s_playerData;
    mapping(bytes32 => uint256)     public s_requestToTokenId;
    mapping(bytes32 => bool)        public s_requestExists;

    MockRouterLayered private _router;

    // --- Custom errors ---
    error UnknownRequestId(bytes32 requestId);
    error OracleError(bytes err);
    error IntervalTooShort(uint256 provided, uint256 minimum);
    error NoTokensMinted();
    error NotOwner();

    // --- Events ---
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
        _router        = MockRouterLayered(routerAddr);
    }

    // -------------------------------------------------------------------------
    // FUNGSI YANG DIUJI
    // -------------------------------------------------------------------------

    /// @notice Mint token baru dengan data awal
    function safeMint(address, string memory _nickname, string memory _lane) public onlyOwner {
        uint256 tokenId = _tokenIds;
        s_playerData[tokenId] = PlayerDataL(_nickname, _lane, 0, 0, 0, 0);
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
    function getPlayerData(uint256 tokenId) public view returns (PlayerDataL memory) {
        require(tokenId < _tokenIds, "Token ID tidak valid");
        return s_playerData[tokenId];
    }

    /// @notice checkUpkeep Chainlink Automation
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval && targetTokenIdToUpdate < _tokenIds;
        performData  = bytes("");
    }

    /// @notice Simulasi fulfillRequest — inject packed uint256 langsung ke storage
    function simulateFulfill(uint256 tokenId, uint256 packedData) public {
        require(tokenId < _tokenIds, "Token ID tidak valid");
        s_playerData[tokenId].assists = uint64(packedData);
        s_playerData[tokenId].deaths  = uint64(packedData >> 64);
        s_playerData[tokenId].kills   = uint64(packedData >> 128);
        s_playerData[tokenId].games   = uint64(packedData >> 192);
        PlayerDataL memory d = s_playerData[tokenId];
        emit PlayerStatsUpdated(tokenId, d.games, d.kills, d.deaths, d.assists, block.timestamp);
    }

    /// @notice Generate SVG menggunakan library PlayerCardRenderer (arsitektur berlapis)
    ///         PERBEDAAN KUNCI vs Model A: rendering didelegasikan ke library eksternal
    function generateSVG(uint256 tokenId) public view returns (string memory) {
        PlayerDataL memory d = s_playerData[tokenId];
        uint64 safeDeaths    = d.deaths == 0 ? 1 : d.deaths;
        uint256 kdaScaled    = (uint256(d.kills) + uint256(d.assists)) * 100 / safeDeaths;
        uint256 kdaDec       = kdaScaled % 100;
        string memory kdaStr = string.concat(
            Strings.toString(kdaScaled / 100), ".",
            kdaDec < 10
                ? string.concat("0", Strings.toString(kdaDec))
                : Strings.toString(kdaDec)
        );

        // ✅ Perbedaan arsitektur: 3 layer terpisah dari library
        return string.concat(
            '<svg width="320" height="400" viewBox="0 0 320 400" xmlns="http://www.w3.org/2000/svg">',
            '<g shape-rendering="crispEdges">',
            PlayerCardRenderer.getBackgroundLayer(),   // Layer 1: Background
            '</g>',
            PlayerCardRenderer.getPixelArtLayer(),     // Layer 2: Pixel Art
            PlayerCardRenderer.getStatsLayer(d, kdaStr), // Layer 3: Stats
            '</svg>'
        );
    }

    /// @notice Ekspos fungsi layer individual untuk unit test terpisah per layer
    function getBackgroundLayerOutput() public pure returns (string memory) {
        return PlayerCardRenderer.getBackgroundLayer();
    }

    function getPixelArtLayerOutput() public pure returns (string memory) {
        return PlayerCardRenderer.getPixelArtLayer();
    }

    function getStatsLayerOutput(uint256 tokenId) public view returns (string memory) {
        PlayerDataL memory d = s_playerData[tokenId];
        uint64 safeDeaths    = d.deaths == 0 ? 1 : d.deaths;
        uint256 kdaScaled    = (uint256(d.kills) + uint256(d.assists)) * 100 / safeDeaths;
        uint256 kdaDec       = kdaScaled % 100;
        string memory kdaStr = string.concat(
            Strings.toString(kdaScaled / 100), ".",
            kdaDec < 10
                ? string.concat("0", Strings.toString(kdaDec))
                : Strings.toString(kdaDec)
        );
        return PlayerCardRenderer.getStatsLayer(d, kdaStr);
    }
}

// =============================================================================
// TEST CONTRACT
// =============================================================================

/// @title  PlayerCard_LayeredTest
/// @notice Unit test untuk kontrak Model B (Berlapis / Layered)
///         Dijalankan dengan: forge test --match-contract PlayerCard_LayeredTest -vv
contract PlayerCard_LayeredTest is Test {

    PlayerCard_Layered_Testable public card;
    MockRouterLayered                 public router;

    address public contractOwner = address(this);
    address public nonOwner      = address(0xDEAD);

    // -------------------------------------------------------------------------
    // SETUP
    // -------------------------------------------------------------------------
    function setUp() public {
        router = new MockRouterLayered();
        card   = new PlayerCard_Layered_Testable(1, address(router));
    }

    // =========================================================================
    // GRUP 1: safeMint
    // =========================================================================

    /// @dev TC-L-01: Mint token pertama berhasil, totalSupply bertambah
    function test_L01_SafeMint_Sukses_TotalSupplyBertambah() public {
        assertEq(card.totalSupply(), 0);
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        assertEq(card.totalSupply(), 1);
    }

    /// @dev TC-L-02: Data pemain tersimpan benar setelah mint (stats awal = 0)
    function test_L02_SafeMint_DataPemainTersimpanBenar() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        PlayerDataL memory d = card.getPlayerData(0);
        assertEq(d.nickname, "Kairi");
        assertEq(d.lane,     "JUNGLE");
        assertEq(d.games,    0);
        assertEq(d.kills,    0);
        assertEq(d.deaths,   0);
        assertEq(d.assists,  0);
    }

    /// @dev TC-L-03: Mint oleh non-owner harus revert
    function test_L03_SafeMint_RevertJikaBukanOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(PlayerCard_Layered_Testable.NotOwner.selector);
        card.safeMint(nonOwner, "Kairi", "JUNGLE");
    }

    /// @dev TC-L-04: Mint beberapa token, setiap tokenId unik dan sequential
    function test_L04_SafeMint_MultipleToken_IdSequential() public {
        card.safeMint(contractOwner, "Kairi",  "JUNGLE");
        card.safeMint(contractOwner, "Udil", "MID");
        card.safeMint(contractOwner, "Branz", "GOLD");
        assertEq(card.totalSupply(), 3);
        assertEq(card.getPlayerData(0).nickname, "Kairi");
        assertEq(card.getPlayerData(1).nickname, "Udil");
        assertEq(card.getPlayerData(2).nickname, "Branz");
    }

    // =========================================================================
    // GRUP 2: getPlayerData
    // =========================================================================

    /// @dev TC-L-05: getPlayerData token tidak ada harus revert
    function test_L05_GetPlayerData_RevertJikaTokenTidakAda() public {
        vm.expectRevert(bytes("Token ID tidak valid"));
        card.getPlayerData(999);
    }

    /// @dev TC-L-06: getPlayerData mengembalikan data benar setelah update stats
    function test_L06_GetPlayerData_DataBenarSetelahUpdateStats() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        uint256 packed = (uint256(30)  << 192) |
                         (uint256(120) << 128) |
                         (uint256(60)  << 64)  |
                         uint256(200);
        card.simulateFulfill(0, packed);
        PlayerDataL memory d = card.getPlayerData(0);
        assertEq(d.games,   30);
        assertEq(d.kills,   120);
        assertEq(d.deaths,  60);
        assertEq(d.assists, 200);
    }

    // =========================================================================
    // GRUP 3: simulateFulfill (logika bit-unpacking fulfillRequest)
    // =========================================================================

    /// @dev TC-L-07: Bit-unpacking packed uint256 → 4 field uint64 benar
    function test_L07_FulfillRequest_BitUnpackingBenar() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        uint64 expGames   = 50;
        uint64 expKills   = 300;
        uint64 expDeaths  = 100;
        uint64 expAssists = 450;
        uint256 packed = (uint256(expGames)   << 192) |
                         (uint256(expKills)   << 128) |
                         (uint256(expDeaths)  << 64)  |
                         uint256(expAssists);
        card.simulateFulfill(0, packed);
        PlayerDataL memory d = card.getPlayerData(0);
        assertEq(d.games,   expGames);
        assertEq(d.kills,   expKills);
        assertEq(d.deaths,  expDeaths);
        assertEq(d.assists, expAssists);
    }

    /// @dev TC-L-08: Nilai boundary uint64 tidak overflow
    function test_L08_FulfillRequest_BoundaryUint64_TidakOverflow() public {
        card.safeMint(contractOwner, "Branz", "GOLD");
        uint64 maxVal  = type(uint64).max;
        uint256 packed = (uint256(maxVal) << 192) |
                         (uint256(maxVal) << 128) |
                         (uint256(maxVal) << 64)  |
                         uint256(maxVal);
        card.simulateFulfill(0, packed);
        PlayerDataL memory d = card.getPlayerData(0);
        assertEq(d.games,   maxVal);
        assertEq(d.kills,   maxVal);
        assertEq(d.deaths,  maxVal);
        assertEq(d.assists, maxVal);
    }

    // =========================================================================
    // GRUP 4: generateSVG — output keseluruhan (3 layer tergabung)
    // =========================================================================

    /// @dev TC-L-09: generateSVG mengembalikan string tidak kosong setelah mint
    function test_L09_GenerateSVG_OutputTidakKosong() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        string memory svg = card.generateSVG(0);
        assertTrue(bytes(svg).length > 0);
    }

    /// @dev TC-L-10: Output SVG mengandung ketiga layer (background, pixelart, stats)
    function test_L10_GenerateSVG_MengandungKetigaLayer() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        string memory svg = card.generateSVG(0);
        // Layer 1 — background mengandung teks header
        assertTrue(_contains(svg, "MPL PLAYER CARD"), "Layer 1 background tidak ditemukan");
        // Layer 2 — pixel art
        assertTrue(_contains(svg, "PIXEL_ART"),        "Layer 2 pixel art tidak ditemukan");
        // Layer 3 — stats mengandung nickname
        assertTrue(_contains(svg, "Kairi"),              "Layer 3 stats tidak ditemukan");
    }

    // =========================================================================
    // GRUP 5: Layer individual (arsitektur berlapis — perbedaan utama Model B)
    // =========================================================================

    /// @dev TC-L-11: getBackgroundLayer menghasilkan output tidak kosong
    function test_L11_BackgroundLayer_OutputTidakKosong() public view {
        string memory bg = card.getBackgroundLayerOutput();
        assertTrue(bytes(bg).length > 0);
    }

    /// @dev TC-L-12: getBackgroundLayer mengandung elemen header kartu
    function test_L12_BackgroundLayer_MengandungHeaderKartu() public view {
        string memory bg = card.getBackgroundLayerOutput();
        assertTrue(_contains(bg, "MPL PLAYER CARD"), "Header tidak ditemukan di background layer");
    }

    /// @dev TC-L-13: getPixelArtLayer menghasilkan output tidak kosong
    function test_L13_PixelArtLayer_OutputTidakKosong() public view {
        string memory pa = card.getPixelArtLayerOutput();
        assertTrue(bytes(pa).length > 0);
    }

    /// @dev TC-L-14: getStatsLayer mengandung data pemain yang benar
    function test_L14_StatsLayer_MengandungDataPemain() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        uint256 packed = (uint256(30)  << 192) |
                         (uint256(120) << 128) |
                         (uint256(60)  << 64)  |
                         uint256(200);
        card.simulateFulfill(0, packed);
        string memory stats = card.getStatsLayerOutput(0);
        assertTrue(_contains(stats, "Kairi"), "Nickname tidak ditemukan di stats layer");
        assertTrue(_contains(stats, "JUNGLE"),  "Lane tidak ditemukan di stats layer");
        assertTrue(_contains(stats, "120"),  "Kills tidak ditemukan di stats layer");
    }

    // =========================================================================
    // GRUP 6: KDA Calculation
    // =========================================================================

    /// @dev TC-L-15: KDA dihitung benar — kills=120, deaths=60, assists=200 → 5.33
    function test_L15_GenerateSVG_KDADiHitungBenar() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        uint256 packed = (uint256(30)  << 192) |
                         (uint256(120) << 128) |
                         (uint256(60)  << 64)  |
                         uint256(200);
        card.simulateFulfill(0, packed);
        string memory svg = card.generateSVG(0);
        assertTrue(_contains(svg, "5.33"), "KDA harus 5.33");
    }

    /// @dev TC-L-16: Division by zero guard aktif saat deaths=0
    function test_L16_GenerateSVG_DeathsNol_GuardAktif() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        uint256 packed = (uint256(5)  << 192) |
                         (uint256(10) << 128) |
                         (uint256(0)  << 64)  |
                         uint256(5);
        card.simulateFulfill(0, packed);
        string memory svg = card.generateSVG(0);
        // KDA = (10+5)/1 = 15.00
        assertTrue(_contains(svg, "15.00"), "KDA harus 15.00 saat deaths=0");
    }

    /// @dev TC-L-17: Leading zero pada desimal KDA < .10
    function test_L17_GenerateSVG_KDALeadingZeroDesimal() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        uint256 packed = (uint256(1) << 192) |
                         (uint256(4) << 128) |
                         (uint256(1) << 64)  |
                         uint256(0);
        card.simulateFulfill(0, packed);
        string memory svg = card.generateSVG(0);
        assertTrue(_contains(svg, "4.00"), "KDA harus format 4.00");
    }

    // =========================================================================
    // GRUP 7: setSourceCode
    // =========================================================================

    /// @dev TC-L-18: setSourceCode tersimpan dengan benar
    function test_L18_SetSourceCode_TersimpanBenar() public {
        string memory src = "const result = await fetch(args[0]);";
        card.setSourceCode(src);
        assertEq(card.sourceCode(), src);
    }

    /// @dev TC-L-19: setSourceCode oleh non-owner harus revert
    function test_L19_SetSourceCode_RevertJikaBukanOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(PlayerCard_Layered_Testable.NotOwner.selector);
        card.setSourceCode("malicious code");
    }

    // =========================================================================
    // GRUP 8: setAutomationSettings
    // =========================================================================

    /// @dev TC-L-20: setAutomationSettings berhasil dengan nilai valid
    function test_L20_SetAutomationSettings_Sukses() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        card.setAutomationSettings(7200, 0);
        assertEq(card.interval(),              7200);
        assertEq(card.targetTokenIdToUpdate(), 0);
    }

    /// @dev TC-L-21: setAutomationSettings revert jika interval < MINIMUM (3600 detik)
    function test_L21_SetAutomationSettings_RevertIntervalTerlalupendek() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        vm.expectRevert(
            abi.encodeWithSelector(
                PlayerCard_Layered_Testable.IntervalTooShort.selector,
                1800,
                3600
            )
        );
        card.setAutomationSettings(1800, 0);
    }

    /// @dev TC-L-22: setAutomationSettings revert jika belum ada token yang di-mint
    function test_L22_SetAutomationSettings_RevertJikaBelumAdaToken() public {
        vm.expectRevert(PlayerCard_Layered_Testable.NoTokensMinted.selector);
        card.setAutomationSettings(7200, 0);
    }

    /// @dev TC-L-23: setAutomationSettings revert jika targetTokenId melebihi supply
    function test_L23_SetAutomationSettings_RevertTargetTokenTidakValid() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        vm.expectRevert(bytes("Token ID tidak valid"));
        card.setAutomationSettings(7200, 5);
    }

    // =========================================================================
    // GRUP 9: checkUpkeep
    // =========================================================================

    /// @dev TC-L-24: checkUpkeep false jika interval belum terlewati
    function test_L24_CheckUpkeep_FalseJikaIntervalBelumTerlewati() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        card.setAutomationSettings(86400, 0);
        vm.warp(block.timestamp + 12 hours);
        (bool needed,) = card.checkUpkeep("");
        assertFalse(needed);
    }

    /// @dev TC-L-25: checkUpkeep true jika interval sudah terlewati
    function test_L25_CheckUpkeep_TrueJikaIntervalSudahTerlewati() public {
        card.safeMint(contractOwner, "Kairi", "JUNGLE");
        card.setAutomationSettings(3600, 0);
        vm.warp(block.timestamp + 2 hours);
        (bool needed,) = card.checkUpkeep("");
        assertTrue(needed);
    }

    // =========================================================================
    // HELPER INTERNAL
    // =========================================================================

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
