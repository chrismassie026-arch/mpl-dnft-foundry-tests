// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Dependensi OpenZeppelin: standar ERC-721, kontrol akses owner, utilitas string dan Base64
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
// Dependensi Chainlink: klien dan library untuk pengambilan data off-chain via DON
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

// Kontrak utama: ERC-721 dNFT dengan integrasi Chainlink Functions dan Chainlink Automation
contract PlayerCard_NonLayered is ERC721URIStorage, Ownable, FunctionsClient {
    using Strings for uint256;
    using FunctionsRequest for FunctionsRequest.Request;

    // Custom error, lebih hemat gas dibanding string revert
    error UnknownRequestId(bytes32 requestId);
    error OracleError(bytes err);
    error IntervalTooShort(uint256 provided, uint256 minimum);
    error NoTokensMinted();

    // Struct penyimpan data statistik pemain
    struct PlayerData {
        string nickname;
        string lane;
        uint64 games;
        uint64 kills;
        uint64 deaths;
        uint64 assists;
    }

    // Konfigurasi jaringan: counter token, alamat router, dan identitas DON Sepolia
    uint256 private _tokenIds;
    address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 donId = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    uint64 public subscriptionId;
    string public sourceCode; 

    // Variabel kontrol Chainlink Automation
    uint256 public lastTimeStamp;
    uint256 public constant MINIMUM_INTERVAL = 3600; 
    uint256 public interval = 24 hours;
    uint256 public targetTokenIdToUpdate;

    // Penyimpanan data pemain dan pelacak status request oracle
    mapping(uint256 => PlayerData) public s_playerData;       
    mapping(bytes32 => uint256)    public s_requestToTokenId; 
    mapping(bytes32 => bool)       public s_requestExists;   

    // Event untuk mencatat pembaruan statistik, pengiriman request, dan perubahan konfigurasi automasi
    event PlayerStatsUpdated(
        uint256 indexed tokenId,
        uint64 games,
        uint64 kills,
        uint64 deaths,
        uint64 assists,
        uint256 timestamp
    );
    event StatsRequested(uint256 indexed tokenId, bytes32 indexed requestId, string nickname);
    event AutomationSettingsChanged(uint256 newInterval, uint256 newTargetTokenId);

    // Inisialisasi kontrak: nama token, owner, router Chainlink, subscription ID, dan timer automasi
    constructor(uint64 _subscriptionId)
        ERC721("MPL Player Card Non-Layered", "MPLNL")
        Ownable(msg.sender)
        FunctionsClient(router)
    {
        subscriptionId = _subscriptionId;
        lastTimeStamp = block.timestamp;
    }

    // Merakit SVG dinamis dari dua fungsi internal; KDA dihitung dengan integer x100 (2 desimal)
    function generateSVG(uint256 tokenId) public view returns (string memory) {
        PlayerData memory d = s_playerData[tokenId];

        // Hindari division by zero jika deaths masih 0
        uint64 safeDeaths = d.deaths == 0 ? 1 : d.deaths;
        // Hitung KDA berskala x100 untuk simulasi 2 angka desimal
        uint256 kdaScaled = (uint256(d.kills) + uint256(d.assists)) * 100 / safeDeaths;
        uint256 kdaDec = kdaScaled % 100;
        // Tambahkan leading zero pada desimal jika nilainya < 10 (misal: 4.05, bukan 4.5)
        string memory kdaStr = string.concat(
            (kdaScaled / 100).toString(), ".",
            kdaDec < 10 ? string.concat("0", kdaDec.toString()) : kdaDec.toString()
        );

        // Gabungkan dua bagian SVG dalam satu kontrak (arsitektur monolitik)
        return string.concat(
            '<svg width="320" height="400" viewBox="0 0 320 400" xmlns="http://www.w3.org/2000/svg">',
            _svgPart1(),
            _svgPart2(d, kdaStr),
            '</svg>'
        );
    }

    // Bagian SVG pertama: latar belakang kartu dan sprite pixel art karakter (layer statis)
    function _svgPart1() internal pure returns (string memory) {
        return string.concat(
            '<g shape-rendering="crispEdges">',
            '<rect x="0" y="0" width="320" height="400" fill="#0b101e"/>',
            '<rect x="8" y="8" width="304" height="384" fill="#141e33"/>',
            '<rect x="8" y="8" width="304" height="384" fill="none" stroke="#00f0ff" stroke-width="1.5" rx="2"/>',
            '<text x="160" y="36" fill="#00f0ff" font-size="16" text-anchor="middle" font-weight="bold" font-family="monospace">MPL PLAYER CARD</text>',
            '<line x1="20" y1="50" x2="300" y2="50" stroke="#00f0ff" stroke-width="2"/>',
            '</g>',
            // Sprite pixel art 32x32 piksel, di-hardcode langsung di dalam kontrak tanpa library
            '<svg x="10" y="30" width="140" height="380" viewBox="0 0 32 32" shape-rendering="crispEdges">...</svg>'
        );
    }

    // Bagian SVG kedua: panel statistik dinamis (data diambil langsung dari struct PlayerData)
    function _svgPart2(PlayerData memory d, string memory kdaStr) internal pure returns (string memory) {
        string memory labelColor = "#3498db";

        // Dibagi dua string untuk menghindari error "stack too deep"
        string memory part1 = string.concat(
            '<g transform="translate(180, 95)" shape-rendering="crispEdges">',
            '<text x="-30" y="20" fill="', labelColor, '" font-size="13" font-family="monospace">PLAYER NAME:</text>',
            '<text x="-30" y="46" fill="#ecf0f1" font-size="20" font-weight="bold" font-family="monospace">', d.nickname, '</text>',
            '<line x1="-25" y1="68" x2="120" y2="68" stroke="#555" stroke-width="3" stroke-dasharray="8,6"/>',
            '<text x="-30" y="92"  fill="', labelColor, '" font-size="13" font-family="monospace">LANE   :</text>',
            '<text x="120" y="92"  fill="#ecf0f1" font-size="13" text-anchor="end" font-family="monospace">', d.lane, '</text>',
            '<text x="-30" y="116" fill="', labelColor, '" font-size="13" font-family="monospace">GAMES  :</text>',
            '<text x="120" y="116" fill="#ecf0f1" font-size="13" text-anchor="end" font-family="monospace">', uint256(d.games).toString(), '</text>'
        );

        string memory part2 = string.concat(
            '<text x="-30" y="140" fill="', labelColor, '" font-size="13" font-family="monospace">KILLS  :</text>',
            '<text x="120" y="140" fill="#ecf0f1" font-size="13" text-anchor="end" font-family="monospace">', uint256(d.kills).toString(), '</text>',
            '<text x="-30" y="164" fill="', labelColor, '" font-size="13" font-family="monospace">DEATHS :</text>',
            '<text x="120" y="164" fill="#ecf0f1" font-size="13" text-anchor="end" font-family="monospace">', uint256(d.deaths).toString(), '</text>',
            '<text x="-30" y="188" fill="', labelColor, '" font-size="13" font-family="monospace">ASSISTS:</text>',
            '<text x="120" y="188" fill="#ecf0f1" font-size="13" text-anchor="end" font-family="monospace">', uint256(d.assists).toString(), '</text>',
            '<text x="-30" y="212" fill="', labelColor, '" font-size="13" font-family="monospace">KDA    :</text>',
            '<text x="120" y="212" fill="#ecf0f1" font-size="13" text-anchor="end" font-family="monospace">', kdaStr, '</text>',
            '<line x1="-30" y1="228" x2="120" y2="228" stroke="#555" stroke-width="3" stroke-dasharray="8,6"/>',
            '</g>'
        );

        return string.concat(part1, part2);
    }

    // Mint token baru dengan data awal; statistik diisi nol dan akan diperbarui oracle pada siklus pertama
    function safeMint(address to, string memory _nickname, string memory _lane) public onlyOwner {
        uint256 tokenId = _tokenIds;
        s_playerData[tokenId] = PlayerData(_nickname, _lane, 0, 0, 0, 0);
        _safeMint(to, tokenId);
        _tokenIds++;
    }

    // Menyimpan kode JavaScript sumber yang akan dikirim ke DON saat request dibuat
    function setSourceCode(string memory _sourceCode) public onlyOwner {
        sourceCode = _sourceCode;
    }

    // Memicu pembaruan statistik secara manual untuk token tertentu, di luar jadwal automasi
    function requestStatsUpdate(uint256 tokenId) public onlyOwner {
        require(tokenId < _tokenIds, "Token ID tidak valid");
        _requestStatsInternal(tokenId, s_playerData[tokenId].nickname);
    }

    // Membangun dan mengirim request ke Chainlink DON; mendaftarkan requestId ke mapping pelacak
    function _requestStatsInternal(uint256 tokenId, string memory nickname) internal returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(sourceCode);
        // Sisipkan nickname sebagai argumen yang diakses di JavaScript DON dengan args[0]
        string[] memory args = new string[](1);
        args[0] = nickname;
        req.setArgs(args);
        // Kirim request ke DON dengan gas limit callback 300.000 unit
        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, 300000, donId);
        s_requestToTokenId[requestId] = tokenId;
        s_requestExists[requestId] = true;
        emit StatsRequested(tokenId, requestId, nickname);
    }

    // Callback dari DON: unpack data uint256 via bit-shift, perbarui statistik, hapus mapping request
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (!s_requestExists[requestId]) revert UnknownRequestId(requestId);
        if (err.length > 0) revert OracleError(err);

        uint256 tokenId = s_requestToTokenId[requestId];
        // Decode respons ABI menjadi uint256 tunggal berisi 4 statistik yang di-pack via bit-shifting
        uint256 packedData = abi.decode(response, (uint256));

        // Unpack tiap statistik dari slot 64-bit yang sesuai
        s_playerData[tokenId].assists = uint64(packedData);        
        s_playerData[tokenId].deaths  = uint64(packedData >> 64);   
        s_playerData[tokenId].kills   = uint64(packedData >> 128);  
        s_playerData[tokenId].games   = uint64(packedData >> 192); 

        // Hapus mapping untuk mendapatkan gas refund dari pembebasan storage slot
        delete s_requestExists[requestId];
        delete s_requestToTokenId[requestId];

        PlayerData memory d = s_playerData[tokenId];
        emit PlayerStatsUpdated(tokenId, d.games, d.kills, d.deaths, d.assists, block.timestamp);
    }

    // Menyusun metadata JSON + SVG sepenuhnya on-chain, dikembalikan sebagai Base64 data URI
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        PlayerData memory d = s_playerData[tokenId];
        // Encode SVG ke Base64 untuk disematkan langsung di dalam JSON
        string memory imageBase64 = Base64.encode(bytes(generateSVG(tokenId)));

        // Atribut JSON dibagi dua bagian untuk menghindari error "stack too deep"
        string memory attrs1 = string.concat(
            '{"trait_type": "Nickname", "value": "', d.nickname,                    '"},',
            '{"trait_type": "Lane",     "value": "', d.lane,                        '"},',
            '{"trait_type": "Games",    "value": ',  uint256(d.games).toString(),   '},'
        );
        string memory attrs2 = string.concat(
            '{"trait_type": "Kills",   "value": ',  uint256(d.kills).toString(),   '},',
            '{"trait_type": "Deaths",  "value": ',  uint256(d.deaths).toString(),  '},',
            '{"trait_type": "Assists", "value": ',  uint256(d.assists).toString(), '}'
        );

        // Gabungkan seluruh JSON lalu encode ke Base64 sebagai data URI
        string memory json = Base64.encode(bytes(string.concat(
            '{"name": "MPL Card #', tokenId.toString(), '", ',
            '"description": "Kartu dNFT MPL Indonesia. Statistik pemain diperbarui secara real-time dari API melalui Chainlink Functions. Versi pembanding untuk analisis gas cost.", ',
            '"attributes": [', attrs1, attrs2, '], ',
            '"image": "data:image/svg+xml;base64,', imageBase64, '"}'
        )));
        return string.concat("data:application/json;base64,", json);
    }

    // Menetapkan interval waktu dan target token untuk siklus Chainlink Automation
    function setAutomationSettings(uint256 _intervalSeconds, uint256 _targetTokenId) public onlyOwner {
        if (_intervalSeconds < MINIMUM_INTERVAL) revert IntervalTooShort(_intervalSeconds, MINIMUM_INTERVAL);
        if (_tokenIds == 0) revert NoTokensMinted();
        require(_targetTokenId < _tokenIds, "Token ID tidak valid");
        interval = _intervalSeconds;
        targetTokenIdToUpdate = _targetTokenId;
        emit AutomationSettingsChanged(_intervalSeconds, _targetTokenId);
    }

    // Mengembalikan total token yang telah di-mint
    function totalSupply() public view returns (uint256) { return _tokenIds; }

    // Mengembalikan seluruh data statistik pemain untuk token tertentu
    function getPlayerData(uint256 tokenId) public view returns (PlayerData memory) {
        require(tokenId < _tokenIds, "Token ID tidak valid");
        return s_playerData[tokenId];
    }

    // Diperiksa Automation Node setiap blok; true jika interval terlewati dan token ID valid
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval && targetTokenIdToUpdate < _tokenIds;
        performData = bytes("");
    }

    // Dieksekusi Automation Node saat checkUpkeep true; catat timestamp lalu kirim request oracle
    function performUpkeep(bytes calldata) external {
        if ((block.timestamp - lastTimeStamp) > interval) {
            lastTimeStamp = block.timestamp;
            _requestStatsInternal(targetTokenIdToUpdate, s_playerData[targetTokenIdToUpdate].nickname);
        }
    }
}
