import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "EquationParser.js" as EquationParser

PlasmoidItem {
    id: root
    implicitWidth: 1920
    implicitHeight: 1080
    Layout.minimumWidth: 1920
    Layout.minimumHeight: 1080
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    // Preserve the original 16:9 ellipse clearance from the screen edges.
    readonly property real ry: Math.min((height - 200) / 2, (width - 160) * 9 / 32)
    readonly property real rx: ry * 16 / 9
    readonly property real circleRadius: Math.min(rx, ry)
    property real orbitRotation: 0
    property real orbitVelocity: 0
    property real autoRotationRpm: Number(plasmoid.configuration.autoRotation || 0)
    property real dragVelocity: 0
    property bool orbitDragging: false
    property bool pathTransitioning: false
    property var audioLevels: []
    property var audioVisualLevels: []
    property var audioSpacingOffsets: []
    property bool audioSignalActive: false
    property real audioSmoothTime: 0
    property var audioSinks: [{name:"", description:"Default output"}]
    property string audioSinkName: plasmoid.configuration.audioSink || ""
    property real audioLastUpdate: 0
    property real audioStartedAt: 0
    property var resolvedPositions: []
    property string audioStatus: ""
    property string audioBuffer: ""
    property bool audioCaptureRunning: false
    property bool audioPollRunning: false
    property real audioFrameTime: 0
    readonly property string audioFrameFile: "/tmp/io.github.catprincehq2.desktop-orbit-audio.json"
    // Start with no machine-specific shortcuts; users add their own launchers.
    readonly property var defaultLaunchers: []
    property var launchers: loadLaunchers()
    property bool weatherVisible: plasmoid.configuration.weatherVisible === undefined ? true : plasmoid.configuration.weatherVisible
    property string equation: plasmoid.configuration.equation || "ellipse"
    property string equationText: equation === "custom" ? (plasmoid.configuration.equationExpression || "y = x") : equation === "sine" ? "y = sin(x)" : equation === "line" ? "y = x" : equation
    property var equationFunction: null
    property string equationMessage: ""
    property var sampledPath: []
    property real pathLength: 0
    property bool pathClosed: true
    property string weatherPlace: plasmoid.configuration.weatherPlace || "London, United Kingdom"
    property string weatherLatitude: plasmoid.configuration.weatherLatitude === undefined ? "51.5074" : String(plasmoid.configuration.weatherLatitude)
    property string weatherLongitude: plasmoid.configuration.weatherLongitude === undefined ? "-91.65788" : String(plasmoid.configuration.weatherLongitude)
    property bool showWeatherLocation: plasmoid.configuration.showWeatherLocation === undefined ? true : plasmoid.configuration.showWeatherLocation
    property bool locationSettingsOpen: false
    readonly property real unit: height / 2

    function loadLaunchers() {
        var saved = plasmoid.configuration.launcherJson
        if (saved) { try { var list = JSON.parse(saved); if (Array.isArray(list)) return list } catch (e) {} }
        return defaultLaunchers
    }
    function refreshLauncherMetadata() {
        for (var i = 0; i < launchers.length; ++i)
            launcherMetadataReader.request(launchers[i].file)
    }
    function saveLaunchers() { plasmoid.configuration.launcherJson = JSON.stringify(launchers) }
    function persistVisibility() { plasmoid.configuration.weatherVisible = weatherVisible }
    function persistEquation() {
        plasmoid.configuration.equation = equation
        plasmoid.configuration.equationExpression = equation === "custom" ? equationText : ""
    }
    function insideWeatherExclusion(p, rect) { return p.x > rect.left && p.x < rect.right && p.y > rect.top && p.y < rect.bottom }
    function boundaryCross(a, b, rect) {
        var lo=0, hi=1, aInside=insideWeatherExclusion(a,rect)
        for (var i=0;i<24;i++) {
            var t=(lo+hi)/2, p={x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t}
            if (insideWeatherExclusion(p,rect) === aInside) lo=t; else hi=t
        }
        var t=(lo+hi)/2
        return {x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t}
    }
    function perimeterCoordinate(p, rect) {
        var w=rect.right-rect.left, h=rect.bottom-rect.top
        var distances=[Math.abs(p.y-rect.top),Math.abs(p.x-rect.right),Math.abs(p.y-rect.bottom),Math.abs(p.x-rect.left)]
        var side=0; for (var i=1;i<4;i++) if (distances[i]<distances[side]) side=i
        if (side===0) return Math.max(0,Math.min(w,p.x-rect.left))
        if (side===1) return w+Math.max(0,Math.min(h,p.y-rect.top))
        if (side===2) return w+h+Math.max(0,Math.min(w,rect.right-p.x))
        return 2*w+h+Math.max(0,Math.min(h,rect.bottom-p.y))
    }
    function perimeterPoint(s, rect) {
        var w=rect.right-rect.left, h=rect.bottom-rect.top, p=2*(w+h)
        s=((s%p)+p)%p
        if (s<=w) return {x:rect.left+s,y:rect.top}
        s-=w; if (s<=h) return {x:rect.right,y:rect.top+s}
        s-=h; if (s<=w) return {x:rect.right-s,y:rect.bottom}
        s-=w; return {x:rect.left,y:rect.bottom-s}
    }
    function detourAroundWeather(entry, exit, rect, out) {
        var w=rect.right-rect.left, h=rect.bottom-rect.top, perimeter=2*(w+h)
        var start=perimeterCoordinate(entry,rect), end=perimeterCoordinate(exit,rect)
        var delta=((end-start+perimeter)%perimeter)
        if (delta>perimeter/2) delta-=perimeter
        var steps=Math.max(1,Math.ceil(Math.abs(delta)/18))
        for (var i=1;i<=steps;i++) out.push(perimeterPoint(start+delta*i/steps,rect))
    }
    function routeAroundWeather(points, closed) {
        var rect={left:cx-310,right:cx+310,top:cy-170,bottom:cy+330}
        var src=points
        if (closed && points.length>2) {
            var count=points.length-1, start=0
            while (start<count && insideWeatherExclusion(points[start],rect)) start++
            if (start===count) return points
            src=[]
            for (var j=0;j<count;j++) src.push(points[(start+j)%count])
            src.push(src[0])
        }
        var out=[src[0]], inGap=insideWeatherExclusion(src[0],rect), entry=null
        for (var k=1;k<src.length;k++) {
            var a=src[k-1], b=src[k], aIn=insideWeatherExclusion(a,rect), bIn=insideWeatherExclusion(b,rect)
            if (!aIn && !bIn) { out.push(b); continue }
            if (!aIn && bIn) { entry=boundaryCross(a,b,rect); out.push(entry); inGap=true; continue }
            if (aIn && bIn) continue
            if (aIn && !bIn) {
                var exit=boundaryCross(a,b,rect)
                if (entry) detourAroundWeather(entry,exit,rect,out); else out.push(exit)
                out.push(b); entry=null; inGap=false
            }
        }
        return out
    }
    function buildPath(kind) {
        var pts = [], n = 720, cx = width / 2, cy = height / 2, left = 0, right = width
        pathClosed = kind === "ellipse" || kind === "circle"
        for (var i = 0; i <= n; ++i) {
            var t = i / n, x = 0, y = 0
            if (kind === "ellipse") { var a = t * Math.PI * 2; x = (rx / unit) * Math.cos(a); y = (ry / unit) * Math.sin(a) }
            else if (kind === "circle") { var c = t * Math.PI * 2; x = (circleRadius / unit) * Math.cos(c); y = (circleRadius / unit) * Math.sin(c) }
            else if (kind === "line") { x = 2*t - 1; y = x }
        else if (kind === "sine") { x = ((left + t * (right-left)) - cx) / unit; y = Math.sin(x) }
            else if (kind === "custom") {
                x = ((left + t * (right-left)) - cx) / unit
                var value = equationFunction ? equationFunction(x) : 0
                var yLimit = Math.max(0, (height / 2 - 36) / unit)
                if (!Number.isFinite(value)) value = value < 0 ? -yLimit : value > 0 ? yLimit : 0
                y = Math.max(-yLimit, Math.min(yLimit, value))
            }
            // Overscan both horizontal edges so icons wrap cleanly without a
            // visible gap, while keeping the row centered on the screen.
            else if (kind === "soundwave") { x = ((-100 + t * (width + 200)) - cx) / unit; y = 0 }
            else if (kind === "spiral") { var s = t * Math.PI * 4, r = 0.08 + 0.82*t; x = r*Math.cos(s); y = r*Math.sin(s) }
            var px = cx + x * unit, py = cy + y * unit
            pts.push({x:px, y:py})
        }
        if (pts.length < 2) { pathLength = 0; return [] }
        if (weatherVisible && kind !== "ellipse" && kind !== "soundwave") pts = routeAroundWeather(pts, pathClosed)
        // Arc-length table makes icon spacing uniform on every supported curve.
        var out = [ {x:pts[0].x, y:pts[0].y, d:0} ], total = 0
        for (var j = 1; j < pts.length; ++j) { total += Math.hypot(pts[j].x-pts[j-1].x, pts[j].y-pts[j-1].y); out.push({x:pts[j].x,y:pts[j].y,d:total}) }
        pathLength = total
        return out
    }
    function applyEquation(text) {
        var s = text.toLowerCase().replace(/\s/g, "")
        var kind = "", nextFunction = null
        if (s === "ellipse" || s === "default") kind = "ellipse"
        else if (s === "line") kind = "line"
        else if (s === "x^2+y^2=1" || s === "circle" || s === "x=cos(t),y=sin(t)" || s === "x=cos(t);y=sin(t)") kind = "circle"
        else if (s === "sine") kind = "sine"
        else if (s === "spiral" || s === "x=r*cos(t),y=r*sin(t),r=t/(4*pi)") kind = "spiral"
        else if (s === "soundwave" || s === "sound wave" || s === "audio") kind = "soundwave"
        if (!kind) {
            try {
                nextFunction = EquationParser.compileY(s)
                var finiteSamples = 0
                for (var sample=0;sample<=16;sample++) {
                    var sampleX = ((sample / 16 * width) - cx) / unit
                    if (Number.isFinite(nextFunction(sampleX))) finiteSamples++
                }
                if (finiteSamples < 2) throw new Error("The expression has no finite values on screen.")
                kind = "custom"
            } catch (error) {
                equationMessage = "Enter y=f(x), for example y=2x or y=2sin(3x). " + String(error.message || error)
                return false
            }
        }
        var previousKind=equation, previousFunction=equationFunction, previousText=equationText
        pathTransitioning = true
        pathTransitionTimer.restart()
        equation = kind
        equationFunction = kind === "custom" ? nextFunction : null
        equationText = kind === "custom" ? String(text).trim() : kind === "sine" ? "y = sin(x)" : kind === "line" ? "y = x" : kind
        sampledPath = buildPath(kind)
        if (sampledPath.length < 2) {
            equation=previousKind; equationFunction=previousFunction; equationText=previousText
            sampledPath=buildPath(previousKind)
            equationMessage = "That curve has no usable points."
            return false
        }
        audioStatus = kind === "soundwave" ? "Connecting to output…" : ""
        if (kind === "soundwave") { audioStartedAt=Date.now(); refreshAudioSinks() }
        persistEquation(); equationMessage = "Applied " + kind + " · x/y units are monitor height ÷ 2."; return true
    }
    function pointAt(distance) {
        var p = sampledPath
        if (!p || p.length < 2) return {x:cx, y:cy}
        if (root.pathLength <= 0) return {x:cx, y:cy}
        var d = ((distance % root.pathLength) + root.pathLength) % root.pathLength
        var lo = 0, hi = p.length-1
        while (lo < hi) { var mid = Math.floor((lo+hi)/2); if (p[mid].d < d) lo = mid+1; else hi = mid }
        var b = p[lo], a = p[Math.max(0,lo-1)], span = b.d-a.d, f = span ? (d-a.d)/span : 0
        return {x:a.x+(b.x-a.x)*f,y:a.y+(b.y-a.y)*f}
    }
    function rebuildLauncherPositions() {
        if (pathLength <= 0 || launchers.length === 0) { resolvedPositions=[]; return }
        var count = launchers.length, positions = [], coordinates=[]
        for (var k=0;k<count;k++) positions.push((k / Math.max(1,count)) * pathLength + orbitRotation * pathLength / (2*Math.PI))
        // Resolve visual collisions by moving each pair equally in opposite
        // directions along the path, keeping their shared midpoint stable.
        // Cache one screen position per icon per pass. This avoids sampling the
        // path for every pair, and this solver runs once per frame rather than
        // once for every delegate.
        for (var pass=0;equation !== "soundwave" && pass<3;pass++) {
            var changed=false
            coordinates=[]
            for (var c=0;c<count;c++) {
                var point=pointAt(positions[c])
                if (equation === "soundwave") point.y=soundwaveY(audioVisualLevels[c]||0)
                coordinates.push(point)
            }
            for (var a=0;a<count;a++) for (var b=a+1;b<count;b++) {
                var pa=coordinates[a], pb=coordinates[b]
                var dx=pb.x-pa.x, dy=pb.y-pa.y, distance=Math.hypot(dx,dy), minDistance=90
                if (distance >= minDistance) continue
                var delta=positions[b]-positions[a]
                if (delta > pathLength/2) delta-=pathLength
                if (delta < -pathLength/2) delta+=pathLength
                var direction=delta >= 0 ? 1 : -1
                var push=(minDistance-distance+1)/2
                positions[a]-=direction*push
                positions[b]+=direction*push
                changed=true
            }
            if (!changed) break
        }
        var result=[]
        for (var n=0;n<count;n++) {
            var finalPoint=pointAt(positions[n])
            if (equation === "soundwave") finalPoint.y=soundwaveY(audioVisualLevels[n]||0)
            result.push(finalPoint)
        }
        if (equation === "soundwave") {
            // Softly repel close neighbors over multiple frames. The prior
            // hard correction snapped icons directly to the full 28px gap.
            var offsets=audioSpacingOffsets.slice()
            while (offsets.length<count) offsets.push(0)
            offsets.length=count
            if (audioSignalActive) {
                for (var i=0;i<count-1;i++) {
                    var gap=result[i+1].y+offsets[i+1]-result[i].y-offsets[i]
                    var magnitude=Math.abs(gap)
                    if (magnitude>=28) continue
                    var direction=gap===0 ? (i%2===0 ? 1 : -1) : Math.sign(gap)
                    var push=Math.min(0.55,(28-magnitude)*0.1)
                    offsets[i]-=direction*push
                    offsets[i+1]+=direction*push
                }
            } else {
                for (var j=0;j<count;j++) offsets[j]*=0.94
            }
            audioSpacingOffsets=offsets
            for (var k=0;k<count;k++) result[k].y+=offsets[k]
        }
        resolvedPositions=result
    }
    function launcherCenter(i) {
        if (i >= 0 && i < resolvedPositions.length) return resolvedPositions[i]
        return {x:cx,y:cy}
    }
    function soundwaveY(level) {
        // Silence rests on center. Levels use a perceptual dB curve; the
        // midpoint represents about -48 dBFS, giving active noise headroom
        // above center without making near-full-scale samples bunch at max.
        if (!audioSignalActive && level<=0.003) return cy
        var pivot=0.35, travel=340, displacement=level>=pivot
            ? (level-pivot)/(1-pivot)*travel
            : -(pivot-level)/pivot*travel
        return cy-displacement
    }
    function audioSourceCommand() {
        var helper = Qt.resolvedUrl("../scripts/audio_levels.py")
        var helperPath = decodeURIComponent(String(helper).replace(/^file:\/\//, ""))
        return "python3 " + safeShell(helperPath) + " " + launchers.length + " " + safeShell(audioSinkName) + " " + safeShell(audioFrameFile)
    }
    function refreshAudioSinks() {
        var helper = Qt.resolvedUrl("../scripts/audio_devices.py")
        var helperPath = decodeURIComponent(String(helper).replace(/^file:\/\//, ""))
        sinkEnumerator.connectSource("python3 " + safeShell(helperPath))
    }
    function pollAudioFrame() {
        if (equation !== "soundwave" || audioPollRunning) return
        audioPollRunning = true
        audioReader.connectSource("cat " + safeShell(audioFrameFile))
    }
    function safeShell(path) { return "'" + path.replace(/'/g, "'\\''") + "'" }
    function addLauncher(path) {
        if (!path || !path.toString().endsWith(".desktop")) { equationMessage = "Choose a .desktop launcher file."; return }
        var p = path.toLocalFile ? path.toLocalFile() : path.toString().replace(/^file:\/\//, "")
        for (var i=0;i<launchers.length;i++) if (launchers[i].file === p) { equationMessage = "That launcher is already on the orbit."; return }
        var fallbackName = p.split("/").pop().replace(/\.desktop$/i, "").replace(/[-_]/g, " ")
        var updated = launchers.slice(); updated.push({name:fallbackName, icon:"application-x-executable", file:p}); launchers=updated; saveLaunchers()
        launcherMetadataReader.request(p)
        equationMessage = "Added " + fallbackName + "."
    }
    function removeLauncher(i) { var updated=launchers.slice(); updated.splice(i,1); launchers=updated; saveLaunchers(); equationMessage="Launcher removed." }
    Component.onCompleted: {
        refreshLauncherMetadata()
        if (equation === "custom") {
            if (!applyEquation(equationText)) {
                equation="ellipse"; equationFunction=null; equationText="ellipse"; persistEquation()
                sampledPath=buildPath(equation); rebuildLauncherPositions()
            }
        } else {
            if (["ellipse", "line", "circle", "sine", "spiral", "soundwave"].indexOf(equation) < 0) { equation="ellipse"; persistEquation() }
            sampledPath = buildPath(equation); rebuildLauncherPositions()
        }
        loadWeather(); refreshAudioSinks()
    }
    onSampledPathChanged: rebuildLauncherPositions()
    onLaunchersChanged: rebuildLauncherPositions()
    onWidthChanged: sampledPath = buildPath(equation)
    onHeightChanged: sampledPath = buildPath(equation)
    onWeatherVisibleChanged: { persistVisibility(); sampledPath = buildPath(equation) }

    P5Support.DataSource {
        id: commandRunner
        engine: "executable"
        connectedSources: []
        function run(command) { connectSource(command) }
        onNewData: function(source, data) {
            if (data && data.stderr) root.equationMessage = String(data.stderr).trim().slice(0, 180)
            disconnectSource(source)
        }
    }

    P5Support.DataSource {
        id: launcherMetadataReader
        engine: "executable"
        connectedSources: []
        property var pendingPaths: ({})
        function request(path) {
            var helperUrl = Qt.resolvedUrl("../scripts/desktop_entry.py")
            var helperPath = decodeURIComponent(String(helperUrl).replace(/^file:\/\//, ""))
            var command = "python3 " + root.safeShell(helperPath) + " " + root.safeShell(path)
            pendingPaths[command] = path
            connectSource(command)
        }
        onNewData: function(source, data) {
            var path = pendingPaths[source]
            delete pendingPaths[source]
            disconnectSource(source)
            if (!path || !data || !data.stdout) return
            try {
                var metadata = JSON.parse(String(data.stdout))
                if (metadata.error) return
                var fallbackName = path.split("/").pop().replace(/\.desktop$/i, "").replace(/[-_]/g, " ")
                var index = root.launchers.findIndex(function(item) { return item.file === path })
                if (index < 0) return
                var updated = root.launchers.slice()
                updated[index] = {
                    name: metadata.name || fallbackName,
                    icon: metadata.icon || "application-x-executable",
                    file: path
                }
                root.launchers = updated
                root.saveLaunchers()
            } catch (e) {}
        }
    }

    P5Support.DataSource {
        id: audioWriter
        engine: "executable"
        connectedSources: root.equation === "soundwave" ? [root.audioSourceCommand()] : []
        onNewData: function(source, data) {
            disconnectSource(source)
        }
    }
    P5Support.DataSource {
        id: audioReader
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            root.audioPollRunning=false
            disconnectSource(source)
            if (!data || !data.stdout) return
            try {
                var frame=JSON.parse(String(data.stdout))
                if (frame.error) { root.audioStatus="Output unavailable: " + String(frame.error).slice(0,60); return }
                if (!Array.isArray(frame.levels) || frame.time === root.audioFrameTime) return
                root.audioFrameTime=frame.time
                root.audioSignalActive=frame.active === true
                root.audioLevels=frame.levels
                root.audioLastUpdate=Date.now()
                var active=frame.active === true
                var sinkLabel=root.audioSinkName || "default output"
                for (var k=0;k<root.audioSinks.length;k++) if (root.audioSinks[k].name === root.audioSinkName) sinkLabel=root.audioSinks[k].description
                root.audioStatus=active ? "Signal detected · " + sinkLabel : "Listening · no signal on " + sinkLabel
            } catch (e) {}
        }
    }
    P5Support.DataSource {
        id: sinkEnumerator
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            if (!data || !data.stdout) { disconnectSource(source); return }
            try {
                var result=JSON.parse(String(data.stdout))
                if (result.error) { root.audioStatus="Could not list audio outputs"; disconnectSource(source); return }
                var items=[{name:"",description:"Default · " + (result.sinks.find(function(s){return s.name===result.default}) || {description:"system output"}).description}]
                for (var i=0;i<result.sinks.length;i++) items.push(result.sinks[i])
                root.audioSinks=items
                if (root.audioSinkName && !result.sinks.some(function(s){return s.name===root.audioSinkName})) {
                    root.audioSinkName=""
                    plasmoid.configuration.audioSink=""
                }
            } catch (e) { root.audioStatus="Could not read audio outputs" }
            disconnectSource(source)
        }
    }
    Timer {
        interval: 6
        repeat: true
        running: root.equation === "soundwave"
        onTriggered: {
            root.pollAudioFrame()
            if ((root.audioLastUpdate > 0 && Date.now()-root.audioLastUpdate > 4000) || (root.audioLastUpdate === 0 && root.audioStartedAt > 0 && Date.now()-root.audioStartedAt > 4000))
                root.audioStatus="No monitor data · select an active output"
        }
    }
    Timer {
        // Approximately one update per 165 Hz display frame. Smooth audio
        // envelopes before repositioning icons to prevent spectral jitter.
        interval: 6
        repeat: true
        running: root.equation === "soundwave"
        onTriggered: {
            var now=Date.now(), dt=root.audioSmoothTime ? Math.min(0.05,(now-root.audioSmoothTime)/1000) : 0.006
            root.audioSmoothTime=now
            var next=root.audioVisualLevels.slice(), changed=false
            for (var i=0;i<root.audioLevels.length;i++) {
                var current=next[i]||0, target=root.audioLevels[i]||0
                var tau=target>current ? 0.035 : 0.07
                var value=current+(target-current)*(1-Math.exp(-dt/tau))
                if (Math.abs(value-current)>0.001) changed=true
                next[i]=value
            }
            if (next.length!==root.audioLevels.length) changed=true
            root.audioVisualLevels=next
            if (changed) root.rebuildLauncherPositions()
        }
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.equation === "soundwave"
        onTriggered: root.refreshAudioSinks()
    }
    Timer { id: pathTransitionTimer; interval: 700; repeat: false; onTriggered: root.pathTransitioning=false }

    property real temperature: NaN
    property real feelsLike: NaN
    property real high: NaN
    property real low: NaN
    property real humidity: NaN
    property real wind: NaN
    property int weatherCode: -1
    property string statusText: "Loading forecast…"
    property string updatedAt: ""

    function weatherDescription(code) {
        if (code === 0) return "Clear sky"
        if (code === 1) return "Mostly clear"
        if (code === 2) return "Partly cloudy"
        if (code === 3) return "Overcast"
        if (code === 45 || code === 48) return "Fog"
        if (code >= 51 && code <= 57) return "Drizzle"
        if (code >= 61 && code <= 67) return "Rain"
        if (code >= 71 && code <= 77) return "Snow"
        if (code >= 80 && code <= 82) return "Rain showers"
        if (code >= 85 && code <= 86) return "Snow showers"
        if (code >= 95) return "Thunderstorm"
        return "Weather unavailable"
    }
    function weatherEmoji(code) {
        if (code === 0 || code === 1) return "☀️"
        if (code === 2 || code === 3 || code === 45 || code === 48) return "☁️"
        if (code >= 71 && code <= 77 || code >= 85 && code <= 86) return "❄️"
        if (code >= 95) return "⛈️"
        if (code >= 51 && code <= 82) return "🌧️"
        return "🌤️"
    }
    function loadWeather() {
        var req = new XMLHttpRequest()
        req.open("GET", "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(root.weatherLatitude) + "&longitude=" + encodeURIComponent(root.weatherLongitude) + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=1")
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (req.status !== 200) { statusText = "Forecast connection unavailable"; return }
            try {
                var data = JSON.parse(req.responseText)
                temperature = data.current.temperature_2m
                feelsLike = data.current.apparent_temperature
                humidity = data.current.relative_humidity_2m
                wind = data.current.wind_speed_10m
                weatherCode = data.current.weather_code
                high = data.daily.temperature_2m_max[0]
                low = data.daily.temperature_2m_min[0]
                updatedAt = data.current.time.split("T")[1]
                statusText = weatherDescription(weatherCode)
            } catch (e) {
                statusText = "Forecast data unavailable"
            }
        }
        req.send()
    }
    function applyWeatherLocation() {
        var lat=Number(locationLatitude.text), lon=Number(locationLongitude.text)
        if (!Number.isFinite(lat) || !Number.isFinite(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
            equationMessage = "Enter a valid latitude (−90…90) and longitude (−180…180)."
            return
        }
        weatherLatitude=String(lat); weatherLongitude=String(lon)
        weatherPlace=locationName.text.trim() || (weatherLatitude + ", " + weatherLongitude)
        plasmoid.configuration.weatherLatitude=lat; plasmoid.configuration.weatherLongitude=lon
        plasmoid.configuration.weatherPlace=weatherPlace
        loadWeather(); locationSettingsOpen=false; equationMessage="Weather location updated."
    }
    Timer { interval: 900000; running: true; repeat: true; onTriggered: root.loadWeather() }

    Repeater {
        model: root.launchers
        delegate: Item {
            id: launcher
            required property int index
            required property var modelData
            readonly property var position: root.launcherCenter(index)
            width: 100
            height: 100
            x: position.x - width / 2
            y: position.y - height / 2
            Behavior on x { enabled: root.pathTransitioning; NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: root.pathTransitioning; NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }
            // Keep the path point visible at the actual screen boundary; the
            // applet viewport clips only the portion of the 100 px launcher
            // that extends beyond the edge.
            visible: position.x >= 0 && position.x <= root.width && position.y >= 0 && position.y <= root.height

            Kirigami.Icon {
                id: appIcon
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                width: 58
                height: 58
                source: launcher.modelData.icon
            }
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 34
                text: launcher.modelData.name
                color: "white"
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                style: Text.Outline
                styleColor: "#99000000"
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    var desktopFile = launcher.modelData.file
                    commandRunner.run("gio launch " + root.safeShell(desktopFile))
                }
            }
        }
    }

    Rectangle {
        id: weatherCard
        anchors.centerIn: parent
        width: 330
        height: root.weatherVisible ? 238 : 0
        visible: root.weatherVisible
        z: 50
        radius: 24
        color: "#bb111722"
        border.color: "#55ffffff"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Controls.Button {
                    text: "⚙"; Accessible.name: "Weather location settings"
                    Layout.preferredWidth: 30; Layout.preferredHeight: 28
                    onClicked: {
                        locationName.text=root.weatherPlace
                        locationLatitude.text=root.weatherLatitude
                        locationLongitude.text=root.weatherLongitude
                        root.locationSettingsOpen=true
                    }
                }
                Text { text: root.weatherPlace; color: "white"; font.pixelSize: 20; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; visible: root.showWeatherLocation }
                Controls.Button { text: "−"; Accessible.name: "Minimize weather"; Layout.preferredWidth: 30; Layout.preferredHeight: 28; onClicked: root.weatherVisible=false }
            }
            Text { text: Number.isFinite(root.temperature) ? Math.round(root.temperature) + "°F" : "—°"; color: "white"; font.pixelSize: 54; font.weight: Font.Light; Layout.alignment: Qt.AlignHCenter }
            Text { text: root.weatherEmoji(root.weatherCode) + "  " + root.statusText; color: "#e7ecf2"; font.pixelSize: 16; Layout.alignment: Qt.AlignHCenter }
            Text {
                text: Number.isFinite(root.high) ? "H " + Math.round(root.high) + "°   L " + Math.round(root.low) + "°   Feels " + Math.round(root.feelsLike) + "°" : ""
                color: "#c7d2df"; font.pixelSize: 13; Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: Number.isFinite(root.humidity) ? "Humidity " + Math.round(root.humidity) + "%   •   Wind " + Math.round(root.wind) + " mph" : ""
                color: "#c7d2df"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter
            }
            Text { text: root.updatedAt ? "Updated " + root.updatedAt : ""; color: "#9caabd"; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
        }
    }
    Rectangle {
        id: managerCard
        anchors.top: weatherCard.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: 440
        height: root.equation === "soundwave" ? 184 : 152
        visible: root.weatherVisible
        z: 50
        radius: 18
        color: "#bb111722"
        border.color: "#55ffffff"
        border.width: 1
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 5
            RowLayout {
                Layout.fillWidth: true
                Controls.ComboBox {
                    id: presetBox
                    Layout.preferredWidth: 128
                    model: ["ellipse", "y = x", "circle", "y = sin(x)", "spiral", "soundwave"]
                    currentIndex: root.equation === "custom" ? (root.equationText.toLowerCase().replace(/\s/g, "") === "y=x" ? 1 : root.equationText.toLowerCase().replace(/\s/g, "") === "y=sin(x)" ? 3 : -1) : root.equation === "line" ? 1 : root.equation === "circle" ? 2 : root.equation === "sine" ? 3 : root.equation === "spiral" ? 4 : root.equation === "soundwave" ? 5 : 0
                    delegate: Controls.ItemDelegate {
                        width: presetBox.width
                        height: 28
                        text: modelData
                    }
                    popup.height: 174
                    onActivated: root.applyEquation(currentText)
                }
                Controls.TextField {
                    id: equationInput
                    Layout.fillWidth: true
                    placeholderText: "Equation or preset"
                    text: root.equationText
                    onAccepted: root.applyEquation(text)
                }
                Controls.Button { text: "Apply"; onClicked: root.applyEquation(equationInput.text) }
            }
            RowLayout {
                Layout.fillWidth: true
                Controls.Button { text: "Add launchers"; onClicked: launcherPicker.open() }
                Controls.Button { text: "Refresh"; onClicked: { root.launchers = root.loadLaunchers(); root.equationMessage = "Launcher arrangement refreshed." } }
                Controls.ComboBox {
                    id: launcherSelect
                    Layout.fillWidth: true
                    model: root.launchers.map(function(item) { return item.name })
                }
                Controls.Button { text: "Remove"; enabled: root.launchers.length > 0; onClicked: root.removeLauncher(launcherSelect.currentIndex) }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.equation === "soundwave"
                Text { text: "Audio output"; color: "#c7d2df"; font.pixelSize: 11 }
                Controls.ComboBox {
                    id: audioSinkSelect
                    Layout.fillWidth: true
                    model: root.audioSinks
                    textRole: "description"
                    currentIndex: {
                        for (var i=0;i<root.audioSinks.length;i++) if (root.audioSinks[i].name === root.audioSinkName) return i
                        return 0
                    }
                    onActivated: function(index) {
                        root.audioSinkName=root.audioSinks[index].name
                        plasmoid.configuration.audioSink=root.audioSinkName
                        root.audioLevels=[]; root.audioLastUpdate=0; root.audioStartedAt=Date.now()
                        root.audioStatus="Connecting to " + root.audioSinks[index].description
                    }
                }
                Controls.Button { text: "↻"; Accessible.name: "Refresh audio outputs"; onClicked: root.refreshAudioSinks() }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: root.equationMessage + (root.audioStatus ? "   •   " + root.audioStatus : "") + (root.launchers.length ? "   •   " + root.launchers.length + " launchers" : "")
                    color: "#c7d2df"; font.pixelSize: 10; elide: Text.ElideRight
                }
                Text { text: "Auto"; color: "#c7d2df"; font.pixelSize: 10 }
                Controls.Slider {
                    id: autoRotationSlider
                    Layout.preferredWidth: 100
                    from: 0; to: 30; stepSize: 1
                    value: root.autoRotationRpm
                    onMoved: { root.autoRotationRpm=value; plasmoid.configuration.autoRotation=value }
                }
                Text { text: Math.round(root.autoRotationRpm) + " rpm"; color: "#c7d2df"; font.pixelSize: 10; Layout.preferredWidth: 42 }
            }
        }
    }

    Rectangle {
        id: locationSettingsScrim
        anchors.fill: parent
        visible: root.locationSettingsOpen
        z: 90
        color: "#55000000"
        MouseArea { anchors.fill: parent; onClicked: root.locationSettingsOpen=false }
    }
    Rectangle {
        id: locationSettingsPanel
        anchors.centerIn: parent
        width: 360
        height: 190
        visible: root.locationSettingsOpen
        z: 91
        radius: 14
        color: "#f0191524"
        border.color: "#70ffffff"
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 14; spacing: 7
            Text { text: "Weather location"; color: "white"; font.pixelSize: 16; font.weight: Font.DemiBold }
            Controls.TextField { id: locationName; Layout.fillWidth: true; placeholderText: "Location label"; text: root.weatherPlace }
            RowLayout {
                Layout.fillWidth: true
                Controls.TextField { id: locationLatitude; Layout.fillWidth: true; placeholderText: "Latitude"; text: root.weatherLatitude; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                Controls.TextField { id: locationLongitude; Layout.fillWidth: true; placeholderText: "Longitude"; text: root.weatherLongitude; inputMethodHints: Qt.ImhFormattedNumbersOnly }
            }
            RowLayout {
                Controls.CheckBox { text: "Show location name"; checked: root.showWeatherLocation; onToggled: { root.showWeatherLocation=checked; plasmoid.configuration.showWeatherLocation=checked } }
                Item { Layout.fillWidth: true }
                Controls.Button { text: "Apply"; onClicked: root.applyWeatherLocation() }
            }
        }
    }

    FileDialog {
        id: launcherPicker
        title: "Choose desktop launchers"
        nameFilters: ["Desktop launchers (*.desktop)"]
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            for (var i = 0; i < selectedFiles.length; ++i)
                root.addLauncher(selectedFiles[i])
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 108
        width: 40; height: 40; radius: 20
        color: "#bb111722"; border.color: "#55ffffff"
        visible: !root.weatherVisible
        z: 80
        Text { anchors.centerIn: parent; text: "☀"; color: "white"; font.pixelSize: 20 }
        MouseArea { anchors.fill: parent; onClicked: root.weatherVisible = true }
    }

    // Smoothly follow the mouse's angular speed, then coast to a stop on release.
    Timer {
        interval: 6
        repeat: true
        running: Math.abs(root.orbitVelocity) > 0.002 || root.orbitDragging || root.autoRotationRpm > 0
        onTriggered: {
            var target = root.orbitDragging ? root.dragVelocity : 0
            root.orbitVelocity += (target - root.orbitVelocity) * (root.orbitDragging ? 0.28 : 0.045)
            if (!root.orbitDragging && Math.abs(root.orbitVelocity) < 0.002)
                root.orbitVelocity = 0
            root.orbitRotation += (root.orbitVelocity + root.autoRotationRpm * 2*Math.PI / 60) * interval / 1000
        }
    }
    Timer {
        interval: 6
        repeat: true
        running: Math.abs(root.orbitVelocity) > 0.002 || root.orbitDragging || root.autoRotationRpm > 0
        onTriggered: root.rebuildLauncherPositions()
    }

    // This overlay owns the gesture so the spin continues even when the pointer
    // passes over an icon. A short click is routed to the launcher under it.
    MouseArea {
        id: orbitMouse
        anchors.fill: parent
        z: 1
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        property bool moved: false
        property int clickedLauncher: -1
        property real previousPathDistance: 0
        property real previousPointerX: 0
        property real previousPointerY: 0
        property real previousPointerTime: 0
        property real previousProjectionError: 0

        function nearestPathProjection(px, py, referenceDistance, continuityWindow) {
            var p = root.sampledPath, best = null, bestD2 = Infinity, fallback = null, fallbackD2 = Infinity
            if (p.length < 2 || root.pathLength <= 0) return {distance: 0, error: Infinity, continuous: false}
            for (var i=1; i<p.length; ++i) {
                var a=p[i-1], b=p[i], vx=b.x-a.x, vy=b.y-a.y
                var denom=vx*vx+vy*vy, t=denom ? Math.max(0,Math.min(1,((px-a.x)*vx+(py-a.y)*vy)/denom)) : 0
                var qx=a.x+t*vx, qy=a.y+t*vy, dx=px-qx, dy=py-qy, d2=dx*dx+dy*dy
                var distance=a.d+t*(b.d-a.d)
                if (d2 < fallbackD2) { fallbackD2=d2; fallback={distance:distance,error:Math.sqrt(d2),continuous:false} }
                if (referenceDistance !== undefined) {
                    var progress=distance-referenceDistance
                    if (progress > root.pathLength/2) progress -= root.pathLength
                    if (progress < -root.pathLength/2) progress += root.pathLength
                    if (Math.abs(progress) > continuityWindow) continue
                }
                if (d2 < bestD2) {
                    bestD2=d2
                    best={distance:distance,error:Math.sqrt(d2),continuous:true}
                }
            }
            return best || fallback
        }
        function launcherAt(px, py) {
            for (var i = 0; i < root.launchers.length; ++i) {
                var p = root.launcherCenter(i)
                var lx = p.x
                var ly = p.y
                if (Math.abs(px - lx) <= 50 && Math.abs(py - ly) <= 50) return i
            }
            return -1
        }
        onPressed: function(mouse) {
            var overManager=managerCard.visible && mouse.x>=managerCard.x && mouse.x<=managerCard.x+managerCard.width && mouse.y>=managerCard.y && mouse.y<=managerCard.y+managerCard.height
            var overWeather=weatherCard.visible && mouse.x>=weatherCard.x && mouse.x<=weatherCard.x+weatherCard.width && mouse.y>=weatherCard.y && mouse.y<=weatherCard.y+weatherCard.height
            var onLauncher = launcherAt(mouse.x, mouse.y) >= 0
            var projection = nearestPathProjection(mouse.x, mouse.y)
            // Only launcher hits and the visible curve can start an orbit drag.
            // Empty areas (including settings sliders) should never grab Plasma's desktop.
            if (root.locationSettingsOpen || overManager || overWeather || (!onLauncher && projection.error > 36)) {
                root.orbitDragging=false
                root.dragVelocity=0
                clickedLauncher=-1
                mouse.accepted=true
                return
            }
            moved = false
            clickedLauncher = launcherAt(mouse.x, mouse.y)
            root.orbitDragging = root.pathLength > 0
            previousPathDistance = projection.distance
            previousProjectionError = projection.error
            previousPointerX = mouse.x; previousPointerY = mouse.y
            previousPointerTime = Date.now(); root.dragVelocity = 0
        }
        onPositionChanged: function(mouse) {
            if (!(mouse.buttons & Qt.LeftButton) || !root.orbitDragging) return
            var now = Date.now()
            var dt = Math.max(0.001, (now - previousPointerTime) / 1000)
            var dx=mouse.x-previousPointerX, dy=mouse.y-previousPointerY
            var travel=Math.hypot(dx,dy)
            var window=Math.max(220,travel*2+90)
            var projection=nearestPathProjection(mouse.x,mouse.y,previousPathDistance,window)
            var delta=0
            if (previousProjectionError <= 220 && projection.error <= 220 && projection.continuous) {
                delta=projection.distance-previousPathDistance
                if (delta > root.pathLength/2) delta -= root.pathLength
                if (delta < -root.pathLength/2) delta += root.pathLength
            }
            if (Math.hypot(mouse.x-previousPointerX, mouse.y-previousPointerY) > 4) moved = true
            root.dragVelocity = Math.max(-14, Math.min(14, delta * 2*Math.PI / (root.pathLength*dt)))
            previousPathDistance = projection.distance
            previousProjectionError=projection.error
            previousPointerX = mouse.x; previousPointerY = mouse.y
            previousPointerTime = now
        }
        onReleased: {
            root.orbitDragging = false
            root.dragVelocity = 0
            if (!moved && clickedLauncher >= 0) {
                var desktopFile = root.launchers[clickedLauncher].file
                commandRunner.run("gio launch " + root.safeShell(desktopFile))
            }
        }
        onCanceled: {
            root.orbitDragging = false
            root.dragVelocity = 0
        }
    }
}
