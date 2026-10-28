pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions
import "LyricsUtils.js" as LyricsUtils

Singleton {
    id: root

    readonly property bool enabled: Config.options.bar.lyrics.enable
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool isPlaying: player?.isPlaying ?? false

    property var lines: []
    property int currentIndex: -1
    property string fetchStatus: "idle"      // idle | loading | found | notfound | error
    readonly property bool hasLyrics: lines.length > 0
    readonly property string currentLine: (currentIndex >= 0 && currentIndex < lines.length) ? lines[currentIndex].text : ""

    readonly property string trackKey: `${player?.trackArtist ?? ""}|${player?.trackTitle ?? ""}|${Math.round(player?.length ?? 0)}`
    onTrackKeyChanged: debounce.restart()
    onEnabledChanged: debounce.restart()

    function load() {
    }
    Component.onCompleted: debounce.restart()

    property string cachePath: ""
    property int duration: 0

    Timer {
        id: debounce
        interval: 600
        onTriggered: root.fetchLyrics()
    }

    function reset(newStatus) {
        getProc.running = false;
        searchProc.running = false;
        lines = [];
        currentIndex = -1;
        fetchStatus = newStatus;
    }

    function fetchLyrics() {
        const title = player?.trackTitle ?? "";
        const artist = player?.trackArtist ?? "";
        if (!enabled || !player || title.length === 0) {
            reset("idle");
            return;
        }
        reset("loading");
        duration = Math.round(player.length ?? 0);
        const album = player.trackAlbum ?? "";
        const dir = FileUtils.trimFileProtocol(Directories.genericCache) + "/ii-lyrics";
        cachePath = `${dir}/${Qt.md5(`${artist}|${title}|${duration}`)}.json`;
        getProc.command = ["bash", "-c", getScript, "bash", title, artist, album, String(duration), cachePath];
        getProc.running = true;
    }

    function applyLyrics(obj) {
        if (!obj) {
            fetchStatus = "notfound";
            return;
        }
        const parsed = LyricsUtils.parseLrc(obj.syncedLyrics ?? "");
        lines = parsed;
        fetchStatus = parsed.length > 0 ? "found" : "notfound";
        updateIndex();
    }

    function updateIndex() {
        if (!hasLyrics || !player) {
            if (currentIndex !== -1) currentIndex = -1;
            return;
        }
        const pos = (player.position ?? 0) + Config.options.bar.lyrics.offsetMs / 1000;
        const idx = LyricsUtils.findIndex(lines, pos);
        if (idx !== currentIndex) currentIndex = idx;
    }

    Timer {
        interval: 250
        repeat: true
        running: root.hasLyrics && root.isPlaying
        onTriggered: {
            root.player.positionChanged();
            root.updateIndex();
        }
    }
    Connections {
        target: root.player
        function onPositionChanged() { root.updateIndex(); }
    }

    readonly property string getScript: [
        'T="$1"; A="$2"; AL="$3"; D="$4"; cache="$5"',
        'if [ -s "$cache" ]; then cat "$cache"; exit 0; fi',
        'ua="ii-lyrics-bar/1.0"',
        'fetch() {',
        '  a=(--data-urlencode "track_name=$T" --data-urlencode "artist_name=$A")',
        '  if [ "$1" = 1 ] && [ -n "$AL" ]; then a+=(--data-urlencode "album_name=$AL"); fi',
        '  if [ "$D" -gt 0 ] 2>/dev/null; then a+=(--data-urlencode "duration=$D"); fi',
        '  curl -sfG --max-time 8 -A "$ua" "https://lrclib.net/api/get" "${a[@]}"',
        '}',
        'res=$(fetch 1)',
        'if [ -z "$res" ]; then res=$(fetch 0); fi',
        'if [ -n "$res" ]; then mkdir -p "$(dirname "$cache")"; printf "%s" "$res" > "$cache"; printf "%s" "$res"; fi'
    ].join("\n")

    readonly property string searchScript: [
        'curl -sfG --max-time 8 -A "ii-lyrics-bar/1.0" "https://lrclib.net/api/search"',
        '  --data-urlencode "track_name=$1" --data-urlencode "artist_name=$2"'
    ].join(" ")

    Process {
        id: getProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.fetchStatus !== "loading") return;
                const out = text.trim();
                if (out.length > 0) {
                    try {
                        root.applyLyrics(JSON.parse(out));
                        return;
                    } catch (e) {
                        console.error(`[Lyrics] ${e.message}`);
                    }
                }
                const title = LyricsUtils.cleanTitleForSearch(root.player?.trackTitle ?? "");
                const artist = LyricsUtils.firstArtist(root.player?.trackArtist ?? "");
                searchProc.command = ["bash", "-c", root.searchScript, "bash", title.length > 0 ? title : (root.player?.trackTitle ?? ""), artist];
                searchProc.running = true;
            }
        }
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.fetchStatus !== "loading") return;
                const out = text.trim();
                if (out.length === 0) {
                    root.fetchStatus = "notfound";
                    return;
                }
                try {
                    const best = LyricsUtils.pickBest(JSON.parse(out), root.duration);
                    root.applyLyrics(best);
                    if (best && root.fetchStatus === "found") {
                        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$2")"; printf "%s" "$1" > "$2"', "bash", JSON.stringify(best), root.cachePath]);
                    }
                } catch (e) {
                    console.error(`[Lyrics] ${e.message}`);
                    root.fetchStatus = "error";
                }
            }
        }
    }
}
