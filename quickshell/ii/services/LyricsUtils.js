.pragma library

// Fungsi murni untuk lirik berwaktu (format LRC). Dipisah dari QML supaya mudah diuji.

// "[01:23.45] baris lirik"  ->  [{ t: 83.45, text: "baris lirik" }, ...]
// Satu baris boleh punya beberapa stempel waktu: "[00:10.00][01:05.50] chorus"
function parseLrc(text) {
    var out = [];
    if (!text) return out;
    var rows = String(text).split(/\r?\n/);
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        var re = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
        var stamps = [];
        var lastEnd = 0;
        var m;
        while ((m = re.exec(row)) !== null) {
            var frac = m[3] ? parseInt((m[3] + "00").slice(0, 3), 10) / 1000 : 0;
            stamps.push(parseInt(m[1], 10) * 60 + parseInt(m[2], 10) + frac);
            lastEnd = re.lastIndex;
        }
        if (stamps.length === 0) continue; // tag metadata seperti [ar:...] ikut terlewat
        var content = row.slice(lastEnd).trim();
        for (var j = 0; j < stamps.length; j++) out.push({ t: stamps[j], text: content });
    }
    out.sort(function (a, b) { return a.t - b.t; });
    return out;
}

// Indeks baris terakhir yang waktunya <= pos. -1 kalau belum sampai baris pertama.
function findIndex(lines, pos) {
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (lines[mid].t <= pos) { ans = mid; lo = mid + 1; }
        else hi = mid - 1;
    }
    return ans;
}

// "Song - Remastered 2011", "Song (feat. X)", "Song [Remix]"  ->  "Song"
function cleanTitleForSearch(title) {
    var s = String(title || "");
    s = s.replace(/\s*[\(\[][^\)\]]*[\)\]]/g, "");
    s = s.replace(/\s+-\s+.*$/, "");
    return s.trim();
}

// "A, B", "A & B", "A feat. B"  ->  "A"
function firstArtist(artist) {
    return String(artist || "").split(/\s*(?:,|&|\sfeat\.|\sft\.|\sx\s)\s*/i)[0].trim();
}

// Dari hasil /api/search: pilih yang punya lirik berwaktu, durasinya paling dekat.
function pickBest(results, duration) {
    if (!results || !results.length) return null;
    var best = null, bestDiff = Infinity;
    for (var i = 0; i < results.length; i++) {
        var r = results[i];
        if (!r || !r.syncedLyrics) continue;
        var diff = duration > 0 && r.duration ? Math.abs(r.duration - duration) : 0;
        if (diff < bestDiff) { best = r; bestDiff = diff; }
    }
    return best;
}
