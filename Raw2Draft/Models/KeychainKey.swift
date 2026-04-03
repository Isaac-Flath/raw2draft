import Foundation

enum KeychainKey: String, CaseIterable {
    case lemonfoxApiKey = "LEMONFOX_API_KEY"
    case openaiApiKey = "OPENAI_API_KEY"
    case geminiApiKey = "GEMINI_API_KEY"
    case uploadpostApiKey = "UPLOADPOST_API_KEY"
    case assemblyaiApiKey = "ASSEMBLYAI_API_KEY"
    case awsAccessKeyId = "AWS_ACCESS_KEY_ID"
    case awsSecretAccessKey = "AWS_SECRET_ACCESS_KEY"
    case awsRegion = "AWS_REGION"
    case s3Bucket = "S3_BUCKET"

    var displayName: String {
        switch self {
        case .lemonfoxApiKey: return "LemonFox API Key"
        case .openaiApiKey: return "OpenAI API Key"
        case .geminiApiKey: return "Gemini API Key"
        case .uploadpostApiKey: return "UploadPost API Key"
        case .assemblyaiApiKey: return "AssemblyAI API Key"
        case .awsAccessKeyId: return "AWS Access Key ID"
        case .awsSecretAccessKey: return "AWS Secret Access Key"
        case .awsRegion: return "AWS Region"
        case .s3Bucket: return "S3 Bucket"
        }
    }

    var hint: String {
        switch self {
        case .lemonfoxApiKey: return "Used for transcription"
        case .openaiApiKey: return "Used for AI generation"
        case .geminiApiKey: return "Used for AI generation"
        case .uploadpostApiKey: return "Used for social media scheduling"
        case .assemblyaiApiKey: return "Used for video transcription"
        case .awsAccessKeyId: return "Used for image hosting"
        case .awsSecretAccessKey: return "Used for image hosting"
        case .awsRegion: return "Used for image hosting"
        case .s3Bucket: return "Used for image hosting"
        }
    }

    /// Whether this key contains a secret value (shown as SecureField vs TextField).
    var isSecret: Bool {
        switch self {
        case .awsRegion, .s3Bucket: return false
        default: return true
        }
    }

    /// Keys shown in Settings UI and used for environment variable hydration.
    static let apiKeys: [KeychainKey] = allCases

    /// Alias for backward compatibility.
    static var environmentKeys: [KeychainKey] { apiKeys }
}
