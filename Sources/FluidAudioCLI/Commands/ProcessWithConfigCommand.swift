#if os(macOS)
import AVFoundation
import FluidAudio

/// Handler for the 'process-with-config' command - processes a single audio file with custom config
enum ProcessWithConfigCommand {
    private static let logger = AppLogger(category: "ProcessWithConfig")
    
    static func run(arguments: [String]) async {
        guard !arguments.isEmpty else {
            logger.error("No audio file specified")
            printUsage()
            exit(1)
        }

        let audioFile = arguments[0]
        var threshold: Float = 0.7
        var numClusters: Int = -1  // -1 for automatic
        var maxSpeakers: Int = -1  // -1 for unlimited
        var debugMode = false
        var outputFile: String?

        // Parse remaining arguments
        var i = 1
        while i < arguments.count {
            switch arguments[i] {
            case "--threshold":
                if i + 1 < arguments.count {
                    threshold = Float(arguments[i + 1]) ?? 0.7
                    i += 1
                }
            case "--num-clusters":
                if i + 1 < arguments.count {
                    numClusters = Int(arguments[i + 1]) ?? -1
                    i += 1
                }
            case "--max-speakers":
                if i + 1 < arguments.count {
                    maxSpeakers = Int(arguments[i + 1]) ?? -1
                    i += 1
                }
            case "--debug":
                debugMode = true
            case "--output":
                if i + 1 < arguments.count {
                    outputFile = arguments[i + 1]
                    i += 1
                }
            default:
                logger.warning("Unknown option: \(arguments[i])")
            }
            i += 1
        }

        logger.info("🎵 Processing audio file: \(audioFile)")
        logger.info("   Clustering threshold: \(threshold)")
        logger.info("   Number of clusters: \(numClusters == -1 ? "automatic" : String(numClusters))")
        logger.info("   Max speakers: \(maxSpeakers == -1 ? "unlimited" : String(maxSpeakers))")

        // Create config with custom parameters
        let config = DiarizerConfig(
            clusteringThreshold: threshold,
            numClusters: numClusters,
            maxSpeakers: maxSpeakers,
            debugMode: debugMode
        )

        let manager = DiarizerManager(config: config)

        do {
            let models = try await DiarizerModels.downloadIfNeeded()
            manager.initialize(models: models)
            logger.info("Models initialized")
        } catch {
            logger.error("Failed to initialize models: \(error)")
            exit(1)
        }

        // Load and process audio file
        do {
            let audioSamples = try await AudioProcessor.loadAudioFile(path: audioFile)
            logger.info("Loaded audio: \(audioSamples.count) samples")

            let startTime = Date()
            let result = try manager.performCompleteDiarization(
                audioSamples, sampleRate: 16000)
            let processingTime = Date().timeIntervalSince(startTime)

            let duration = Float(audioSamples.count) / 16000.0
            let rtfx = duration / Float(processingTime)

            logger.info("Diarization completed in \(String(format: "%.1f", processingTime))s")
            logger.info("   Real-time factor (RTFx): \(String(format: "%.2f", rtfx))x")
            logger.info("   Found \(result.segments.count) segments")
            logger.info("   Detected speakers: \(Set(result.segments.map { $0.speakerId }).count)")

            // Create output JSON
            let outputData: [String: Any] = [
                "video_id": URL(fileURLWithPath: audioFile).deletingPathExtension().lastPathComponent,
                "duration": duration,
                "processing_time": processingTime,
                "rtfx": rtfx,
                "speakers": Array(Set(result.segments.map { $0.speakerId })).sorted(),
                "segments": result.segments.map { segment in
                    [
                        "start": segment.startTimeSeconds,
                        "end": segment.endTimeSeconds,
                        "duration": segment.endTimeSeconds - segment.startTimeSeconds,
                        "speaker": segment.speakerId
                    ]
                }
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: outputData, options: .prettyPrinted)
            
            if let outputFile = outputFile {
                try jsonData.write(to: URL(fileURLWithPath: outputFile))
                logger.info("Results saved to: \(outputFile)")
            } else {
                print(String(data: jsonData, encoding: .utf8) ?? "Error encoding JSON")
            }

        } catch {
            logger.error("Failed to process audio file: \(error)")
            exit(1)
        }
    }
    
    private static func printUsage() {
        print("""
        Usage: fluidaudio process-with-config <audio_file> [options]
        
        Options:
            --threshold <value>     Clustering threshold (0.0-1.0, default: 0.7)
            --num-clusters <count>  Expected number of speakers (-1 for automatic, default: -1)
            --max-speakers <count>  Maximum number of speakers allowed (-1 for unlimited, default: -1)
            --output <file>         Output JSON file (default: stdout)
            --debug                 Enable debug output
        """)
    }
}

#endif
