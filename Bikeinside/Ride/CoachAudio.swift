import AppKit
import AVFoundation
import BikeinsideCore

/// Spoken coaching (Swedish voice), short cue sounds, and wind noise that
/// follows your speed.
@MainActor
final class CoachAudio {
    var voiceEnabled: Bool
    var soundsEnabled: Bool {
        didSet { if !soundsEnabled { wind.setLevel(0) } }
    }

    private let synth = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private let wind = WindNoise()
    private var lastSpoken = Date.distantPast
    private var lastCountdown: Int?
    private var spokeHalfMinute = false
    private var lastStep: Int?
    private var lastGhostKm = 0

    init(voice: Bool, sounds: Bool) {
        voiceEnabled = voice
        soundsEnabled = sounds
        self.voice = AVSpeechSynthesisVoice(language: "sv-SE")
        if sounds { wind.start() }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        wind.stop()
    }

    func say(_ text: String, priority: Bool = false) {
        guard voiceEnabled else { return }
        if synth.isSpeaking {
            guard priority else { return }
            synth.stopSpeaking(at: .word)
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = 0.5
        u.volume = 0.9
        synth.speak(u)
        lastSpoken = Date()
    }

    func play(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// Called every frame.
    func update(engine: RideEngine, paused: Bool, ftp: Double) {
        if soundsEnabled {
            // wind grows with the square of speed; silent when stopped or paused
            let v = paused ? 0 : engine.speed
            wind.setLevel(Float(min(pow(v / 14, 2), 1)) * 0.22)
        }
        guard !paused else { return }

        if let ws = engine.workoutStatus, !ws.isFinished, let idx = ws.stepIndex {
            if idx != lastStep {
                lastStep = idx
                spokeHalfMinute = false
                lastCountdown = nil
                let step = ws.workout.steps[idx]
                if idx > 0 {
                    let target = step.isFree ? "kör efter känsla" : "\(Int((ws.targetWatts ?? 0).rounded())) watt"
                    say("\(step.label). \(target) i \(Self.spokenDuration(step.duration)).", priority: true)
                }
            }
            let remaining = ws.remainingInStep
            if remaining <= 31, remaining > 29, !spokeHalfMinute, ws.workout.steps[idx].duration >= 90 {
                spokeHalfMinute = true
                if let next = ws.nextStep {
                    let nt = next.isFree ? "fritt" : "\(Int((next.start.watts(ftp: ftp) * engine.workoutIntensity).rounded())) watt"
                    say("Trettio sekunder kvar. Sedan \(next.label.lowercased()), \(nt).")
                } else {
                    say("Trettio sekunder kvar av passet.")
                }
            }
            let n = Int(remaining.rounded(.up))
            if n <= 3, n >= 1, n != lastCountdown, ws.nextStep != nil {
                lastCountdown = n
                play("Tink")
            }
        }

        if let gap = engine.ghostGapSeconds {
            let km = Int(engine.distance / 1000)
            if km > lastGhostKm {
                lastGhostKm = km
                let s = Int(abs(gap).rounded())
                if s >= 1 { say(gap >= 0 ? "Du ligger \(s) sekunder före spöket." : "Spöket leder med \(s) sekunder.") }
            }
        }
    }

    func handle(_ e: RideEvent, route: Route) {
        switch e {
        case .segmentStarted(let s):
            if s.kind == .climb {
                let g = route.averageGrade(from: s.startDistance, to: s.endDistance)
                say("Klättring, \(s.name). \(Int(s.length)) meter, \(Int((g * 100).rounded())) procent.")
            } else {
                say("Spurt, \(s.name). Ge allt!")
            }
        case .segmentFinished(let r):
            if r.isPersonalBest {
                play("Glass")
                say("Nytt personbästa på \(r.name)!", priority: true)
            }
        case .lapCompleted(let lap, let secs):
            play("Hero")
            say("Varv \(lap) klart på \(Self.spokenDuration(secs)).")
        case .workoutFinished:
            play("Hero")
            say("Passet är klart. Snyggt jobbat!", priority: true)
        case .workoutStep, .kilometer:
            break
        }
    }

    static func spokenDuration(_ s: Double) -> String {
        let total = Int(s.rounded())
        let m = total / 60, sec = total % 60
        switch (m, sec) {
        case (0, _): return "\(sec) sekunder"
        case (_, 0): return m == 1 ? "en minut" : "\(m) minuter"
        default: return "\(m) minuter och \(sec) sekunder"
        }
    }
}

/// Soft filtered noise that sounds like air rushing past.
final class WindNoise: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let lock = NSLock()
    private var target: Float = 0
    private var level: Float = 0
    private var lowpass: Float = 0
    private var seed: UInt32 = 22222

    func start() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sr = Float(format.sampleRate > 0 ? format.sampleRate : 44100)
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self else { return noErr }
            self.lock.lock()
            let goal = self.target
            self.lock.unlock()
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let alpha: Float = 1 - exp(-2 * .pi * 600 / sr) // ~600 Hz low-pass
            for frame in 0..<Int(frameCount) {
                self.level += (goal - self.level) * 0.0005
                self.seed = self.seed &* 1_664_525 &+ 1_013_904_223
                let white = Float(Int32(bitPattern: self.seed)) / Float(Int32.max)
                self.lowpass += alpha * (white - self.lowpass)
                let sample = self.lowpass * self.level
                for b in buffers {
                    b.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        source = node
        let mono = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: format.channelCount > 0 ? format.channelCount : 2)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        try? engine.start()
    }

    func setLevel(_ v: Float) {
        lock.lock()
        target = v
        lock.unlock()
    }

    func stop() {
        engine.stop()
    }
}
